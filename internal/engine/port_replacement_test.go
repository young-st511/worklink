package engine

import (
	"os"
	"path/filepath"
	"strconv"
	"testing"
	"time"

	"github.com/young-st511/worklink/internal/address"
	"github.com/young-st511/worklink/internal/model"
)

func fullConfig() model.Config {
	c := model.DefaultConfig()
	c.Hosts = []model.Host{{Name: "office", Helper: "/tmp/helper"}}
	c.ImageHost = "office"
	for i := 0; i < 16; i++ {
		c.Ports = append(c.Ports, model.Port{ID: model.NewID(), Host: "office", LocalPort: 4000 + i, Enabled: true, Endpoint: address.Parse(strconv.Itoa(4000 + i)).Endpoint})
	}
	return c
}
func TestReplaceOldestConfirmedInactivePort(t *testing.T) {
	e, err := New(t.TempDir(), nil, func(Event) {})
	if err != nil {
		t.Fatal(err)
	}
	if err = e.SaveConfig(fullConfig()); err != nil {
		t.Fatal(err)
	}
	e.state.On = true
	e.state.Generation = 1
	c := e.Snapshot().Config
	now := time.Now()
	e.now = func() time.Time { return now }
	e.recordPortChecks("office", map[string]bool{c.Ports[0].ID: false, c.Ports[1].ID: true}, 1)
	now = now.Add(time.Hour)
	e.recordPortChecks("office", map[string]bool{c.Ports[0].ID: false, c.Ports[1].ID: false}, 1)
	e.state.Hosts = []HostState{{Host: "office", Status: "connected"}}
	c.Ports = append(c.Ports, model.Port{ID: model.NewID(), Host: "office", LocalPort: 6000, Enabled: true, Endpoint: address.Parse("6000").Endpoint})
	adjusted, removed, err := e.trimInactive(c)
	if err != nil {
		t.Fatal(err)
	}
	if removed == nil || removed.LocalPort != 4000 || len(adjusted.Ports) != 16 {
		t.Fatal(removed, e.Snapshot())
	}
}
func TestReplacementProtectsUnknownActiveAndOffline(t *testing.T) {
	e, _ := New(t.TempDir(), nil, func(Event) {})
	if err := e.SaveConfig(fullConfig()); err != nil {
		t.Fatal(err)
	}
	e.state.On = true
	e.state.Generation = 1
	c := e.Snapshot().Config
	c.Ports = append(c.Ports, model.Port{ID: model.NewID(), Host: "office", LocalPort: 6000, Enabled: true, Endpoint: address.Parse("6000").Endpoint})
	for _, status := range []string{"connected", "backoff"} {
		e.state.Hosts = []HostState{{Host: "office", Status: status}}
		if _, err := e.saveConfig(c); err == nil {
			t.Fatal("unknown/offline ports evicted")
		}
	}
	checks := map[string]bool{}
	for _, p := range e.state.Config.Ports {
		checks[p.ID] = true
	}
	e.recordPortChecks("office", checks, 1)
	e.state.Hosts = []HostState{{Host: "office", Status: "connected"}}
	if _, err := e.saveConfig(c); err == nil {
		t.Fatal("active ports evicted")
	}
}
func TestPortInactivityPersistsWithoutHeartbeatWrites(t *testing.T) {
	e, _ := New(t.TempDir(), nil, func(Event) {})
	if err := e.SaveConfig(fullConfig()); err != nil {
		t.Fatal(err)
	}
	e.state.On = true
	e.state.Generation = 1
	id := e.state.Config.Ports[0].ID
	e.recordPortChecks("office", map[string]bool{id: false}, 1)
	path := filepath.Join(e.store.Root, "port-activity.json")
	before, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	for i := 0; i < 60; i++ {
		e.recordPortChecks("office", map[string]bool{id: false}, 1)
	}
	after, _ := os.Stat(path)
	if !os.SameFile(before, after) {
		t.Fatal("activity heartbeat wrote disk")
	}
	reloaded, err := New(e.store.Root, nil, func(Event) {})
	if err != nil {
		t.Fatal(err)
	}
	if reloaded.activity[id].InactiveSince != e.activity[id].InactiveSince {
		t.Fatal("lost inactivity start")
	}
}

