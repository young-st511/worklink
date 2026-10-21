package storage

import (
	"bytes"
	"crypto/sha256"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sync"
	"testing"
	"time"

	"github.com/young-st511/worklink/internal/model"
)

func TestFilesOriginalQuotaAndCleanup(t *testing.T) {
	s, err := Open(t.TempDir(), model.DefaultConfig().Limits)
	if err != nil {
		t.Fatal(err)
	}
	for _, data := range [][]byte{[]byte("original\x00bytes"), {}} {
		hash := fmt.Sprintf("%x", sha256.Sum256(data))
		id := model.NewID()
		f, err := s.ReceiveFile(id, "원본 sample.txt", hash, int64(len(data)), bytes.NewReader(data))
		if err != nil {
			t.Fatal(err)
		}
		got, _ := os.ReadFile(f.Path)
		if !bytes.Equal(got, data) || filepath.Base(f.Path) != "원본 sample.txt" {
			t.Fatal(f)
		}
		if _, err = s.ReceiveFile(id, f.Name, hash, f.Size, bytes.NewReader(data)); err != nil {
			t.Fatal(err)
		}
	}
	all, err := s.ListFiles()
	if err != nil || len(all) != 2 {
		t.Fatal(all, err)
	}
	removed, err := s.Cleanup(time.Now().Add(25*time.Hour), false)
	if err != nil || len(removed) != 2 {
		t.Fatal(removed, err)
	}
	for _, f := range all {
		if _, err := os.Stat(f.Path); !os.IsNotExist(err) {
			t.Fatal(err)
		}
	}
}
func TestFileRejectsUnsafeNamesHashAndQuota(t *testing.T) {
	s, _ := Open(t.TempDir(), model.DefaultConfig().Limits)
	data := []byte("abc")
	hash := fmt.Sprintf("%x", sha256.Sum256(data))
	for _, name := range []string{"../escape", "a/b", ".", "a\nb", ""} {
		if _, err := s.ReceiveFile(model.NewID(), name, hash, 3, bytes.NewReader(data)); err == nil {
			t.Fatal(name)
		}
	}
	if _, err := s.ReceiveFile(model.NewID(), "valid", hash, 3, bytes.NewReader([]byte("bad"))); err == nil {
		t.Fatal("hash mismatch accepted")
	}
	s.Limits.InboxBytes = 2
	if _, err := s.ReceiveFile(model.NewID(), "valid", hash, 3, bytes.NewReader(data)); err == nil {
		t.Fatal("quota exceeded")
	}
}

// A slow file must not hold the commit lock and block automatic captures.
func TestFileStreamingDoesNotBlockImageReceive(t *testing.T) {
	s, _ := Open(t.TempDir(), model.DefaultConfig().Limits)
	r, w := io.Pipe()
	entered := make(chan struct{})
	reader := &signalReader{Reader: r, entered: entered}
	done := make(chan error, 1)
	data := []byte("file")
	hash := fmt.Sprintf("%x", sha256.Sum256(data))
	go func() { _, err := s.ReceiveFile(model.NewID(), "slow.txt", hash, 4, reader); done <- err }()
	select {
	case <-entered:
	case <-time.After(time.Second):
		t.Fatal("file receiver did not begin streaming")
	}
	// The file is waiting for its first network byte while the image commits.
	image := []byte("image")
	imageHash := fmt.Sprintf("%x", sha256.Sum256(image))
	imageDone := make(chan error, 1)
	go func() {
		_, err := s.Receive(model.NewID(), "png", imageHash, int64(len(image)), bytes.NewReader(image))
		imageDone <- err
	}()
	select {
	case err := <-imageDone:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(time.Second):
		t.Fatal("file stream blocked image commit")
	}
	w.Write(data)
	w.Close()
	if err := <-done; err != nil {
		t.Fatal(err)
	}
}
func TestCombinedFileImageQuota(t *testing.T) {
	limits := model.DefaultConfig().Limits
	limits.InboxBytes = 5
	s, _ := Open(t.TempDir(), limits)
	data := []byte("file")
	hash := fmt.Sprintf("%x", sha256.Sum256(data))
	if _, err := s.ReceiveFile(model.NewID(), "fixture", hash, 4, bytes.NewReader(data)); err != nil {
		t.Fatal(err)
	}
	if _, err := s.Receive(model.NewID(), "png", hash, 4, bytes.NewReader(data)); err == nil {
		t.Fatal("image ignored file quota")
	}
}
func TestCleanupCrashRemnantsPreservesUnknownAndLive(t *testing.T) {
	s, _ := Open(t.TempDir(), model.DefaultConfig().Limits)
	now := time.Now()
	stale := filepath.Join(s.Root, "staging", "worklink-file-upload-stale")
	live := filepath.Join(s.Root, "staging", "worklink-file-upload-live")
	unknown := filepath.Join(s.Root, "staging", "other.png")
	for _, path := range []string{stale, live, unknown} {
		os.WriteFile(path, []byte("partial"), 0600)
	}
	os.Chtimes(stale, now.Add(-25*time.Hour), now.Add(-25*time.Hour))
	os.Chtimes(unknown, now.Add(-25*time.Hour), now.Add(-25*time.Hour))
	orphan := filepath.Join(s.Root, "file-inbox", model.NewID())
	os.Mkdir(orphan, 0700)
	path := filepath.Join(orphan, "original.txt")
	os.WriteFile(path, []byte("partial"), 0600)
	os.Chtimes(path, now.Add(-25*time.Hour), now.Add(-25*time.Hour))
	os.Chtimes(orphan, now.Add(-25*time.Hour), now.Add(-25*time.Hour))
	id := filepath.Base(orphan)
	if err := AtomicJSON(s.filePending(id), model.File{ID: id, Name: "original.txt", CreatedAt: now.Add(-25 * time.Hour), Path: path, Size: 7, SHA256: fmt.Sprintf("%x", sha256.Sum256([]byte("partial")))}); err != nil {
		t.Fatal(err)
	}
	unknownDir := filepath.Join(s.Root, "file-inbox", model.NewID())
	os.Mkdir(unknownDir, 0700)
	unknownFile := filepath.Join(unknownDir, "user.txt")
	os.WriteFile(unknownFile, []byte("user"), 0600)
	os.Chtimes(unknownFile, now.Add(-25*time.Hour), now.Add(-25*time.Hour))
	os.Chtimes(unknownDir, now.Add(-25*time.Hour), now.Add(-25*time.Hour))
	removed, err := s.Cleanup(now, false)
	if err != nil || len(removed) != 2 {
		t.Fatal(removed, err)
	}
	for _, path := range []string{stale, orphan} {
		if _, err := os.Stat(path); !os.IsNotExist(err) {
			t.Fatal("stale remnant retained", path, err)
		}
	}
	for _, path := range []string{live, unknown, unknownFile} {
		if _, err := os.Stat(path); err != nil {
			t.Fatal("unowned/live file removed", err)
		}
	}
}

type signalReader struct {
	io.Reader
	entered chan struct{}
	once    sync.Once
}

func (r *signalReader) Read(b []byte) (int, error) {
	r.once.Do(func() { close(r.entered) })
	return r.Reader.Read(b)
}
