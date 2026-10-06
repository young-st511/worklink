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

	"github.com/young-st511/worklink/internal/address"
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

type familyConnection struct {
	target      string
	cancelError bool
	forwards    []model.Port
	removes     []bool
}

func (f *familyConnection) Close() {}
func (f *familyConnection) Forward(_ context.Context, p model.Port, remove bool) error {
	f.forwards = append(f.forwards, p)
	f.removes = append(f.removes, remove)
	if remove && f.cancelError {
		return fmt.Errorf("cancel failed")
	}
	return nil
}
func (f *familyConnection) Call(_ context.Context, q remote.Request, _ io.Reader) (remote.Response, error) {
	r := remote.Response{Checks: map[string]bool{}, Targets: map[string]string{}}
	for id := range q.Endpoints {
		r.Checks[id] = true
		r.Targets[id] = f.target
	}
	return r, nil
}
func TestForwardFollowsResolvedFamily(t *testing.T) {
	conn := &familyConnection{target: "::1"}
	e, err := New(t.TempDir(), nil, func(Event) {})
	if err != nil {
		t.Fatal(err)
	}
	c := model.DefaultConfig()
	c.Hosts = []model.Host{{Name: "test", Helper: "/tmp/helper"}}
	c.Ports = []model.Port{{ID: model.NewID(), Host: "test", Enabled: true, LocalPort: 4000, Endpoint: address.Endpoint{Scheme: "http", RemoteHost: "127.0.0.1", RemotePort: 4000, Path: "/"}}}
	e.state.Config = c
	e.state.On = true
	e.state.Generation = 1
	e.peers["test"] = &peer{connection: conn, forwarded: map[string]bool{}}
	e.cycle(context.Background(), 1)
	if len(conn.forwards) != 1 || conn.forwards[0].Endpoint.RemoteHost != "::1" || e.Snapshot().Ports[0].RemoteHost != "::1" {
		t.Fatal("forward/check target differs", conn.forwards, e.Snapshot())
	}
	conn.target = "127.0.0.1"
	e.cycle(context.Background(), 1)
	if len(conn.forwards) != 3 || !conn.removes[1] || conn.forwards[1].Endpoint.RemoteHost != "::1" || conn.removes[2] || conn.forwards[2].Endpoint.RemoteHost != "127.0.0.1" {
		t.Fatal("family change did not retarget owned forward", conn)
	}
}

func TestRejectNonLoopbackResolvedTarget(t *testing.T) {
	conn := &familyConnection{target: "192.0.2.1"}
	e, _ := New(t.TempDir(), nil, func(Event) {})
	c := model.DefaultConfig()
	c.Hosts = []model.Host{{Name: "test", Helper: "/tmp/helper"}}
	c.Ports = []model.Port{{ID: model.NewID(), Host: "test", Enabled: true, LocalPort: 4000, Endpoint: address.Parse("4000").Endpoint}}
	e.state.Config = c
	e.state.On = true
	e.state.Generation = 1
	e.peers["test"] = &peer{connection: conn, forwarded: map[string]bool{}}
	e.cycle(context.Background(), 1)
	if len(conn.forwards) != 0 {
		t.Fatal("forwarded an unregistered target", conn.forwards)
	}
	e.state.On = false
	e.portStatus(1, c.Ports[0].ID, "ready", "", true, "::1")
	if len(e.Snapshot().Ports) != 0 {
		t.Fatal("OFF accepted stale port status")
	}
}

func TestRetargetFailureInvalidatesReadyAndPublishes(t *testing.T) {
	conn := &familyConnection{target: "::1"}
	published := false
	e, _ := New(t.TempDir(), nil, func(event Event) {
		if event.State != nil && len(event.State.Ports) > 0 && !event.State.Ports[0].Reachable {
			published = true
		}
	})
	c := model.DefaultConfig()
	c.Hosts = []model.Host{{Name: "test", Helper: "/tmp/helper"}}
	c.Ports = []model.Port{{ID: model.NewID(), Host: "test", Enabled: true, LocalPort: 4000, Endpoint: address.Parse("4000").Endpoint}}
	e.state.Config = c
	e.state.On = true
	e.state.Generation = 1
	e.peers["test"] = &peer{connection: conn, forwarded: map[string]bool{}}
	e.cycle(context.Background(), 1)
	conn.target = "127.0.0.1"
	conn.cancelError = true
	e.cycle(context.Background(), 1)
	if state := e.Snapshot(); state.Ports[0].Reachable || state.Ports[0].Status == "ready" || !published {
		t.Fatal("failed tunnel remained ready or not published", state, published)
	}
}
