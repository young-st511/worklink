package engine

import (
	"encoding/json"
	"errors"
	"path/filepath"
	"reflect"
	"strings"
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
	changed := false
	for _, port := range e.state.Config.Ports {
		ready, ok := checks[port.ID]
		if port.Host != host || !port.Enabled || !ok {
			continue
		}
		e.checkedAt[port.ID] = e.now()
		previous, exists := e.activity[port.ID]
		same := exists && previous.Identity == portIdentity(port)
		if same && !previous.FirstSeen.IsZero() && previous.Reachable == ready {
			if ready {
				previous.LastActive = e.now().UTC()
				e.activity[port.ID] = previous
			}
			continue
		}
		current := portActivity{Identity: portIdentity(port), FirstSeen: e.now().UTC()}
		if same {
			current = previous
			if current.FirstSeen.IsZero() {
				current.FirstSeen = e.now().UTC()
			}
		}
		current.Reachable = ready
		if ready {
			current.LastActive = e.now().UTC()
			current.InactiveSince = time.Time{}
		} else {
			if !same || previous.Reachable || current.InactiveSince.IsZero() {
				current.InactiveSince = e.now().UTC()
			}
			// A persisted reachable record may predate a crash. Start a conservative inactivity window now.
			if same && previous.Reachable {
				current.LastActive = e.now().UTC()
			}
		}
		e.activity[port.ID] = current
		changed = true
	}
	if changed || e.activityDirty {
		if err := storage.AtomicJSON(filepath.Join(e.store.Root, "port-activity.json"), e.activity); err != nil {
			e.state.Error = "포트 활동 기록: " + err.Error()
			e.activityDirty = true
			e.checkedAt = map[string]time.Time{}
		} else {
			e.activityDirty = false
			if strings.HasPrefix(e.state.Error, "포트 활동 기록: ") {
				e.state.Error = ""
			}
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
	if e.activityDirty {
		return c, nil, errors.New("활동 기록 저장을 확인한 후 다시 등록해 주세요")
	}
	candidate := -1
	var oldest time.Time
	for n, port := range e.state.Config.Ports {
		if port.Pinned || !port.Enabled {
			continue
		}
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
		return c, nil, errors.New("서버 16개가 모두 활성·고정·중지 또는 미확인 상태입니다. 서버 상태 새로고침 후 다시 등록하거나 항목을 직접 제거해 주세요")
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
	if changed || e.activityDirty {
		if err := storage.AtomicJSON(filepath.Join(e.store.Root, "port-activity.json"), e.activity); err != nil {
			e.state.Error = "포트 활동 기록: " + err.Error()
			e.activityDirty = true
		} else {
			e.activityDirty = false
			if strings.HasPrefix(e.state.Error, "포트 활동 기록: ") {
				e.state.Error = ""
			}
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
