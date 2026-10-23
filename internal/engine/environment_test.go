package engine

import (
	"bytes"
	"context"
	"encoding/json"
	"github.com/young-st511/worklink/internal/model"
	"github.com/young-st511/worklink/internal/remote"
	"github.com/young-st511/worklink/internal/storage"
	"github.com/young-st511/worklink/internal/transport"
	"io"
	"os"
	"strings"
	"sync"
	"testing"
	"time"
)

type policyConnection struct {
	mu     sync.Mutex
	calls  int
	closed bool
}

func (p *policyConnection) Call(_ context.Context, q remote.Request, _ io.Reader) (remote.Response, error) {
	p.mu.Lock()
	defer p.mu.Unlock()
	if q.Op == "check" {
		p.calls++
	}
	return remote.Response{Checks: map[string]bool{}}, nil
}
func (p *policyConnection) Forward(context.Context, model.Port, bool) error { return nil }
func (p *policyConnection) Close()                                          { p.mu.Lock(); p.closed = true; p.mu.Unlock() }
func TestPolicyIntervalsAndEmptyKeepalive(t *testing.T) {
	for _, mode := range []string{"normal", "low", "empty"} {
		t.Run(mode, func(t *testing.T) {
			e := idleEngine(t)
			now := time.Now()
			e.now = func() time.Time { return now }
			conn := &policyConnection{}
			e.connect = func(context.Context, model.Host) (transport.Connection, error) { return conn, nil }
			c := fullConfig()
			if mode == "empty" {
				c.Ports = nil
			}
			e.state.Config = c
			e.SetEnvironment(true, mode == "low")
			e.cycle(context.Background(), 1)
			if conn.calls != 1 {
				t.Fatal(conn.calls)
			}
			interval := 5 * time.Second
			if mode == "low" {
				interval = 30 * time.Second
			}
			if mode == "empty" {
				interval = time.Minute
			}
			now = now.Add(interval - time.Millisecond)
			e.cycle(context.Background(), 1)
			if conn.calls != 1 {
				t.Fatal("early check", conn.calls)
			}
			now = now.Add(time.Millisecond)
			e.cycle(context.Background(), 1)
			if conn.calls != 2 {
				t.Fatal("missed due check", conn.calls)
			}
		})
	}
}
func TestOfflineDoesNotConnectOrResetRetry(t *testing.T) {
	e := idleEngine(t)
	now := time.Now()
	e.now = func() time.Time { return now }
	attempts := 0
	e.connect = func(context.Context, model.Host) (transport.Connection, error) { attempts++; return nil, io.EOF }
	e.SetEnvironment(false, false)
	e.cycle(context.Background(), 1)
	if attempts != 0 {
		t.Fatal("offline connect")
	}
	e.SetEnvironment(true, false)
	e.cycle(context.Background(), 1)
	if attempts != 1 {
		t.Fatal(attempts)
	}
	e.SetEnvironment(false, false)
	e.SetEnvironment(true, false)
	e.cycle(context.Background(), 1)
	if attempts != 1 {
		t.Fatal("flap reset retry")
	}
}

