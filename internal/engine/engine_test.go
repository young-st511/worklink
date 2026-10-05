package engine

import (
	"context"
	"github.com/young-st511/worklink/internal/model"
	"github.com/young-st511/worklink/internal/remote"
	"github.com/young-st511/worklink/internal/storage"
	"github.com/young-st511/worklink/internal/transport"
	"io"
	"os"
	"path/filepath"
	"testing"
	"time"
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
