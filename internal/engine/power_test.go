package engine

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"os"
	"path/filepath"
	"strconv"
	"testing"
	"time"

	"github.com/young-st511/worklink/internal/address"
	"github.com/young-st511/worklink/internal/model"
	"github.com/young-st511/worklink/internal/remote"
	"github.com/young-st511/worklink/internal/storage"
	"github.com/young-st511/worklink/internal/transport"
)

func idleEngine(t *testing.T) *Engine {
	t.Helper()
	e, err := New(t.TempDir(), func(context.Context, model.Host) (transport.Connection, error) { return nil, io.EOF }, func(Event) {})
	if err != nil {
		t.Fatal(err)
	}
	e.state.On = true
	e.state.Generation = 1
	e.state.Config.Hosts = []model.Host{{Name: "offline", Helper: "/tmp/helper"}}
	e.state.Config.ImageHost = "offline"
	return e
}
func enqueueFixture(t *testing.T, e *Engine) Job {
	t.Helper()
	path := filepath.Join(t.TempDir(), "image.png")
	if err := os.WriteFile(path, []byte{1, 2, 3}, 0600); err != nil {
		t.Fatal(err)
	}
	j, err := e.Enqueue(path, "png", 1)
	if err != nil {
		t.Fatal(err)
	}
	return j
}
func TestOfflineQueueDoesNotRewrite(t *testing.T) {
	e := idleEngine(t)
	j := enqueueFixture(t, e)
	path := filepath.Join(e.store.Root, "jobs.json")
	before, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	for i := 0; i < 60; i++ {
		e.sendNext(context.Background(), 1)
	}
	after, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	if !os.SameFile(before, after) || !before.ModTime().Equal(after.ModTime()) {
		t.Fatal("offline queue repeatedly rewrote jobs.json")
	}
	if got := e.Snapshot().Jobs[0]; got.Status != "queued" || got.ID != j.ID {
		t.Fatal(got)
	}
	if _, err = os.Stat(e.queuePath(j)); err != nil {
		t.Fatal("offline queue removed original", err)
	}
}
func TestExpiryPersistsOnce(t *testing.T) {
	e := idleEngine(t)
	j := enqueueFixture(t, e)
	e.state.Jobs[0].CreatedAt = time.Now().Add(-31 * time.Minute)
	if err := e.saveJobsLocked(); err != nil {
		t.Fatal(err)
	}
	e.sendNext(context.Background(), 1)
	var jobs []Job
	path := filepath.Join(e.store.Root, "jobs.json")
	b, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if err = json.Unmarshal(b, &jobs); err != nil || jobs[0].Status != "expired" {
		t.Fatal("expiry not persisted", jobs, err)
	}
	before, _ := os.Stat(path)
	e.sendNext(context.Background(), 1)
	after, _ := os.Stat(path)
	if !os.SameFile(before, after) {
		t.Fatal("expired job repeatedly persisted")
	}
	if _, err = os.Stat(e.queuePath(j)); err != nil {
		t.Fatal("expiry removed pending original", err)
	}
}
func TestOfflineHostDoesNotBlockReadyUpload(t *testing.T) {
	e := idleEngine(t)
	offline := enqueueFixture(t, e)
	e.state.Config.Hosts = append(e.state.Config.Hosts, model.Host{Name: "ready", Helper: "/tmp/helper"})
	e.state.Config.ImageHost = "ready"
	ready := enqueueFixture(t, e)
	store, err := storage.Open(t.TempDir(), model.DefaultConfig().Limits)
	if err != nil {
		t.Fatal(err)
	}
	e.peers["ready"] = &peer{connection: &localConnection{store}}
	e.sendNext(context.Background(), 1)
	for _, job := range e.Snapshot().Jobs {
		if job.ID == offline.ID && job.Status != "queued" {
			t.Fatal(job)
		}
		if job.ID == ready.ID && job.Status != "complete" {
			t.Fatal("ready host starved behind offline job", job)
		}
	}
	if _, err = store.Verify(ready.ID); err != nil {
		t.Fatal(err)
	}
}
func TestStateEventsDeduplicateOnlyState(t *testing.T) {
	var output bytes.Buffer
	emit := newEventEmitter(&output)
	state := State{Generation: 1, Jobs: []Job{{Image: model.Image{ID: "fixture", Status: "queued"}}}}
	for i := 0; i < 60; i++ {
		emit(Event{Kind: "state", State: &state})
	}
	for i := 0; i < 2; i++ {
		emit(Event{Kind: "reply", ID: "same"})
		emit(Event{Kind: "upload_complete", Job: &state.Jobs[0]})
	}
	state.Jobs[0].Status = "complete"
	emit(Event{Kind: "state", State: &state})
	state.On = true
	state.Generation++
	emit(Event{Kind: "state", State: &state})
	decoder := json.NewDecoder(&output)
	counts := map[string]int{}
	for {
		var event Event
		err := decoder.Decode(&event)
		if err == io.EOF {
			break
		}
		if err != nil {
			t.Fatal(err)
		}
		counts[event.Kind]++
	}
	if counts["state"] != 3 || counts["reply"] != 2 || counts["upload_complete"] != 2 {
		t.Fatal(counts)
	}
}

type conflictConnection struct {
	fail   bool
	calls  map[string]int
	target string
	checks int
}

