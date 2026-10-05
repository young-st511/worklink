package storage

import (
	"bytes"
	"crypto/sha256"
	"fmt"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/young-st511/worklink/internal/model"
)

func TestModifiedRemoteCannotACK(t *testing.T) {
	s, _ := Open(t.TempDir(), model.DefaultConfig().Limits)
	b := []byte("original")
	hash := fmt.Sprintf("%x", sha256.Sum256(b))
	id := model.NewID()
	i, e := s.Receive(id, "png", hash, int64(len(b)), bytes.NewReader(b))
	if e != nil {
		t.Fatal(e)
	}
	os.WriteFile(i.Path, []byte("modified"), 0600)
	if _, e = s.Verify(id); e == nil {
		t.Fatal("verified modified bytes")
	}
	if _, e = s.Receive(id, "png", hash, int64(len(b)), bytes.NewReader(b)); e == nil {
		t.Fatal("acknowledged modified bytes")
	}
}
func TestOrphanRecovery(t *testing.T) {
	s, _ := Open(t.TempDir(), model.DefaultConfig().Limits)
	b := []byte("original")
	hash := fmt.Sprintf("%x", sha256.Sum256(b))
	id := model.NewID()
	i, e := s.Receive(id, "png", hash, int64(len(b)), bytes.NewReader(b))
	if e != nil {
		t.Fatal(e)
	}
	os.Remove(s.record(id))
	recovered, e := s.Receive(id, "png", hash, int64(len(b)), bytes.NewReader(b))
	if e != nil || recovered.Path != i.Path {
		t.Fatal(recovered, e)
	}
}
func TestPendingAndInvalidRecordsPreserved(t *testing.T) {
	s, _ := Open(t.TempDir(), model.DefaultConfig().Limits)
	now := time.Now()
	i := model.Image{ID: model.NewID(), CreatedAt: now.Add(-48 * time.Hour), Extension: "png", Size: 1, Status: "uploading"}
	i.Path = filepath.Join(s.Root, "inbox", model.CaptureName(i.CreatedAt, i.ID, "png"))
	os.WriteFile(i.Path, []byte{1}, 0600)
	AtomicJSON(s.record(i.ID), i)
	bad := filepath.Join(s.Root, "records", model.NewID()+".json")
	os.WriteFile(bad, []byte("bad json"), 0600)
	if paths, e := s.Cleanup(now, false); e != nil || len(paths) != 0 {
		t.Fatal(paths, e)
	}
	if _, e := os.Stat(i.Path); e != nil {
		t.Fatal("pending removed")
	}
	if _, e := os.Stat(bad); e != nil {
		t.Fatal("invalid record removed")
	}
}
func TestConfigRejectsStaleWrite(t *testing.T) {
	s, _ := Open(t.TempDir(), model.DefaultConfig().Limits)
	a, _ := s.LoadConfig()
	b := a
	a.Hosts = append(a.Hosts, model.Host{Name: "one", Helper: "~/.local/bin/worklink"})
	if e := s.SaveConfig(&a); e != nil {
		t.Fatal(e)
	}
	b.Hosts = append(b.Hosts, model.Host{Name: "two", Helper: "~/.local/bin/worklink"})
	if e := s.SaveConfig(&b); e == nil {
		t.Fatal("stale settings silently overwrote new settings")
	}
	c, _ := s.LoadConfig()
	if len(c.Hosts) != 1 || c.Hosts[0].Name != "one" {
		t.Fatal(c)
	}
}
