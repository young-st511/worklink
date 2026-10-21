package engine

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/young-st511/worklink/internal/address"
	"github.com/young-st511/worklink/internal/model"
)

func cleanupFixture(t *testing.T) (*Engine, *time.Time) {
	t.Helper()
	e, err := New(t.TempDir(), nil, func(Event) {})
	if err != nil {
		t.Fatal(err)
	}
	c := fullConfig()
	c.PortCleanupEnabled = true
	c.PortCleanupDays = 7
	if err = e.SaveConfig(c); err != nil {
		t.Fatal(err)
	}
	e.state.On = true
	e.state.Generation = 1
	e.state.Hosts = []HostState{{Host: "office", Status: "connected"}}
	now := time.Now().UTC()
	e.now = func() time.Time { return now }
	return e, &now
}
func TestDailyCleanupAgePinUndo(t *testing.T) {
	e, now := cleanupFixture(t)
	c := e.Snapshot().Config
	c.Ports[1].Pinned = true
	e.state.Config = c
	e.recordPortChecks("office", map[string]bool{c.Ports[0].ID: false, c.Ports[1].ID: false, c.Ports[2].ID: true}, 1)
	*now = now.Add(7 * 24 * time.Hour)
	e.recordPortChecks("office", map[string]bool{c.Ports[0].ID: false, c.Ports[1].ID: false, c.Ports[2].ID: true}, 1)
	if err := e.cleanupPorts(context.Background(), 1); err != nil {
		t.Fatal(err)
	}
	snap := e.Snapshot()
	if len(snap.Config.Ports) != 15 || snap.Config.PortCleanupHistory == nil || len(snap.Config.PortCleanupHistory.Removed) != 1 {
		t.Fatal(snap.Config)
	}
	if err := e.UndoPortCleanup(); err != nil {
		t.Fatal(err)
	}
	snap = e.Snapshot()
	if len(snap.Config.Ports) != 16 {
		t.Fatal(snap.Config)
	}
	for _, p := range snap.Config.Ports {
		if p.ID == c.Ports[0].ID && !p.Pinned {
			t.Fatal("restored port not protected")
		}
	}
}
func TestDailyCleanupDefaultAndFreshness(t *testing.T) {
	c := model.DefaultConfig()
	if c.PortCleanupEnabled || c.PortCleanupDays != 7 {
		t.Fatal(c)
	}
	for _, mode := range []string{"off", "offline", "stale", "old-generation", "disabled"} {
		t.Run(mode, func(t *testing.T) {
			e, now := cleanupFixture(t)
			id := e.state.Config.Ports[0].ID
			e.recordPortChecks("office", map[string]bool{id: false}, 1)
			*now = now.Add(8 * 24 * time.Hour)
			e.recordPortChecks("office", map[string]bool{id: false}, 1)
			gen := uint64(1)
			switch mode {
			case "off":
				e.state.On = false
			case "offline":
				e.state.Hosts = nil
			case "stale":
				*now = now.Add(16 * time.Second)
			case "old-generation":
				gen = 0
			case "disabled":
				e.state.Config.PortCleanupEnabled = false
			}
			if err := e.cleanupPorts(context.Background(), gen); err != nil {
				t.Fatal(err)
			}
			if len(e.Snapshot().Config.Ports) != 16 {
				t.Fatal("protected port removed")
			}
		})
	}
}
func TestCleanupDailyGateAndRecentActivity(t *testing.T) {
	e, now := cleanupFixture(t)
	ports := e.state.Config.Ports
	old := ports[0].ID
	active := ports[1].ID
	e.recordPortChecks("office", map[string]bool{old: false, active: true}, 1)
	*now = now.Add(8 * 24 * time.Hour)
	e.recordPortChecks("office", map[string]bool{old: false, active: false}, 1)
	if err := e.cleanupPorts(context.Background(), 1); err != nil {
		t.Fatal(err)
	}
	s := e.Snapshot()
	if len(s.Config.Ports) != 15 || s.Config.PortCleanupHistory.Removed[0].ID != old {
		t.Fatal(s.Config)
	}
	rev := s.Config.Revision
	if err := e.cleanupPorts(context.Background(), 1); err != nil {
		t.Fatal(err)
	}
	if e.Snapshot().Config.Revision != rev {
		t.Fatal("daily heartbeat wrote config")
	}
	*now = now.Add(24 * time.Hour)
	e.recordPortChecks("office", map[string]bool{active: false}, 1)
	if err := e.cleanupPorts(context.Background(), 1); err != nil {
		t.Fatal(err)
	}
	if len(e.Snapshot().Config.Ports) != 15 {
		t.Fatal("recently active port removed")
	}
	reloaded, err := New(e.store.Root, nil, func(Event) {})
	if err != nil {
		t.Fatal(err)
	}
	if len(reloaded.Snapshot().Config.PortCleanupHistory.Removed) != 1 {
		t.Fatal("undo lost on empty run/restart")
	}
}
func TestCleanupUndoConflictAndStorageFailure(t *testing.T) {
	e, now := cleanupFixture(t)
	id := e.state.Config.Ports[0].ID
	e.recordPortChecks("office", map[string]bool{id: false}, 1)
	*now = now.Add(8 * 24 * time.Hour)
	e.recordPortChecks("office", map[string]bool{id: false}, 1)
	path := filepath.Join(e.store.Root, "config.json")
	original, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	os.Remove(path)
	os.Mkdir(path, 0700)
	if err := e.cleanupPorts(context.Background(), 1); err == nil {
		t.Fatal("save error ignored")
	}
	if len(e.Snapshot().Config.Ports) != 16 || e.Snapshot().Config.PortCleanupHistory != nil {
		t.Fatal("failed cleanup changed state")
	}
	os.Remove(path)
	os.WriteFile(path, original, 0600)
	if err := e.cleanupPorts(context.Background(), 1); err != nil {
		t.Fatal(err)
	}
	c := e.Snapshot().Config
	replacement := c.PortCleanupHistory.Removed[0]
	replacement.ID = model.NewID()
	c.Ports = append(c.Ports, replacement)
	// Store the conflicting registration without starting the background loop.
	if err := e.store.SaveConfig(&c); err != nil {
		t.Fatal(err)
	}
	e.state.Config = c
	before := c.Revision
	if err := e.UndoPortCleanup(); err == nil {
		t.Fatal("conflicting undo accepted")
	}
	if e.Snapshot().Config.Revision != before || len(e.Snapshot().Config.PortCleanupHistory.Removed) != 1 {
		t.Fatal("failed undo lost history")
	}
}
func TestPinnedPortProtectedAtCapacity(t *testing.T) {
	e, now := cleanupFixture(t)
	c := e.Snapshot().Config
	id := c.Ports[0].ID
	if err := e.SetPortPinned(id, true); err != nil {
		t.Fatal(err)
	}
	c = e.Snapshot().Config
	e.recordPortChecks("office", map[string]bool{id: false}, 1)
	*now = now.Add(time.Second)
	c.Ports = append(c.Ports, model.Port{ID: model.NewID(), Host: "office", LocalPort: 6000, Enabled: true, Endpoint: address.Parse("6000").Endpoint})
	if _, _, err := e.trimInactive(c); err == nil {
		t.Fatal("pinned port evicted")
	}
}

