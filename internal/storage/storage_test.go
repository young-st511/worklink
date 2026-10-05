package storage

import (
	"bytes"
	"crypto/sha256"
	"fmt"
	"github.com/young-st511/worklink/internal/model"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestOriginalAndRetry(t *testing.T) {
	s, _ := Open(t.TempDir(), model.DefaultConfig().Limits)
	b := []byte{0, 255, 1, 2, 3}
	h := fmt.Sprintf("%x", sha256.Sum256(b))
	id := model.NewID()
	i, e := s.Receive(id, "png", h, int64(len(b)), bytes.NewReader(b))
	if e != nil {
		t.Fatal(e)
	}
	got, _ := os.ReadFile(i.Path)
	if !bytes.Equal(b, got) {
		t.Fatal("reencoded")
	}
	retry, e := s.Receive(id, "png", h, int64(len(b)), bytes.NewReader(b))
	if e != nil || retry.Path != i.Path {
		t.Fatal(retry, e)
	}
	all, _ := s.List()
	if len(all) != 1 {
		t.Fatal(all)
	}
	if _, e = s.Receive(model.NewID(), "png", h, 5, bytes.NewReader(b[:2])); e == nil {
		t.Fatal("short upload accepted")
	}
}
func TestCleanupBoundary(t *testing.T) {
	s, _ := Open(t.TempDir(), model.DefaultConfig().Limits)
	now := time.Now().UTC()
	for n, age := range []time.Duration{24 * time.Hour, 23 * time.Hour, 48 * time.Hour} {
		i := model.Image{ID: model.NewID(), CreatedAt: now.Add(-age), Extension: "png", Size: 1, Pinned: n == 2, Status: "complete"}
		i.Path = filepath.Join(s.Root, "inbox", model.CaptureName(i.CreatedAt, i.ID, "png"))
		os.WriteFile(i.Path, []byte{1}, 0600)
		AtomicJSON(s.record(i.ID), i)
	}
	other := filepath.Join(s.Root, "inbox", "personal.png")
	os.WriteFile(other, []byte{1}, 0600)
	dry, e := s.Cleanup(now, true)
	if e != nil || len(dry) != 1 {
		t.Fatal(dry, e)
	}
	all, _ := s.List()
	if len(all) != 3 {
		t.Fatal("dry run removed files")
	}
	removed, e := s.Cleanup(now, false)
	if e != nil || len(removed) != 1 {
		t.Fatal(removed, e)
	}
	all, _ = s.List()
	if len(all) != 2 {
		t.Fatal(all)
	}
	if _, e = os.Stat(other); e != nil {
		t.Fatal("unmanaged file removed")
	}
}