func TestTransportContextSurvivesCycleUntilOffline(t *testing.T) {
	e := idleEngine(t)
	var connected context.Context
	e.connect = func(ctx context.Context, _ model.Host) (transport.Connection, error) {
		connected = ctx
		return &policyConnection{}, nil
	}
	e.cycle(context.Background(), 1)
	if connected == nil || connected.Err() != nil {
		t.Fatal("cycle killed transport")
	}
	gen := e.Snapshot().Generation
	e.SetEnvironment(true, true)
	if connected.Err() != nil || e.Snapshot().Generation != gen {
		t.Fatal("power change killed session")
	}
	e.SetEnvironment(false, true)
	select {
	case <-connected.Done():
	case <-time.After(time.Second):
		t.Fatal("offline kept transport")
	}
	if e.nextDelay(1) != 0 {
		t.Fatal("offline timer retained")
	}
}
func TestRefreshCoalescesAndRecoveryFloor(t *testing.T) {
	e := idleEngine(t)
	now := time.Now()
	e.now = func() time.Time { return now }
	calls := 0
	e.connect = func(context.Context, model.Host) (transport.Connection, error) {
		calls++
		return &policyConnection{}, nil
	}
	e.cycle(context.Background(), 1)
	e.SetEnvironment(false, false)
	e.SetEnvironment(true, false)
	e.cycle(context.Background(), 1)
	if calls != 1 || e.nextDelay(1) != 30*time.Second {
		t.Fatal("rapid recovery loop", calls, e.nextDelay(1))
	}
	for i := 0; i < 100; i++ {
		if err := e.RequestPortRefresh(); err != nil {
			t.Fatal(err)
		}
		e.cycle(context.Background(), 1)
	}
	if calls != 1 {
		t.Fatal("manual request bypassed recovery floor")
	}
	now = now.Add(30 * time.Second)
	e.cycle(context.Background(), 1)
	if calls != 2 {
		t.Fatal(calls)
	}
	p := e.peers["offline"]
	conn := p.conn().(*policyConnection)
	before := conn.calls
	for i := 0; i < 100; i++ {
		e.RequestPortRefresh()
		e.cycle(context.Background(), 1)
	}
	if conn.calls > before+1 {
		t.Fatal("manual refresh storm", conn.calls)
	}
	e.SetOn(false)
	if err := e.RequestPortRefresh(); err == nil {
		t.Fatal("OFF refresh")
	}
}
func TestBlockedQueueStillExpiresWithoutHeartbeat(t *testing.T) {
	e := idleEngine(t)
	now := time.Now()
	e.now = func() time.Time { return now }
	enqueueFixture(t, e)
	e.state.Jobs[0].CreatedAt = now.Add(-29 * time.Minute)
	e.peers["offline"] = &peer{blocked: true}
	delay := e.nextDelay(1)
	if delay < time.Minute || delay > time.Minute+time.Second {
		t.Fatal("expiry deadline missing", delay)
	}
	now = now.Add(time.Minute + time.Second)
	e.cycle(context.Background(), 1)
	if e.Snapshot().Jobs[0].Status != "expired" || e.nextDelay(1) != 0 {
		t.Fatal(e.Snapshot(), e.nextDelay(1))
	}
}
func TestServeUIStartsWaitingForEnvironment(t *testing.T) {
	var output bytes.Buffer
	if err := ServeUI(t.TempDir(), strings.NewReader(""), &output); err != nil {
		t.Fatal(err)
	}
	var event Event
	if err := json.Unmarshal(bytes.TrimSpace(output.Bytes()), &event); err != nil {
		t.Fatal(err)
	}
	if event.State == nil || !event.State.NetworkUnavailable || event.State.On {
		t.Fatal(event)
	}
}
func TestNetworkFlapPreservesBlockedReason(t *testing.T) {
	e := idleEngine(t)
	e.peers["offline"] = &peer{blocked: true}
	e.state.Hosts = []HostState{{Host: "offline", Status: "blocked", Error: "Permission denied"}}
	e.SetEnvironment(false, false)
	e.SetEnvironment(true, false)
	e.cycle(context.Background(), 1)
	h := e.Snapshot().Hosts[0]
	if h.Status != "blocked" || h.Error != "Permission denied" || e.nextDelay(1) != 0 {
		t.Fatal(h)
	}
}
func TestOFFCancelsLongLivedTransport(t *testing.T) {
	e := idleEngine(t)
	ctx, cancel := context.WithCancel(context.Background())
	e.cancel = cancel
	var transportCtx context.Context
	e.connect = func(c context.Context, _ model.Host) (transport.Connection, error) {
		transportCtx = c
		return &policyConnection{}, nil
	}
	e.cycle(ctx, 1)
	if transportCtx.Err() != nil {
		t.Fatal("transport ended with cycle")
	}
	e.SetOn(false)
	select {
	case <-transportCtx.Done():
	case <-time.After(time.Second):
		t.Fatal("OFF kept transport")
	}
}

type interruptedImageConnection struct {
	localConnection
	started chan struct{}
}

func (c *interruptedImageConnection) Call(ctx context.Context, q remote.Request, r io.Reader) (remote.Response, error) {
	if q.Op == "exists" {
		close(c.started)
		<-ctx.Done()
		return remote.Response{}, ctx.Err()
	}
	return c.localConnection.Call(ctx, q, r)
}
func TestNetworkLossKeepsImageAndResumesSameID(t *testing.T) {
	e := idleEngine(t)
	now := time.Now()
	e.now = func() time.Time { return now }
	store, err := storage.Open(t.TempDir(), model.DefaultConfig().Limits)
	if err != nil {
		t.Fatal(err)
	}
	started := make(chan struct{})
	attempt := 0
	e.connect = func(context.Context, model.Host) (transport.Connection, error) {
		attempt++
		if attempt == 1 {
			return &interruptedImageConnection{localConnection{store}, started}, nil
		}
		return &localConnection{store}, nil
	}
	job := enqueueFixture(t, e)
	done := make(chan struct{})
	go func() { e.cycle(context.Background(), 1); close(done) }()
	select {
	case <-started:
	case <-time.After(time.Second):
		t.Fatal("upload not reached")
	}
	e.SetEnvironment(false, false)
	select {
	case <-done:
	case <-time.After(time.Second):
		t.Fatal("network loss did not cancel RPC")
	}
	if got := e.Snapshot().Jobs[0]; got.ID != job.ID || got.Status != "queued" {
		t.Fatal(got)
	}
	if _, err := os.Stat(e.queuePath(job)); err != nil {
		t.Fatal("pending original removed", err)
	}
	e.SetEnvironment(true, false)
	now = now.Add(31 * time.Second)
	e.cycle(context.Background(), 1)
	if got := e.Snapshot().Jobs[0]; got.ID != job.ID || got.Status != "complete" {
		t.Fatal(got)
	}
	if _, err := store.Verify(job.ID); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(e.queuePath(job)); !os.IsNotExist(err) {
		t.Fatal("ACK did not reclaim queue", err)
	}
}

func TestNetworkLossBeforeSendLeavesJobQueued(t *testing.T) {
	e := idleEngine(t)
	job := enqueueFixture(t, e)
	e.peers[job.Host] = &peer{connection: &policyConnection{}}
	e.SetEnvironment(false, false)
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	e.sendNext(ctx, 1)
	if got := e.Snapshot().Jobs[0]; got.Status != "queued" {
		t.Fatal(got)
	}
}