func (c *conflictConnection) Close() {}
func (c *conflictConnection) Forward(_ context.Context, p model.Port, remove bool) error {
	if remove {
		return nil
	}
	c.calls[p.ID]++
	if c.fail && p.LocalPort == 4000 {
		return errors.New("port conflict")
	}
	return nil
}
func (c *conflictConnection) Call(_ context.Context, q remote.Request, _ io.Reader) (remote.Response, error) {
	c.checks++
	r := remote.Response{Checks: map[string]bool{}, Targets: map[string]string{}}
	for id := range q.Endpoints {
		r.Checks[id] = true
		r.Targets[id] = c.target
	}
	return r, nil
}
func TestConflictBackoffAndRecovery(t *testing.T) {
	e := idleEngine(t)
	now := time.Now()
	e.now = func() time.Time { return now }
	c := &conflictConnection{fail: true, calls: map[string]int{}, target: "127.0.0.1"}
	for _, port := range []int{4000, 5000} {
		e.state.Config.Ports = append(e.state.Config.Ports, model.Port{ID: model.NewID(), Host: "offline", Enabled: true, LocalPort: port, Endpoint: address.Parse(strconv.Itoa(port)).Endpoint})
	}
	bad, good := e.state.Config.Ports[0].ID, e.state.Config.Ports[1].ID
	e.peers["offline"] = &peer{connection: c, forwarded: map[string]bool{}}
	e.cycle(context.Background(), 1)
	for _, delay := range []time.Duration{10, 20, 40, 60, 60} {
		attempts := c.calls[bad]
		now = now.Add((delay - 1) * time.Second)
		e.cycle(context.Background(), 1)
		if c.calls[bad] != attempts || c.calls[good] != 1 {
			t.Fatal("retry ran early or normal port retried", c.calls)
		}
		now = now.Add(time.Second)
		e.cycle(context.Background(), 1)
		if c.calls[bad] != attempts+1 {
			t.Fatal("retry did not run at deadline", c.calls)
		}
	}
	c.fail = false
	now = now.Add(60 * time.Second)
	e.cycle(context.Background(), 1)
	for _, p := range e.Snapshot().Ports {
		if p.Status != "ready" {
			t.Fatal("conflict did not recover", p)
		}
	}
	attempts := c.calls[bad]
	now = now.Add(time.Minute)
	e.cycle(context.Background(), 1)
	if c.calls[bad] != attempts {
		t.Fatal("successful tunnel retried")
	}
	e.SetOn(false)
	now = now.Add(time.Hour)
	e.cycle(context.Background(), 1)
	if c.calls[bad] != attempts {
		t.Fatal("OFF retried tunnel")
	}
}
func TestConflictTargetChangeRetriesImmediately(t *testing.T) {
	e := idleEngine(t)
	c := &conflictConnection{fail: true, calls: map[string]int{}, target: "127.0.0.1"}
	p := model.Port{ID: model.NewID(), Host: "offline", Enabled: true, LocalPort: 4000, Endpoint: address.Parse("4000").Endpoint}
	e.state.Config.Ports = []model.Port{p}
	e.peers["offline"] = &peer{connection: c, forwarded: map[string]bool{}}
	e.cycle(context.Background(), 1)
	c.target = "::1"
	c.fail = false
	e.cycle(context.Background(), 1)
	if c.calls[p.ID] != 2 || e.Snapshot().Ports[0].Status != "ready" {
		t.Fatal("target change stuck in old backoff", c.calls, e.Snapshot())
	}
}

func TestDisconnectedExpiryOFFAndGeneration(t *testing.T) {
	e := idleEngine(t)
	j := enqueueFixture(t, e)
	e.state.Jobs[0].CreatedAt = time.Now().Add(-time.Hour)
	if err := e.saveJobsLocked(); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(e.store.Root, "jobs.json")
	before, _ := os.Stat(path)
	e.sendNext(context.Background(), 2)
	after, _ := os.Stat(path)
	if e.Snapshot().Jobs[0].Status != "queued" || !os.SameFile(before, after) {
		t.Fatal("old generation processed queue")
	}
	e.state.On = false
	e.sendNext(context.Background(), 1)
	after, _ = os.Stat(path)
	if !os.SameFile(before, after) {
		t.Fatal("OFF wrote queue")
	}
	if _, err := os.Stat(e.queuePath(j)); err != nil {
		t.Fatal(err)
	}
}

type intermittentWriter struct {
	bytes.Buffer
	fail bool
}

func (w *intermittentWriter) Write(p []byte) (int, error) {
	if w.fail {
		w.fail = false
		return 0, io.ErrClosedPipe
	}
	return w.Buffer.Write(p)
}
func TestStateCacheDoesNotDropFailedWrite(t *testing.T) {
	out := &intermittentWriter{fail: true}
	emit := newEventEmitter(out)
	state := State{Generation: 1}
	emit(Event{Kind: "state", State: &state})
	emit(Event{Kind: "state", State: &state})
	var event Event
	if err := json.Unmarshal(bytes.TrimSpace(out.Bytes()), &event); err != nil || event.State == nil {
		t.Fatal("failed state write cached", err)
	}
}
func TestExpirySaveFailureCanRecover(t *testing.T) {
	e := idleEngine(t)
	enqueueFixture(t, e)
	e.state.Jobs[0].CreatedAt = time.Now().Add(-time.Hour)
	path := filepath.Join(e.store.Root, "jobs.json")
	if err := os.Remove(path); err != nil {
		t.Fatal(err)
	}
	if err := os.Mkdir(path, 0700); err != nil {
		t.Fatal(err)
	}
	e.sendNext(context.Background(), 1)
	if e.Snapshot().Jobs[0].Status != "queued" || e.Snapshot().Error == "" {
		t.Fatal("failed expiry silently accepted", e.Snapshot())
	}
	if err := os.Remove(path); err != nil {
		t.Fatal(err)
	}
	e.sendNext(context.Background(), 1)
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var jobs []Job
	if err = json.Unmarshal(data, &jobs); err != nil || jobs[0].Status != "expired" {
		t.Fatal("failed expiry never retried", err)
	}
}