type cleanupConnection struct {
	localConnection
	cancel func() error
	closed bool
}

func (c *cleanupConnection) Forward(_ context.Context, _ model.Port, remove bool) error {
	if remove && c.cancel != nil {
		return c.cancel()
	}
	return nil
}
func (c *cleanupConnection) Close() { c.closed = true }
func TestCleanupRechecksAfterForwardAndKeepsSession(t *testing.T) {
	for _, mode := range []string{"success", "stale", "cancel-failed"} {
		t.Run(mode, func(t *testing.T) {
			e, now := cleanupFixture(t)
			id := e.state.Config.Ports[0].ID
			e.recordPortChecks("office", map[string]bool{id: false}, 1)
			*now = now.Add(8 * 24 * time.Hour)
			e.recordPortChecks("office", map[string]bool{id: false}, 1)
			conn := &cleanupConnection{cancel: func() error {
				if mode == "stale" {
					*now = now.Add(16 * time.Second)
				}
				if mode == "cancel-failed" {
					return errors.New("fixture cancel failure")
				}
				return nil
			}}
			e.peers["office"] = &peer{connection: conn, forwarded: map[string]bool{id: true}, targets: map[string]string{}, forwardRetries: map[string]forwardRetry{}}
			fileCancelled := false
			e.fileCancel = func() { fileCancelled = true }
			err := e.cleanupPorts(context.Background(), 1)
			if mode == "cancel-failed" && err == nil {
				t.Fatal("cancel failure ignored")
			}
			expected := 16
			if mode == "success" {
				expected = 15
			}
			snap := e.Snapshot()
			if len(snap.Config.Ports) != expected || snap.Generation != 1 || !snap.On || conn.closed || fileCancelled {
				t.Fatal(snap.Config, "session changed")
			}
			if mode == "stale" && snap.Config.PortCleanupHistory != nil {
				t.Fatal("stale checks recorded run")
			}
		})
	}
}
func TestActivityWriteFailurePreservesRecentUse(t *testing.T) {
	e, now := cleanupFixture(t)
	id := e.state.Config.Ports[0].ID
	e.recordPortChecks("office", map[string]bool{id: false}, 1)
	*now = now.Add(8 * 24 * time.Hour)
	path := filepath.Join(e.store.Root, "port-activity.json")
	os.Remove(path)
	os.Mkdir(path, 0700)
	e.recordPortChecks("office", map[string]bool{id: true}, 1)
	if err := e.cleanupPorts(context.Background(), 1); err != nil {
		t.Fatal(err)
	}
	if len(e.Snapshot().Config.Ports) != 16 {
		t.Fatal("dirty activity removed")
	}
	os.Remove(path)
	*now = now.Add(5 * time.Second)
	e.recordPortChecks("office", map[string]bool{id: false}, 1)
	if e.activityDirty {
		t.Fatal("activity did not recover")
	}
	if err := e.cleanupPorts(context.Background(), 1); err != nil {
		t.Fatal(err)
	}
	if len(e.Snapshot().Config.Ports) != 16 {
		t.Fatal("recent use lost on failed write")
	}
}
func TestPolicyDoesNotInterruptAndRejectsInvalidDays(t *testing.T) {
	e, _ := cleanupFixture(t)
	cancelled := false
	e.fileCancel = func() { cancelled = true }
	for _, days := range []int{3, 7, 14, 30} {
		if err := e.SetPortCleanup(true, days); err != nil {
			t.Fatal(err)
		}
	}
	if err := e.SetPortCleanup(true, 2); err == nil {
		t.Fatal("invalid cleanup days accepted")
	}
	s := e.Snapshot()
	if s.Config.PortCleanupDays != 30 || !s.On || s.Generation != 1 || cancelled {
		t.Fatal(s)
	}
}