func TestActivityWriteFailureRecovers(t *testing.T) {
	e, _ := New(t.TempDir(), nil, func(Event) {})
	if err := e.SaveConfig(fullConfig()); err != nil {
		t.Fatal(err)
	}
	e.state.On = true
	e.state.Generation = 1
	id := e.state.Config.Ports[0].ID
	path := filepath.Join(e.store.Root, "port-activity.json")
	if err := os.Mkdir(path, 0700); err != nil {
		t.Fatal(err)
	}
	e.recordPortChecks("office", map[string]bool{id: false}, 1)
	if _, ok := e.activity[id]; ok {
		t.Fatal("uncommitted activity retained")
	}
	os.Remove(path)
	e.recordPortChecks("office", map[string]bool{id: false}, 1)
	if _, err := os.Stat(path); err != nil {
		t.Fatal(err)
	}
}
func TestActivityIdentityAndFreshness(t *testing.T) {
	e, _ := New(t.TempDir(), nil, func(Event) {})
	if err := e.SaveConfig(fullConfig()); err != nil {
		t.Fatal(err)
	}
	e.state.On = true
	e.state.Generation = 1
	c := e.Snapshot().Config
	id := c.Ports[0].ID
	now := time.Now()
	e.now = func() time.Time { return now }
	e.recordPortChecks("office", map[string]bool{id: false}, 1)
	proposed := c
	proposed.Ports = append(append([]model.Port{}, c.Ports...), model.Port{ID: model.NewID(), Host: "office", LocalPort: 6000, Enabled: true, Endpoint: address.Parse("6000").Endpoint})
	e.state.Hosts = []HostState{{Host: "office", Status: "backoff"}}
	if _, _, err := e.trimInactive(proposed); err == nil {
		t.Fatal("disconnected eviction")
	}
	e.state.Hosts[0].Status = "connected"
	now = now.Add(16 * time.Second)
	if _, _, err := e.trimInactive(proposed); err == nil {
		t.Fatal("stale eviction")
	}
	e.recordPortChecks("office", map[string]bool{id: false}, 0)
	if _, _, err := e.trimInactive(proposed); err == nil {
		t.Fatal("old generation accepted")
	}
	reloaded, err := New(e.store.Root, nil, func(Event) {})
	if err != nil {
		t.Fatal(err)
	}
	reloaded.state.Hosts = e.state.Hosts
	if _, _, err := reloaded.trimInactive(proposed); err == nil {
		t.Fatal("restart without fresh check evicted")
	}
	changed := c
	changed.Ports = append([]model.Port{}, c.Ports...)
	changed.Ports[0].Endpoint = address.Parse("7000").Endpoint
	e.prunePortActivityLocked(c, changed)
	if _, ok := e.activity[id]; ok {
		t.Fatal("endpoint inherited activity")
	}
}
func TestFailedReachableWriteCannotEvictActivePort(t *testing.T) {
	e, _ := New(t.TempDir(), nil, func(Event) {})
	if err := e.SaveConfig(fullConfig()); err != nil {
		t.Fatal(err)
	}
	e.state.On = true
	e.state.Generation = 1
	c := e.Snapshot().Config
	id := c.Ports[0].ID
	e.recordPortChecks("office", map[string]bool{id: false}, 1)
	path := filepath.Join(e.store.Root, "port-activity.json")
	os.Remove(path)
	os.Mkdir(path, 0700)
	e.recordPortChecks("office", map[string]bool{id: true}, 1)
	e.state.Hosts = []HostState{{Host: "office", Status: "connected"}}
	c.Ports = append(c.Ports, model.Port{ID: model.NewID(), Host: "office", LocalPort: 6000, Enabled: true, Endpoint: address.Parse("6000").Endpoint})
	if _, _, err := e.trimInactive(c); err == nil {
		t.Fatal("active port evicted after write failure")
	}
}
func TestActivityIdentitySurvivesConfigCommitGap(t *testing.T) {
	e, _ := New(t.TempDir(), nil, func(Event) {})
	if err := e.SaveConfig(fullConfig()); err != nil {
		t.Fatal(err)
	}
	e.state.On = true
	e.state.Generation = 1
	c := e.Snapshot().Config
	id := c.Ports[0].ID
	e.recordPortChecks("office", map[string]bool{id: false}, 1)
	old := e.activity[id]
	c.Ports[0].Endpoint = address.Parse("7000").Endpoint
	if err := e.store.SaveConfig(&c); err != nil {
		t.Fatal(err)
	}
	reloaded, err := New(e.store.Root, nil, func(Event) {})
	if err != nil {
		t.Fatal(err)
	}
	reloaded.state.On = true
	reloaded.state.Generation = 1
	reloaded.now = func() time.Time { return old.InactiveSince.Add(time.Hour) }
	reloaded.recordPortChecks("office", map[string]bool{id: false}, 1)
	if !reloaded.activity[id].InactiveSince.After(old.InactiveSince) {
		t.Fatal("old endpoint inactivity restored")
	}
}
