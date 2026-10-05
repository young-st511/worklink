package engine

import (
	"context"
	"github.com/young-st511/worklink/internal/model"
	"github.com/young-st511/worklink/internal/remote"
	"github.com/young-st511/worklink/internal/transport"
	"io"
	"os"
	"path/filepath"
	"testing"
	"time"
)

type slowConnection struct {
	started chan struct{}
	closed  chan struct{}
}

func (s *slowConnection) Close() {
	select {
	case <-s.closed:
	default:
		close(s.closed)
	}
}
func (s *slowConnection) Forward(context.Context, model.Port, bool) error { return nil }
func (s *slowConnection) Call(ctx context.Context, q remote.Request, r io.Reader) (remote.Response, error) {
	if q.Op == "upload" {
		close(s.started)
		<-ctx.Done()
		return remote.Response{}, ctx.Err()
	}
	return remote.Response{}, nil
}
func TestOFFCancelsUploadAndRetainsOriginal(t *testing.T) {
	root := t.TempDir()
	conn := &slowConnection{make(chan struct{}), make(chan struct{})}
	e, err := New(root, func(context.Context, model.Host) (transport.Connection, error) { return conn, nil }, func(Event) {})
	if err != nil {
		t.Fatal(err)
	}
	c := model.DefaultConfig()
	c.Hosts = []model.Host{{Name: "test", Helper: "/tmp/helper"}}
	c.ImageHost = "test"
	if err = e.SaveConfig(c); err != nil {
		t.Fatal(err)
	}
	source := filepath.Join(t.TempDir(), "test.png")
	os.WriteFile(source, []byte{1, 2}, 0600)
	e.SetOn(true)
	j, err := e.Enqueue(source, "png", 7)
	if err != nil {
		t.Fatal(err)
	}
	select {
	case <-conn.started:
	case <-time.After(2 * time.Second):
		t.Fatal("no upload")
	}
	e.SetOn(false)
	if e.Snapshot().On {
		t.Fatal("still ON")
	}
	if _, err = os.Stat(e.queuePath(j)); err != nil {
		t.Fatal("deleted without ACK")
	}
	restarted, err := New(root, nil, func(Event) {})
	if err != nil {
		t.Fatal(err)
	}
	if restarted.Snapshot().On || restarted.Snapshot().Jobs[0].Status != "paused" {
		t.Fatal("restart auto sending")
	}
}
