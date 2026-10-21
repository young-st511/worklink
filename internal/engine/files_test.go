package engine

import (
	"context"
	"io"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/young-st511/worklink/internal/model"
	"github.com/young-st511/worklink/internal/remote"
	"github.com/young-st511/worklink/internal/storage"
)

type fileConnection struct {
	localConnection
	store *storage.Store
	block bool
}

func (f *fileConnection) UploadFile(ctx context.Context, q remote.Request, r io.Reader) (remote.Response, error) {
	if f.block {
		<-ctx.Done()
		return remote.Response{}, ctx.Err()
	}
	v, err := f.store.ReceiveFile(q.ID, q.FileName, q.SHA256, q.Size, r)
	return remote.Response{File: &v}, err
}
func TestExplicitFilesPreserveNamesAndBytes(t *testing.T) {
	e, _ := New(t.TempDir(), nil, func(Event) {})
	s, _ := storage.Open(t.TempDir(), model.DefaultConfig().Limits)
	e.state.On = true
	e.state.Config.ImageHost = "office"
	e.state.Hosts = []HostState{{Host: "office", Status: "connected"}}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	e.session = ctx
	e.peers["office"] = &peer{connection: &fileConnection{store: s}}
	path := filepath.Join(t.TempDir(), "원본 file.txt")
	os.WriteFile(path, []byte("original bytes"), 0600)
	files, err := e.SendFiles([]string{path})
	if err != nil || len(files) != 1 {
		t.Fatal(files, err)
	}
	data, _ := os.ReadFile(files[0].Path)
	if string(data) != "original bytes" || files[0].Name != "원본 file.txt" {
		t.Fatal(files)
	}
	link := filepath.Join(t.TempDir(), "symlink")
	os.Symlink(path, link)
	if _, err = e.SendFiles([]string{link}); err == nil {
		t.Fatal("symlink accepted")
	}
	e.state.On = false
	if _, err = e.SendFiles([]string{path}); err == nil {
		t.Fatal("OFF file accepted")
	}
}
func TestFileBatchCancellationAndJournalFailure(t *testing.T) {
	e, _ := New(t.TempDir(), nil, func(Event) {})
	s, _ := storage.Open(t.TempDir(), model.DefaultConfig().Limits)
	e.state.On = true
	e.state.Config.ImageHost = "office"
	e.state.Hosts = []HostState{{Host: "office", Status: "connected"}}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	e.session = ctx
	e.peers["office"] = &peer{connection: &fileConnection{store: s, block: true}}
	path := filepath.Join(t.TempDir(), "fixture.txt")
	os.WriteFile(path, []byte("source"), 0600)
	done := make(chan error, 1)
	go func() { _, err := e.SendFiles([]string{path}); done <- err }()
	for i := 0; i < 200; i++ {
		snap := e.Snapshot()
		if len(snap.Files) > 0 && snap.Files[0].Status == "sending" {
			break
		}
		time.Sleep(5 * time.Millisecond)
	}
	e.CancelFiles()
	select {
	case err := <-done:
		if err == nil {
			t.Fatal("cancelled transfer succeeded")
		}
	case <-time.After(time.Second):
		t.Fatal("cancel did not stop batch")
	}
	if e.Snapshot().Files[0].Status != "cancelled" {
		t.Fatal(e.Snapshot())
	}
	data, _ := os.ReadFile(path)
	if string(data) != "source" {
		t.Fatal("source mutated")
	}
	history := filepath.Join(e.store.Root, "file-transfers.json")
	os.Remove(history)
	os.Mkdir(history, 0700)
	if _, err := e.SendFiles([]string{path}); err == nil {
		t.Fatal("history failure ignored")
	}
}
func TestOffCancelsFileBatchAndDoesNotResume(t *testing.T) {
	e, _ := New(t.TempDir(), nil, func(Event) {})
	s, _ := storage.Open(t.TempDir(), model.DefaultConfig().Limits)
	e.state.On = true
	e.state.Config.ImageHost = "office"
	e.state.Hosts = []HostState{{Host: "office", Status: "connected"}}
	ctx, cancel := context.WithCancel(context.Background())
	e.session = ctx
	e.cancel = cancel
	e.peers["office"] = &peer{connection: &fileConnection{store: s, block: true}}
	path := filepath.Join(t.TempDir(), "fixture.txt")
	os.WriteFile(path, []byte("source"), 0600)
	done := make(chan error, 1)
	go func() { _, err := e.SendFiles([]string{path}); done <- err }()
	for i := 0; i < 200; i++ {
		snap := e.Snapshot()
		if len(snap.Files) > 0 && snap.Files[0].Status == "sending" {
			break
		}
		time.Sleep(5 * time.Millisecond)
	}
	e.SetOn(false)
	select {
	case err := <-done:
		if err == nil {
			t.Fatal("OFF batch succeeded")
		}
	case <-time.After(time.Second):
		t.Fatal("OFF did not cancel")
	}
	reloaded, err := New(e.store.Root, nil, func(Event) {})
	if err != nil {
		t.Fatal(err)
	}
	if reloaded.Snapshot().On || reloaded.Snapshot().Files[0].Status != "cancelled" {
		t.Fatal(reloaded.Snapshot())
	}
	files, _ := s.ListFiles()
	if len(files) != 0 {
		t.Fatal("cancelled batch sent data")
	}
}
