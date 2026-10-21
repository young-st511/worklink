package engine

import (
	"encoding/json"
	"errors"
	"path/filepath"
	"reflect"
	"time"

	"github.com/young-st511/worklink/internal/model"
	"github.com/young-st511/worklink/internal/storage"
)

func (e *Engine) recordPortChecks(host string, checks map[string]bool, gen uint64) {
	e.mu.Lock()
	defer e.mu.Unlock()
	if !e.state.On || e.state.Generation != gen {
		return
	}
	previousActivity := make(map[string]portActivity, len(e.activity))
	for id, value := range e.activity {
		previousActivity[id] = value
	}
	changed := false
	for _, port := range e.state.Config.Ports {
		ready, ok := checks[port.ID]
		if port.Host != host || !port.Enabled || !ok {
			continue
		}
		e.checkedAt[port.ID] = e.now()
		previous, exists := e.activity[port.ID]
		if exists && previous.Identity == portIdentity(port) && previous.Reachable == ready {
			continue
		}
		current := portActivity{Identity: portIdentity(port), Reachable: ready}
		if !ready {
			current.InactiveSince = e.now().UTC()
		}
		e.activity[port.ID] = current
		changed = true
	}
	if changed {
		if err := storage.AtomicJSON(filepath.Join(e.store.Root, "port-activity.json"), e.activity); err != nil {
			e.state.Error = err.Error()
			e.activity = previousActivity
			e.checkedAt = map[string]time.Time{}
		}
	}
}
func (e *Engine) trimInactive(c model.Config) (model.Config, *model.Port, error) {
	if len(c.Ports) <= 16 {
		return c, nil, c.Validate()
	}
	if err := c.ValidatePortAddition(); err != nil {
		return c, nil, err
	}
	e.mu.Lock()
	defer e.mu.Unlock()
	if c.Revision != e.state.Config.Revision || len(c.Ports) != 17 || len(e.state.Config.Ports) != 16 {
		return c, nil, errors.New("포트 상한에서 새 항목 하나만 추가할 수 있습니다. 설정을 다시 읽어 주세요")
	}
	byID := map[string]model.Port{}
	for _, p := range c.Ports {
		byID[p.ID] = p
	}
	for _, p := range e.state.Config.Ports {
		if !reflect.DeepEqual(p, byID[p.ID]) {
			return c, nil, errors.New("기존 포트 수정과 자동 교체를 동시에 할 수 없습니다")
		}
	}
	candidate := -1
	var oldest time.Time
	for n, port := range e.state.Config.Ports {
		a, ok := e.activity[port.ID]
		if !ok || a.Identity != portIdentity(port) || a.Reachable || a.InactiveSince.IsZero() {
			continue
		}
		checked := e.checkedAt[port.ID]
		if checked.IsZero() || e.now().Sub(checked) > 15*time.Second {
			continue
		}
		connected := false
		for _, h := range e.state.Hosts {
			if h.Host == port.Host && h.Status == "connected" {
				connected = true
			}
		}
		if !connected {
			continue
		}
		if candidate < 0 || a.InactiveSince.Before(oldest) {
			candidate = n
			oldest = a.InactiveSince
		}
	}
	if candidate < 0 {
		return c, nil, errors.New("서버 16개가 모두 활성 또는 미확인 상태입니다. 업무 ON에서 비활성 상태를 확인하거나 항목을 직접 제거해 주세요")
	}
	removed := e.state.Config.Ports[candidate]
	ports := make([]model.Port, 0, 16)
	for _, p := range c.Ports {
		if p.ID != removed.ID {
			ports = append(ports, p)
		}
	}
	c.Ports = ports
	return c, &removed, c.Validate()
}

func (e *Engine) prunePortActivityLocked(previous, c model.Config) {
	ids := map[string]bool{}
	old := map[string]model.Port{}
	for _, p := range previous.Ports {
		old[p.ID] = p
	}
	for _, p := range c.Ports {
		prior, ok := old[p.ID]
		ids[p.ID] = ok && prior.Host == p.Host && prior.Endpoint == p.Endpoint
	}
	changed := false
	for id := range e.activity {
		if !ids[id] {
			delete(e.activity, id)
			delete(e.checkedAt, id)
			changed = true
		}
	}
	if changed {
		if err := storage.AtomicJSON(filepath.Join(e.store.Root, "port-activity.json"), e.activity); err != nil {
			e.state.Error = err.Error()
		}
	}
}

func portIdentity(p model.Port) string {
	b, _ := json.Marshal(struct {
		Host     string
		Endpoint any
	}{p.Host, p.Endpoint})
	return string(b)
}
