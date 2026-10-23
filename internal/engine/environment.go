package engine

import (
	"context"
	"errors"
	"time"
)

// SetEnvironment changes runtime hints, never the user's ON intent or a peer's retry budget.
func (e *Engine) SetEnvironment(available, lowPower bool) {
	e.mu.Lock()
	if e.closing {
		e.mu.Unlock()
		return
	}
	changed := e.state.NetworkUnavailable != !available || e.state.LowPower != lowPower
	if !changed {
		e.mu.Unlock()
		return
	}
	lost := available == false && !e.state.NetworkUnavailable
	e.state.NetworkUnavailable = !available
	e.state.LowPower = lowPower
	if lost {
		if e.networkCancel != nil {
			e.networkCancel()
		}
		e.resetNetwork = true
		e.checkedAt = map[string]time.Time{}
		for _, p := range e.peers {
			if conn := p.conn(); conn != nil {
				e.closeAsyncLocked(conn)
			}
		}
		dirty := false
		for i := range e.state.Jobs {
			if e.state.Jobs[i].Status == "sending" {
				e.state.Jobs[i].Status = "queued"
				dirty = true
			}
		}
		if dirty {
			if err := e.saveJobsLocked(); err != nil {
				e.state.Error = err.Error()
			}
		}
		for i := range e.state.Hosts {
			if e.state.Hosts[i].Status == "blocked" || e.state.Hosts[i].Status == "backoff" {
				continue
			}
			e.state.Hosts[i].Status = "offline"
			e.state.Hosts[i].Error = "네트워크 연결을 기다립니다"
		}
		for i := range e.state.Ports {
			e.state.Ports[i].Status = "waiting"
			e.state.Ports[i].Reachable = false
			e.state.Ports[i].Error = "네트워크 연결을 기다립니다"
		}
	} else if available && (e.networkContext == nil || e.networkContext.Err() != nil) {
		e.networkContext, e.networkCancel = context.WithCancel(context.Background())
		for i := range e.state.Hosts {
			if e.state.Hosts[i].Status == "offline" {
				e.state.Hosts[i].Status = "waiting"
				e.state.Hosts[i].Error = "SSH 재연결을 기다립니다"
			}
		}
	}
	e.mu.Unlock()
	e.signalWake()
	e.publish()
}
func (e *Engine) signalWake() {
	select {
	case e.wake <- struct{}{}:
	default:
	}
}
func (e *Engine) onlineContext(parent context.Context) (context.Context, context.CancelFunc) {
	e.mu.Lock()
	network := e.networkContext
	e.mu.Unlock()
	if network == nil {
		network = context.Background()
	}
	ctx, cancel := context.WithCancel(parent)
	stop := context.AfterFunc(network, cancel)
	if network.Err() != nil {
		cancel()
	}
	return ctx, func() { stop(); cancel() }
}
func checkInterval(lowPower bool, ports int) time.Duration {
	if ports == 0 {
		return time.Minute
	}
	if lowPower {
		return 30 * time.Second
	}
	return 5 * time.Second
}
func (e *Engine) RequestPortRefresh() error {
	e.mu.Lock()
	defer e.mu.Unlock()
	if !e.state.On {
		return errors.New("업무 모드를 켜 주세요")
	}
	if e.state.NetworkUnavailable {
		return errors.New("네트워크 연결을 기다려 주세요")
	}
	now := e.now()
	if !e.lastManualRefresh.IsZero() && now.Sub(e.lastManualRefresh) < 2*time.Second {
		return nil
	}
	e.lastManualRefresh = now
	e.forceCheck = true
	e.signalWake()
	return nil
}

// Only the loop touches peer scheduling fields. OFF and unavailable networks need no timer.
func (e *Engine) nextDelay(gen uint64) time.Duration {
	e.mu.Lock()
	defer e.mu.Unlock()
	if !e.state.On || e.state.Generation != gen || e.state.NetworkUnavailable {
		return 0
	}
	needed := map[string]bool{}
	counts := map[string]int{}
	if e.state.Config.ImageHost != "" {
		needed[e.state.Config.ImageHost] = true
	}
	for _, p := range e.state.Config.Ports {
		if p.Enabled {
			needed[p.Host] = true
			counts[p.Host]++
		}
	}
	for _, j := range e.state.Jobs {
		if j.Status == "queued" && j.Generation == gen {
			needed[j.Host] = true
		}
	}
	now := e.now()
	var next time.Time
	for _, j := range e.state.Jobs {
		if j.Status == "queued" && j.Generation == gen {
			due := j.CreatedAt.Add(30*time.Minute + time.Millisecond)
			if e.expiryRetry.After(due) {
				due = e.expiryRetry
			}
			if next.IsZero() || due.Before(next) {
				next = due
			}
		}
	}
	for host := range needed {
		p := e.peers[host]
		due := now
		if p != nil {
			if p.blocked {
				continue
			}
			if p.conn() == nil {
				due = p.next
				if due.IsZero() {
					due = now
				}
				if p.recoveryNotBefore.After(due) {
					due = p.recoveryNotBefore
				}
			} else {
				due = p.lastCheck.Add(checkInterval(e.state.LowPower, counts[host]))
			}
		}
		for _, retry := range pRetries(p) {
			if retry.next.Before(due) {
				due = retry.next
			}
		}
		if next.IsZero() || due.Before(next) {
			next = due
		}
	}
	if next.IsZero() {
		return 0
	}
	delay := next.Sub(now)
	if delay < 100*time.Millisecond {
		return 100 * time.Millisecond
	}
	return delay
}

func pRetries(p *peer) map[string]forwardRetry {
	if p == nil {
		return nil
	}
	return p.forwardRetries
}
