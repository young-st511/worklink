package engine

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/young-st511/worklink/internal/model"
	"github.com/young-st511/worklink/internal/storage"
	"github.com/young-st511/worklink/internal/transport"
)

func configured(t *testing.T, root string) *Engine {
	t.Helper()
	e, err := New(root, nil, func(Event) {})
	if err != nil {
		t.Fatal(err)
	}
	c := model.DefaultConfig()
	c.Hosts = []model.Host{{Name: "old", Helper: "/tmp/helper"}, {Name: "new", Helper: "/tmp/helper"}}
	c.ImageHost = "old"
	if err = e.SaveConfig(c); err != nil {
		t.Fatal(err)
	}
	return e
}
func TestACKRecordBeforeQueueRemoval(t *testing.T) {
	root := t.TempDir()
	e := configured(t, root)
	e.state.On = true
	e.state.Generation = 1
	src := filepath.Join(t.TempDir(), "x.png")
	os.WriteFile(src, []byte{1, 2}, 0600)
	j, err := e.Enqueue(src, "png", 1)
	if err != nil {
		t.Fatal(err)
	}
	if err = e.finish(j, "complete", "", "/remote/saved.png"); err != nil {
		t.Fatal(err)
	}
	if _, err = os.Stat(e.queuePath(j)); err != nil {
		t.Fatal("test requires crash before deletion")
	}
	recovered, err := New(root, nil, func(Event) {})
	if err != nil {
		t.Fatal(err)
	}
	got := recovered.Snapshot().Jobs[0]
	if got.Status != "complete" || got.RemotePath != "/remote/saved.png" {
		t.Fatal(got)
	}
	if _, err = os.Stat(e.queuePath(j)); !os.IsNotExist(err) {
		t.Fatal("completed queue copy not reclaimed")
	}
}
func TestACKSaveFailureKeepsQueue(t *testing.T) {
	root := t.TempDir()
	e := configured(t, root)
	e.state.On = true
	e.state.Generation = 1
	src := filepath.Join(t.TempDir(), "x.png")
	os.WriteFile(src, []byte{1, 2}, 0600)
	j, err := e.Enqueue(src, "png", 1)
	if err != nil {
		t.Fatal(err)
	}
	os.Remove(filepath.Join(root, "jobs.json"))
	os.Mkdir(filepath.Join(root, "jobs.json"), 0700)
	if err = e.finish(j, "complete", "", "/remote/saved.png"); err == nil {
		t.Fatal("expected persistence failure")
	}
	if _, err = os.Stat(e.queuePath(j)); err != nil {
		t.Fatal("queue lost without durable ACK")
	}
}
func TestOrphanCountsAgainstQuota(t *testing.T) {
	e := configured(t, t.TempDir())
	c := e.state.Config
	c.Limits.QueueCount = 1
	if err := e.SaveConfig(c); err != nil {
		t.Fatal(err)
	}
	os.WriteFile(filepath.Join(e.store.Root, "queue", model.NewID()+".png"), []byte{1}, 0600)
	e.state.On = true
	src := filepath.Join(t.TempDir(), "x.png")
	os.WriteFile(src, []byte{2}, 0600)
	if _, err := e.Enqueue(src, "png", 1); err == nil {
		t.Fatal("orphan bypassed queue quota")
	}
}
func TestRetryUsesOriginalHostAfterSelectionChange(t *testing.T) {
	root := t.TempDir()
	e := configured(t, root)
	remoteStore, _ := storage.Open(t.TempDir(), model.DefaultConfig().Limits)
	connected := make(chan string, 10)
	e.connect = func(ctx context.Context, h model.Host) (transport.Connection, error) {
		connected <- h.Name
		return &localConnection{remoteStore}, nil
	}
	e.state.On = true
	e.state.Generation = 1
	src := filepath.Join(t.TempDir(), "x.png")
	os.WriteFile(src, []byte{1, 2}, 0600)
	j, err := e.Enqueue(src, "png", 1)
	if err != nil {
		t.Fatal(err)
	}
	e.SetOn(false)
	c := e.Snapshot().Config
	c.ImageHost = "new"
	if err = e.SaveConfig(c); err != nil {
		t.Fatal(err)
	}
	e.SetOn(true)
	defer e.SetOn(false)
	if err = e.Retry(j.ID); err != nil {
		t.Fatal(err)
	}
	deadline := time.After(3 * time.Second)
	for {
		select {
		case h := <-connected:
			if h == "old" {
				return
			}
		case <-deadline:
			t.Fatal("did not connect to original target")
		}
	}
}
