package engine

import (
	"bytes"
	"context"
	"crypto/sha256"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/young-st511/worklink/internal/model"
	"github.com/young-st511/worklink/internal/remote"
	"github.com/young-st511/worklink/internal/storage"
	"github.com/young-st511/worklink/internal/transport"
)

type localConnection struct{ s *storage.Store }

func (l *localConnection) Close()                                          {}
func (l *localConnection) Forward(context.Context, model.Port, bool) error { return nil }
func (l *localConnection) Call(ctx context.Context, q remote.Request, r io.Reader) (remote.Response, error) {
	switch q.Op {
	case "exists":
		i, e := l.s.Verify(q.ID)
		if os.IsNotExist(e) {
			return remote.Response{}, nil
		}
		return remote.Response{Exists: e == nil, Image: &i}, e
	case "upload":
		i, e := l.s.Receive(q.ID, q.Extension, q.SHA256, q.Size, r)
		return remote.Response{Image: &i}, e
	case "check":
		return remote.Response{Checks: map[string]bool{}}, nil
	}
	return remote.Response{}, nil
}
func TestACKDeletesOnlyQueueCopy(t *testing.T) {
	root := t.TempDir()
	inbox, _ := storage.Open(t.TempDir(), model.DefaultConfig().Limits)
	complete := make(chan Event, 1)
	e, err := New(root, func(context.Context, model.Host) (transport.Connection, error) { return &localConnection{inbox}, nil }, func(event Event) {
		if event.Kind == "upload_complete" {
			complete <- event
		}
	})
	if err != nil {
		t.Fatal(err)
	}
	c := model.DefaultConfig()
	c.Hosts = []model.Host{{Name: "test", Helper: "/tmp/helper"}}
	c.ImageHost = "test"
	if err = e.SaveConfig(c); err != nil {
		t.Fatal(err)
	}
	source := filepath.Join(t.TempDir(), "image.png")
	os.WriteFile(source, []byte{0, 255, 3}, 0600)
	e.SetOn(true)
	defer e.SetOn(false)
	j, err := e.Enqueue(source, "png", 41)
	if err != nil {
		t.Fatal(err)
	}
	select {
	case event := <-complete:
		if event.Job == nil || event.Job.ID != j.ID {
			t.Fatal(event)
		}
		if _, err = os.Stat(source); err != nil {
			t.Fatal("original source deleted")
		}
		if _, err = os.Stat(e.queuePath(j)); !os.IsNotExist(err) {
			t.Fatal("queue retained after completion event")
		}
	case <-time.After(3 * time.Second):
		t.Fatal("upload did not complete", e.Snapshot())
	}
}
func TestOffAndRestartDoNotSend(t *testing.T) {
	root := t.TempDir()
	calls := 0
	e, err := New(root, func(context.Context, model.Host) (transport.Connection, error) { calls++; return nil, io.EOF }, func(Event) {})
	if err != nil {
		t.Fatal(err)
	}
	if e.Snapshot().On {
		t.Fatal("starts ON")
	}
	source := filepath.Join(t.TempDir(), "image.png")
	os.WriteFile(source, []byte{1}, 0600)
	if _, err = e.Enqueue(source, "png", 1); err == nil {
		t.Fatal("OFF accepted capture")
	}
	if calls != 0 {
		t.Fatal("OFF connected")
	}
}

func (l *localConnection) Download(ctx context.Context, q remote.Request, dest io.Writer) (remote.Response, error) {
	i, err := l.s.Verify(q.ID)
	if err != nil {
		return remote.Response{}, err
	}
	src, err := os.Open(i.Path)
	if err != nil {
		return remote.Response{}, err
	}
	defer src.Close()
	_, err = io.Copy(dest, src)
	return remote.Response{Image: &i}, err
}
func TestRestoreOriginalAndExpiry(t *testing.T) {
	inbox, _ := storage.Open(t.TempDir(), model.DefaultConfig().Limits)
	data := []byte{0, 255, 1, 4}
	id := model.NewID()
	image, err := inbox.Receive(id, "png", fmt.Sprintf("%x", sha256.Sum256(data)), int64(len(data)), bytes.NewReader(data))
	if err != nil {
		t.Fatal(err)
	}
	e, _ := New(t.TempDir(), nil, func(Event) {})
	e.state.On = true
	e.state.Generation = 3
	e.state.Config.Hosts = []model.Host{{Name: "test", Helper: "/tmp/helper"}}
	e.state.Jobs = []Job{{Image: image, RemotePath: image.Path}}
	e.state.Jobs[0].Host = "test"
	peer := &peer{connection: &localConnection{inbox}}
	e.peers["test"] = peer
	restored, err := e.RestoreOriginal(id)
	if err != nil {
		t.Fatal(err)
	}
	got, err := os.ReadFile(restored.Path)
	if err != nil || !bytes.Equal(got, data) {
		t.Fatal(got, err)
	}
	os.Remove(restored.Path)
	os.Remove(image.Path)
	if _, err = e.RestoreOriginal(id); err == nil {
		t.Fatal("expired image restored")
	}
	files, _ := os.ReadDir(filepath.Join(e.store.Root, "restores"))
	if len(files) != 0 {
		t.Fatal("failed download leaked temp files")
	}
	e.state.On = false
	if _, err = e.RestoreOriginal(id); err == nil {
		t.Fatal("OFF download accepted")
	}
}

func TestQueuedCaptureWaitsForFailedConnection(t *testing.T) {
	e, err := New(t.TempDir(), nil, func(Event) {})
	if err != nil {
		t.Fatal(err)
	}
	e.state.On = true
	e.state.Generation = 1
	e.state.Jobs = []Job{{Image: model.Image{ID: model.NewID(), Host: "test", Status: "queued", Generation: 1, CreatedAt: time.Now(), Extension: "png"}}}
	e.peers["test"] = &peer{}
	e.sendNext(context.Background(), 1)
	if e.Snapshot().Jobs[0].Status != "queued" {
		t.Fatal("disconnected capture no longer queued")
	}
}
