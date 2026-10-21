package engine

import (
	"context"
	"errors"
	"strings"
	"time"

	"github.com/young-st511/worklink/internal/model"
)

// Called only by the existing cycle; peer forwarding maps remain cycle-owned.
func (e *Engine) cleanupPorts(ctx context.Context, gen uint64) error {
	e.configMu.Lock()
	defer e.configMu.Unlock()
	e.mu.Lock()
	c := e.state.Config
	now := e.now().UTC()
	if !e.state.On || e.state.Generation != gen || !c.PortCleanupEnabled || now.Before(e.portCleanupRetry) {
		e.mu.Unlock()
		return nil
	}
	if h := c.PortCleanupHistory; h != nil && !h.LastRun.IsZero() && now.Sub(h.LastRun) < 24*time.Hour {
		e.mu.Unlock()
		return nil
	}
	days := c.PortCleanupDays
	if days == 0 {
		days = 7
	}
	checkedAny := false
	remove := map[string]bool{}
	for _, p := range c.Ports {
		if _, ok := e.portObservedLocked(p, now); !ok {
			continue
		}
		checkedAny = true
		if e.portCleanupEligibleLocked(p, now, days) {
			remove[p.ID] = true
		}
	}
	if !checkedAny {
		e.mu.Unlock()
		return nil
	}
	ports := append([]model.Port{}, c.Ports...)
	peers := make(map[string]*peer, len(e.peers))
	for name, p := range e.peers {
		peers[name] = p
	}
	e.mu.Unlock()
	// Release only Worklink's own forwards for removed registrations. Never reconnect or stop a master.
	for _, port := range ports {
		if !remove[port.ID] {
			continue
		}
		p := peers[port.Host]
		if p == nil || !p.forwarded[port.ID] {
			continue
		}
		conn := p.conn()
		if conn == nil {
			return errors.New("SSH 연결이 바뀌어 정리를 보류했습니다")
		}
		selected := port
		if target := p.targets[port.ID]; target != "" {
			selected.Endpoint.RemoteHost = target
		}
		call, done := context.WithTimeout(ctx, 5*time.Second)
		err := conn.Forward(call, selected, true)
		done()
		if err != nil {
			return err
		}
		delete(p.forwarded, port.ID)
		delete(p.targets, port.ID)
		delete(p.forwardRetries, port.ID)
	}
	e.mu.Lock()
	defer e.mu.Unlock()
	if !e.state.On || e.state.Generation != gen || ctx.Err() != nil {
		return nil
	}
	// Title refresh may have changed the revision while forwards were released.
	c = e.state.Config
	now = e.now().UTC()
	for _, port := range c.Ports {
		if remove[port.ID] && !e.portCleanupEligibleLocked(port, now, days) {
			delete(remove, port.ID)
		}
	}
	fresh := false
	for _, port := range c.Ports {
		if _, ok := e.portObservedLocked(port, now); ok {
			fresh = true
			break
		}
	}
	if !fresh {
		return nil
	}
	next := c
	next.Ports = []model.Port{}
	history := model.PortCleanupHistory{LastRun: now, Removed: []model.Port{}}
	if c.PortCleanupHistory != nil {
		history = *c.PortCleanupHistory
		history.LastRun = now
		history.Removed = append([]model.Port{}, history.Removed...)
	}
	removed := []model.Port{}
	for _, p := range c.Ports {
		if remove[p.ID] && !p.Pinned && p.Enabled {
			removed = append(removed, p)
		} else {
			next.Ports = append(next.Ports, p)
		}
	}
	if len(removed) > 0 {
		history.RemovedAt = now
		history.Removed = removed
	}
	next.PortCleanupHistory = &history
	if err := e.store.SaveConfig(&next); err != nil {
		return err
	}
	e.state.Config = next
	e.portCleanupRetry = time.Time{}
	if strings.HasPrefix(e.state.Error, "포트 자동 정리: ") {
		e.state.Error = ""
	}
	e.prunePortActivityLocked(c, next)
	kept := []PortState{}
	for _, p := range e.state.Ports {
		if !remove[p.ID] {
			kept = append(kept, p)
		}
	}
	e.state.Ports = kept
	return nil
}
func (e *Engine) UndoPortCleanup() error {
	e.configMu.Lock()
	defer e.configMu.Unlock()
	e.mu.Lock()
	defer e.mu.Unlock()
	c := e.state.Config
	h := c.PortCleanupHistory
	if h == nil || len(h.Removed) == 0 {
		return errors.New("되돌릴 포트 정리 기록이 없습니다")
	}
	next := c
	next.Ports = append([]model.Port{}, c.Ports...)
	for _, p := range h.Removed {
		p.Pinned = true
		next.Ports = append(next.Ports, p)
	}
	if err := next.Validate(); err != nil {
		return errors.New("복원할 포트의 상한·중복 또는 원래 SSH 대상을 확인해 주세요: " + err.Error())
	}
	history := *h
	history.Removed = []model.Port{}
	next.PortCleanupHistory = &history
	if err := e.store.SaveConfig(&next); err != nil {
		return err
	}
	e.state.Config = next
	select {
	case e.wake <- struct{}{}:
	default:
	}
	return nil
}
func (e *Engine) SetPortPinned(id string, on bool) error {
	e.configMu.Lock()
	defer e.configMu.Unlock()
	e.mu.Lock()
	defer e.mu.Unlock()
	c := e.state.Config
	c.Ports = append([]model.Port{}, c.Ports...)
	found := false
	for i := range c.Ports {
		if c.Ports[i].ID == id {
			c.Ports[i].Pinned = on
			found = true
		}
	}
	if !found {
		return errors.New("등록된 포트가 없습니다")
	}
	if err := e.store.SaveConfig(&c); err != nil {
		return err
	}
	e.state.Config = c
	return nil
}

func (e *Engine) portObservedLocked(p model.Port, now time.Time) (portActivity, bool) {
	if e.activityDirty {
		return portActivity{}, false
	}
	a, ok := e.activity[p.ID]
	checked := e.checkedAt[p.ID]
	if !p.Enabled || !ok || a.Identity != portIdentity(p) || checked.IsZero() || now.Sub(checked) < 0 || now.Sub(checked) > 15*time.Second {
		return a, false
	}
	for _, h := range e.state.Hosts {
		if h.Host == p.Host && h.Status == "connected" {
			return a, true
		}
	}
	return a, false
}
func (e *Engine) portCleanupEligibleLocked(p model.Port, now time.Time, days int) bool {
	a, ok := e.portObservedLocked(p, now)
	if !ok || p.Pinned || a.Reachable || a.InactiveSince.IsZero() {
		return false
	}
	since := a.LastActive
	if since.IsZero() {
		since = a.FirstSeen
	}
	return !since.IsZero() && now.Sub(since) >= time.Duration(days)*24*time.Hour
}

// Policy changes do not restart SSH sessions or interrupt transfers.
func (e *Engine) SetPortCleanup(enabled bool, days int) error {
	e.configMu.Lock()
	defer e.configMu.Unlock()
	e.mu.Lock()
	defer e.mu.Unlock()
	c := e.state.Config
	c.PortCleanupEnabled = enabled
	c.PortCleanupDays = days
	if err := e.store.SaveConfig(&c); err != nil {
		return err
	}
	e.state.Config = c
	return nil
}
