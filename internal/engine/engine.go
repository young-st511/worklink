package engine

import (
	"context"
	"crypto/sha256"
	"encoding/json"
	"errors"
	"fmt"
	"html"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/young-st511/worklink/internal/address"
	"github.com/young-st511/worklink/internal/model"
	"github.com/young-st511/worklink/internal/remote"
	"github.com/young-st511/worklink/internal/storage"
	"github.com/young-st511/worklink/internal/transport"
)

type Job struct {
	model.Image
	RemotePath string `json:"remote_path,omitempty"`
}
type HostState struct {
	Host   string `json:"host"`
	Status string `json:"status"`
	Error  string `json:"error,omitempty"`
}
type PortState struct {
	ID         string `json:"id"`
	Status     string `json:"status"`
	Error      string `json:"error,omitempty"`
	Reachable  bool   `json:"reachable"`
	RemoteHost string `json:"remote_host,omitempty"`
}
type State struct {
	On         bool           `json:"on"`
	Generation uint64         `json:"generation"`
	Config     model.Config   `json:"config"`
	Hosts      []HostState    `json:"hosts"`
	Ports      []PortState    `json:"ports"`
	Files      []FileTransfer `json:"files,omitempty"`
	Jobs       []Job          `json:"jobs"`
	Version    string         `json:"version"`
	Error      string         `json:"error,omitempty"`
}
type Event struct {
	Kind   string `json:"kind"`
	ID     string `json:"id,omitempty"`
	State  *State `json:"state,omitempty"`
	Job    *Job   `json:"job,omitempty"`
	Result any    `json:"result,omitempty"`
	Error  string `json:"error,omitempty"`
}
type Connector func(context.Context, model.Host) (transport.Connection, error)
type forwardRetry struct {
	attempt int
	next    time.Time
	target  string
}

type peer struct {
	mu             sync.Mutex
	connection     transport.Connection
	forwarded      map[string]bool
	targets        map[string]string
	attempt        int
	next           time.Time
	blocked        bool
	forwardRetries map[string]forwardRetry
}

func (p *peer) conn() transport.Connection     { p.mu.Lock(); defer p.mu.Unlock(); return p.connection }
func (p *peer) setConn(c transport.Connection) { p.mu.Lock(); defer p.mu.Unlock(); p.connection = c }

type portActivity struct {
	Identity      string    `json:"identity"`
	Reachable     bool      `json:"reachable"`
	InactiveSince time.Time `json:"inactive_since"`
}

type Engine struct {
	mu          sync.Mutex
	restoreMu   sync.Mutex
	fileBatchMu sync.Mutex
	fileCancel  context.CancelFunc
	session     context.Context
	store       *storage.Store
	state       State
	connect     Connector
	emit        func(Event)
	cancel      context.CancelFunc
	peers       map[string]*peer
	wake        chan struct{}
	now         func() time.Time
	activity    map[string]portActivity
	checkedAt   map[string]time.Time
}

func New(root string, connect Connector, emit func(Event)) (*Engine, error) {
	s, err := storage.Open(root, model.DefaultConfig().Limits)
	if err != nil {
		return nil, err
	}
	c, err := s.LoadConfig()
	if err != nil {
		return nil, err
	}
	s.Limits = c.Limits
	e := &Engine{activity: map[string]portActivity{}, checkedAt: map[string]time.Time{}, now: time.Now, store: s, connect: connect, emit: emit, peers: map[string]*peer{}, wake: make(chan struct{}, 1), state: State{Config: c, Version: model.Version, Hosts: []HostState{}, Ports: []PortState{}, Jobs: []Job{}}}
	if connect == nil {
		e.connect = transport.Connect
	}
	b, err := os.ReadFile(filepath.Join(root, "jobs.json"))
	if err == nil {
		if err = json.Unmarshal(b, &e.state.Jobs); err != nil {
			return nil, err
		}
		for n := range e.state.Jobs {
			if e.state.Jobs[n].Status == "queued" || e.state.Jobs[n].Status == "sending" {
				e.state.Jobs[n].Status = "paused"
			}
		}
	} else if !os.IsNotExist(err) {
		return nil, err
	}
	if err = e.recoverQueue(); err != nil {
		return nil, err
	}
	if data, err := os.ReadFile(filepath.Join(root, "port-activity.json")); err == nil {
		if err = json.Unmarshal(data, &e.activity); err != nil {
			return nil, err
		}
	} else if !os.IsNotExist(err) {
		return nil, err
	}
	if e.activity == nil {
		e.activity = map[string]portActivity{}
	}
	if err = e.loadFiles(); err != nil {
		return nil, err
	}
	return e, nil
}
func (e *Engine) Snapshot() State {
	e.mu.Lock()
	defer e.mu.Unlock()
	s := e.state
	s.Config.Hosts = append([]model.Host{}, s.Config.Hosts...)
	s.Config.Ports = append([]model.Port{}, s.Config.Ports...)
	s.Hosts = append([]HostState{}, s.Hosts...)
	s.Ports = append([]PortState{}, s.Ports...)
	s.Files = append([]FileTransfer{}, s.Files...)
	s.Jobs = append([]Job{}, s.Jobs...)
	sort.Slice(s.Jobs, func(i, j int) bool { return s.Jobs[i].CreatedAt.After(s.Jobs[j].CreatedAt) })
	if len(s.Jobs) > 5 {
		s.Jobs = s.Jobs[:5]
	}
	return s
}
func (e *Engine) publish() { s := e.Snapshot(); e.emit(Event{Kind: "state", State: &s}) }
func (e *Engine) saveJobsLocked() error {
	return storage.AtomicJSON(filepath.Join(e.store.Root, "jobs.json"), e.state.Jobs)
}
func (e *Engine) queuePath(j Job) string {
	return filepath.Join(e.store.Root, "queue", j.ID+"."+j.Extension)
}
func (e *Engine) SetOn(on bool) {
	e.mu.Lock()
	if e.state.On == on {
		e.mu.Unlock()
		return
	}
	e.state.On = on
	e.state.Generation++
	gen := e.state.Generation
	oldCancel := e.cancel
	oldPeers := e.peers
	e.peers = map[string]*peer{}
	e.checkedAt = map[string]time.Time{}
	e.state.Hosts = []HostState{}
	e.state.Ports = []PortState{}
	for n := range e.state.Jobs {
		if e.state.Jobs[n].Status == "queued" || e.state.Jobs[n].Status == "sending" {
			e.state.Jobs[n].Status = "paused"
		}
	}
	e.saveJobsLocked()
	ctx, cancel := context.WithCancel(context.Background())
	e.cancel = cancel
	e.session = ctx
	e.mu.Unlock()
	if oldCancel != nil {
		oldCancel()
	}
	e.publish()
	var wg sync.WaitGroup
	for _, p := range oldPeers {
		if conn := p.conn(); conn != nil {
			wg.Add(1)
			go func(c transport.Connection) { defer wg.Done(); c.Close() }(conn)
		}
	}
	wg.Wait()
	if on {
		go e.loop(ctx, gen)
	} else {
		cancel()
	}
}
func (e *Engine) SaveConfig(c model.Config) error { _, err := e.saveConfig(c); return err }
func (e *Engine) saveConfig(c model.Config) (*model.Port, error) {
	c, removed, err := e.trimInactive(c)
	if err != nil {
		return nil, err
	}
	if err := c.Validate(); err != nil {
		return nil, err
	}
	e.mu.Lock()
	for _, j := range e.state.Jobs {
		if j.Status != "complete" {
			if _, ok := c.Host(j.Host); !ok {
				e.mu.Unlock()
				return nil, errors.New("대기 이미지가 있는 SSH 대상은 삭제하거나 이름을 바꿀 수 없습니다. 먼저 대기 파일을 정리해 주세요")
			}
		}
	}
	e.mu.Unlock()
	wasOn := e.Snapshot().On
	e.SetOn(false)
	if err := e.store.SaveConfig(&c); err != nil {
		if wasOn {
			e.SetOn(true)
		}
		return nil, err
	}
	e.mu.Lock()
	e.prunePortActivityLocked(e.state.Config, c)
	e.state.Config = c
	e.store.Limits = c.Limits
	e.mu.Unlock()
	e.publish()
	if wasOn {
		e.SetOn(true)
	}
	return removed, nil
}
func (e *Engine) Enqueue(path, ext string, count int) (Job, error) {
	e.mu.Lock()
	defer e.mu.Unlock()
	c := e.state.Config
	if !e.state.On || c.ImageHost == "" {
		return Job{}, errors.New("업무 모드를 켜고 이미지 전송 대상을 선택해 주세요")
	}
	if !model.ValidExtension(ext) {
		return Job{}, errors.New("원본 이미지 형식을 지원하지 않습니다")
	}
	pending, size, err := e.queueUsage()
	if err != nil {
		return Job{}, err
	}
	if pending >= c.Limits.QueueCount {
		return Job{}, errors.New("대기 이미지 수 제한을 초과했습니다")
	}
	src, err := os.Open(path)
	if err != nil {
		return Job{}, err
	}
	defer src.Close()
	st, err := src.Stat()
	if err != nil || !st.Mode().IsRegular() || st.Size() < 1 || st.Size() > c.Limits.ImageBytes || size+st.Size() > c.Limits.QueueBytes {
		return Job{}, errors.New("원본 이미지 또는 대기 용량 제한을 초과했습니다. 압축하지 않고 전송을 중지했습니다")
	}
	j := Job{Image: model.Image{ID: model.NewID(), Host: c.ImageHost, CreatedAt: time.Now().UTC(), Size: st.Size(), Extension: ext, ClipboardCount: count, Generation: e.state.Generation, Status: "queued"}}
	j.Path = e.queuePath(j)
	if err = storage.AtomicJSON(e.journal(j), j); err != nil {
		return j, err
	}
	defer os.Remove(e.journal(j))
	dst, err := os.OpenFile(j.Path, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0600)
	if err != nil {
		return j, err
	}
	h := sha256.New()
	n, err := io.Copy(io.MultiWriter(dst, h), io.LimitReader(src, c.Limits.ImageBytes+1))
	if err == nil {
		err = dst.Sync()
	}
	ce := dst.Close()
	if err == nil {
		err = ce
	}
	if err != nil || n != j.Size {
		os.Remove(j.Path)
		return j, errors.New("원본 파일이 변경됐거나 읽기에 실패했습니다")
	}
	j.SHA256 = fmt.Sprintf("%x", h.Sum(nil))
	e.state.Jobs = append(e.state.Jobs, j)
	if err = e.saveJobsLocked(); err != nil {
		e.state.Jobs = e.state.Jobs[:len(e.state.Jobs)-1]
		os.Remove(j.Path)
		return j, err
	}
	os.Remove(e.journal(j))
	select {
	case e.wake <- struct{}{}:
	default:
	}
	return j, nil
}
func (e *Engine) Retry(id string) error {
	e.mu.Lock()
	defer e.mu.Unlock()
	if !e.state.On {
		return errors.New("업무 모드를 켜 주세요")
	}
	for n, j := range e.state.Jobs {
		if j.ID == id {
			if j.Status == "complete" {
				return errors.New("이미 전송된 이미지입니다")
			}
			if time.Since(j.CreatedAt) > 30*time.Minute {
				return errors.New("30분이 지난 대기 이미지입니다. 다시 캡처해 주세요")
			}
			if _, ok := e.state.Config.Host(j.Host); !ok {
				return errors.New("원래 이미지 전송 대상을 다시 등록해 주세요")
			}
			if _, err := os.Stat(e.queuePath(j)); err != nil && !os.IsNotExist(err) {
				return err
			}
			e.state.Jobs[n].Status = "queued"
			e.state.Jobs[n].Error = ""
			e.state.Jobs[n].Generation = e.state.Generation
			if err := e.saveJobsLocked(); err != nil {
				return err
			}
			select {
			case e.wake <- struct{}{}:
			default:
			}
			return nil
		}
	}
	return errors.New("이미지 기록이 없습니다")
}
func (e *Engine) hostStatus(host, status, message string) {
	e.mu.Lock()
	defer e.mu.Unlock()
	for n, h := range e.state.Hosts {
		if h.Host == host {
			e.state.Hosts[n] = HostState{host, status, message}
			return
		}
	}
	e.state.Hosts = append(e.state.Hosts, HostState{host, status, message})
}
func (e *Engine) portStatus(gen uint64, id, status, message string, reachable bool, host string) {
	e.mu.Lock()
	defer e.mu.Unlock()
	if !e.state.On || e.state.Generation != gen {
		return
	}
	value := PortState{ID: id, Status: status, Error: message, Reachable: reachable, RemoteHost: host}
	for n, p := range e.state.Ports {
		if p.ID == id {
			e.state.Ports[n] = value
			return
		}
	}
	e.state.Ports = append(e.state.Ports, value)
}

func (e *Engine) current(gen uint64) bool {
	e.mu.Lock()
	defer e.mu.Unlock()
	return e.state.On && e.state.Generation == gen
}
func (e *Engine) loop(ctx context.Context, gen uint64) {
	ticker := time.NewTicker(5 * time.Second)
	defer ticker.Stop()
	for {
		if !e.current(gen) {
			return
		}
		e.cycle(ctx, gen)
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		case <-e.wake:
		}
	}
}
func (e *Engine) cycle(ctx context.Context, gen uint64) {
	snap := e.Snapshot()
	needed := map[string]bool{}
	if snap.Config.ImageHost != "" {
		needed[snap.Config.ImageHost] = true
	}
	for _, p := range snap.Config.Ports {
		if p.Enabled {
			needed[p.Host] = true
		}
	}
	e.mu.Lock()
	for _, j := range e.state.Jobs {
		if j.Status == "queued" && j.Generation == gen {
			needed[j.Host] = true
		}
	}
	e.mu.Unlock()
	for _, h := range snap.Config.Hosts {
		if !needed[h.Name] || !e.current(gen) {
			continue
		}
		e.mu.Lock()
		if !e.state.On || e.state.Generation != gen {
			e.mu.Unlock()
			return
		}
		p := e.peers[h.Name]
		if p == nil {
			p = &peer{forwarded: map[string]bool{}}
			e.peers[h.Name] = p
		}
		e.mu.Unlock()
		if p.blocked || time.Now().Before(p.next) {
			continue
		}
		if p.conn() == nil {
			e.hostStatus(h.Name, "connecting", "")
			e.publish()
			conn, err := e.connect(ctx, h)
			if !e.current(gen) {
				if conn != nil {
					conn.Close()
				}
				return
			}
			if err != nil {
				e.failedPeer(h.Name, p, err)
				continue
			}
			if !e.current(gen) {
				conn.Close()
				return
			}
			p.setConn(conn)
			setup, cancel := context.WithTimeout(ctx, 8*time.Second)
			_, err = conn.Call(setup, remote.Request{Op: "limits", Limits: &snap.Config.Limits}, nil)
			cancel()
			if !e.current(gen) {
				conn.Close()
				return
			}
			if err != nil {
				e.failedPeer(h.Name, p, err)
				continue
			}
			p.attempt = 0
			e.hostStatus(h.Name, "connected", "")
		}
		endpoints := map[string]address.Endpoint{}
		for _, port := range snap.Config.Ports {
			if port.Host == h.Name && port.Enabled {
				endpoints[port.ID] = port.Endpoint
			}
		}
		checkCtx, cancel := context.WithTimeout(ctx, 8*time.Second)
		r, err := p.conn().Call(checkCtx, remote.Request{Op: "check", Endpoints: endpoints}, nil)
		cancel()
		if !e.current(gen) {
			return
		}
		if err != nil {
			e.failedPeer(h.Name, p, err)
			continue
		}
		e.recordPortChecks(h.Name, r.Checks, gen)
		if p.forwardRetries == nil {
			p.forwardRetries = map[string]forwardRetry{}
		}
		if p.targets == nil {
			p.targets = map[string]string{}
		}
		for _, port := range snap.Config.Ports {
			if port.Host != h.Name || !port.Enabled {
				continue
			}
			if !e.current(gen) {
				return
			}
			ready := r.Checks[port.ID]
			target := port.Endpoint.RemoteHost
			if resolved := r.Targets[port.ID]; resolved != "" {
				if !port.Endpoint.AllowsTarget(resolved) {
					e.failedPeer(h.Name, p, errors.New("원격 연결 주소가 등록 범위를 벗어났습니다"))
					return
				}
				target = resolved
			} else if !ready && p.forwarded[port.ID] && p.targets[port.ID] != "" {
				target = p.targets[port.ID]
			}
			conn := p.conn()
			if conn == nil {
				return
			}
			if p.forwarded[port.ID] && p.targets[port.ID] != target {
				previous := port
				previous.Endpoint.RemoteHost = p.targets[port.ID]
				forwardCtx, done := context.WithTimeout(ctx, 5*time.Second)
				problem := conn.Forward(forwardCtx, previous, true)
				done()
				if !e.current(gen) {
					return
				}
				if problem != nil {
					e.failedPeer(h.Name, p, problem)
					return
				}
				delete(p.forwarded, port.ID)
				delete(p.targets, port.ID)
			}
			selected := port
			selected.Endpoint.RemoteHost = target
			if !p.forwarded[port.ID] {
				retry := p.forwardRetries[port.ID]
				if retry.target == target && e.now().Before(retry.next) {
					continue
				}
				forwardCtx, done := context.WithTimeout(ctx, 5*time.Second)
				problem := conn.Forward(forwardCtx, selected, false)
				done()
				if !e.current(gen) {
					return
				}
				if problem != nil {
					retry.attempt++
					retry.target = target
					delay := 10 * time.Second << min(retry.attempt-1, 3)
					if delay > time.Minute {
						delay = time.Minute
					}
					retry.next = e.now().Add(delay)
					p.forwardRetries[port.ID] = retry
					e.portStatus(gen, port.ID, "conflict", problem.Error(), false, target)
					continue
				}
				delete(p.forwardRetries, port.ID)
				p.forwarded[port.ID] = true
				p.targets[port.ID] = target
			}
			status := "waiting"
			if ready {
				status = "ready"
			}
			e.portStatus(gen, port.ID, status, r.CheckErrors[port.ID], ready, target)
		}
	}
	if e.current(gen) {
		e.sendNext(ctx, gen)
	}
	if e.current(gen) {
		e.publish()
	}
}
func (e *Engine) failedPeer(host string, p *peer, err error) {
	if conn := p.conn(); conn != nil {
		conn.Close()
	}
	p.setConn(nil)
	p.forwarded = map[string]bool{}
	p.targets = map[string]string{}
	p.forwardRetries = map[string]forwardRetry{}
	p.attempt++
	delay := time.Second << min(p.attempt-1, 6)
	if delay > 60*time.Second {
		delay = 60 * time.Second
	}
	p.next = time.Now().Add(delay)
	message := err.Error()
	for _, text := range []string{"Permission denied", "Host key verification failed", "REMOTE HOST IDENTIFICATION HAS CHANGED"} {
		if strings.Contains(message, text) {
			p.blocked = true
		}
	}
	status := "backoff"
	if p.blocked {
		status = "blocked"
	}
	e.mu.Lock()
	current := e.state.On && e.peers[host] == p
	if current {
		found := false
		for n, h := range e.state.Hosts {
			if h.Host == host {
				e.state.Hosts[n] = HostState{host, status, message}
				found = true
				break
			}
		}
		if !found {
			e.state.Hosts = append(e.state.Hosts, HostState{host, status, message})
		}
		for n, portState := range e.state.Ports {
			for _, port := range e.state.Config.Ports {
				if port.ID == portState.ID && port.Host == host {
					e.state.Ports[n].Status = "waiting"
					e.state.Ports[n].Reachable = false
					e.state.Ports[n].Error = message
					break
				}
			}
		}
	}
	e.mu.Unlock()
	if current {
		e.publish()
	}
}
func (e *Engine) sendNext(ctx context.Context, gen uint64) {
	e.mu.Lock()
	if !e.state.On || e.state.Generation != gen {
		e.mu.Unlock()
		return
	}
	var j Job
	var p *peer
	var conn transport.Connection
	selected := -1
	var expired []int
	for n, x := range e.state.Jobs {
		if x.Status != "queued" || x.Generation != gen {
			continue
		}
		if time.Since(x.CreatedAt) > 30*time.Minute {
			e.state.Jobs[n].Status = "expired"
			expired = append(expired, n)
			continue
		}
		candidate := e.peers[x.Host]
		if candidate == nil {
			continue
		}
		ready := candidate.conn()
		if ready == nil {
			continue
		}
		j, p, conn, selected = x, candidate, ready, n
		break
	}
	if len(expired) > 0 {
		if err := e.saveJobsLocked(); err != nil {
			for _, n := range expired {
				e.state.Jobs[n].Status = "queued"
			}
			e.state.Error = err.Error()
			e.mu.Unlock()
			return
		}
	}
	if selected < 0 {
		e.mu.Unlock()
		return
	}
	e.state.Jobs[selected].Status = "sending"
	e.mu.Unlock()
	e.publish()
	requestCtx, cancel := context.WithTimeout(ctx, 90*time.Second)
	defer cancel()
	r, err := conn.Call(requestCtx, remote.Request{Op: "exists", ID: j.ID}, nil)
	if err == nil && r.Exists {
		if r.Image == nil || r.Image.SHA256 != j.SHA256 || r.Image.Size != j.Size {
			err = errors.New("원격 이미지 확인 결과가 원본과 다릅니다")
		}
	}
	if err == nil && !r.Exists {
		var f *os.File
		f, err = os.Open(e.queuePath(j))
		if err == nil {
			r, err = conn.Call(requestCtx, remote.Request{Op: "upload", ID: j.ID, Extension: j.Extension, SHA256: j.SHA256, Size: j.Size}, f)
			f.Close()
		}
	}
	if !e.current(gen) {
		return
	}
	if err != nil {
		status := "queued"
		if r.Error != "" || os.IsNotExist(err) {
			status = "failed"
		}
		e.finish(j, status, err.Error(), "")
		e.failedPeer(j.Host, p, err)
		return
	}
	if r.Image == nil || r.Image.ID != j.ID || r.Image.SHA256 != j.SHA256 || r.Image.Size != j.Size {
		e.finish(j, "failed", "원격 저장 완료 확인이 올바르지 않습니다", "")
		return
	}
	if err = e.finish(j, "complete", "", r.Image.Path); err != nil {
		e.publish()
		return
	}
	if err = os.Remove(e.queuePath(j)); err != nil && !os.IsNotExist(err) {
		e.finish(j, "failed", "원격 전송은 완료됐지만 로컬 임시 파일을 정리하지 못했습니다", r.Image.Path)
		return
	}
	if !e.current(gen) {
		return
	}
	j.Status = "complete"
	j.RemotePath = r.Image.Path
	e.emit(Event{Kind: "upload_complete", Job: &j})
	select {
	case e.wake <- struct{}{}:
	default:
	}
}
func (e *Engine) finish(j Job, status, message, path string) error {
	e.mu.Lock()
	defer e.mu.Unlock()
	if !e.state.On || j.Generation != e.state.Generation {
		return context.Canceled
	}
	for n, x := range e.state.Jobs {
		if x.ID == j.ID {
			e.state.Jobs[n].Status = status
			e.state.Jobs[n].Error = message
			e.state.Jobs[n].RemotePath = path
			break
		}
	} // Keep five recent finished records plus all pending records.
	finished := 0
	out := []Job{}
	for n := len(e.state.Jobs) - 1; n >= 0; n-- {
		x := e.state.Jobs[n]
		if x.Status == "complete" {
			finished++
			if finished > 5 {
				continue
			}
		}
		out = append(out, x)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].CreatedAt.Before(out[j].CreatedAt) })
	e.state.Jobs = out
	if err := e.saveJobsLocked(); err != nil {
		e.state.Error = err.Error()
		for n, x := range e.state.Jobs {
			if x.ID == j.ID {
				e.state.Jobs[n].Status = "failed"
				e.state.Jobs[n].Error = err.Error()
			}
		}
		return err
	}
	return nil
}
func (e *Engine) RefreshTitle(id string) error {
	snap := e.Snapshot()
	var port model.Port
	ok := false
	for _, p := range snap.Config.Ports {
		if p.ID == id {
			port = p
			ok = true
		}
	}
	if !ok || !snap.On {
		return errors.New("업무 모드와 서버 등록을 확인해 주세요")
	}
	client := &http.Client{Timeout: 2 * time.Second, CheckRedirect: func(r *http.Request, via []*http.Request) error {
		if r.URL.Host != via[0].URL.Host {
			return http.ErrUseLastResponse
		}
		if len(via) > 3 {
			return errors.New("redirect limit")
		}
		return nil
	}}
	res, err := client.Get(port.Endpoint.LocalURL(port.LocalPort))
	if err != nil {
		return err
	}
	defer res.Body.Close()
	if !strings.Contains(strings.ToLower(res.Header.Get("Content-Type")), "text/html") {
		return errors.New("HTML 페이지 제목이 없습니다")
	}
	b, err := io.ReadAll(io.LimitReader(res.Body, 64<<10))
	if err != nil {
		return err
	}
	matches := regexp.MustCompile(`(?is)<title[^>]*>(.*?)</title>`).FindSubmatch(b)
	if len(matches) < 2 {
		return errors.New("HTML 페이지 제목이 없습니다")
	}
	title := strings.Join(strings.Fields(html.UnescapeString(string(matches[1]))), " ")
	if len([]rune(title)) > 200 {
		title = string([]rune(title)[:200])
	}
	e.mu.Lock()
	if e.state.Generation != snap.Generation {
		e.mu.Unlock()
		return errors.New("업무 상태가 변경됐습니다")
	}
	c := e.state.Config
	c.Ports = append([]model.Port{}, c.Ports...)
	for n, p := range c.Ports {
		if p.ID == id {
			c.Ports[n].Title = title
		}
	}
	err = e.store.SaveConfig(&c)
	if err == nil {
		e.state.Config = c
	}
	e.mu.Unlock()
	e.publish()
	return err
}
func (e *Engine) CopyPath(id string) (string, error) {
	snap := e.Snapshot()
	for _, j := range snap.Jobs {
		if j.ID == id && j.RemotePath != "" {
			e.mu.Lock()
			p := e.peers[j.Host]
			e.mu.Unlock()
			if p == nil {
				return "", errors.New("원격 연결을 먼저 켜 주세요")
			}
			conn := p.conn()
			if conn == nil {
				return "", errors.New("원격 연결을 먼저 켜 주세요")
			}
			ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			defer cancel()
			r, err := conn.Call(ctx, remote.Request{Op: "exists", ID: id}, nil)
			if err != nil {
				return "", err
			}
			if !r.Exists {
				return "", errors.New("원격 이미지가 정리되어 경로가 만료됐습니다")
			}
			return j.RemotePath, nil
		}
	}
	return "", errors.New("완료한 이미지 경로가 없습니다")
}

type RestoredImage struct {
	Path      string `json:"path"`
	Extension string `json:"extension"`
	Size      int64  `json:"size"`
}

func (e *Engine) RestoreOriginal(id string) (result RestoredImage, err error) {
	if !e.restoreMu.TryLock() {
		return result, errors.New("원본 이미지를 가져오는 중입니다")
	}
	defer e.restoreMu.Unlock()
	snap := e.Snapshot()
	if !snap.On {
		return result, errors.New("원격 연결을 먼저 켜 주세요")
	}
	var job Job
	for _, j := range snap.Jobs {
		if j.ID == id && j.Status == "complete" {
			job = j
			break
		}
	}
	if job.ID == "" {
		return result, errors.New("완료된 이미지를 찾을 수 없습니다")
	}
	if job.Size <= 0 || job.Size > snap.Config.Limits.ImageBytes {
		return result, errors.New("원본 이미지 크기 제한을 초과했습니다")
	}
	e.mu.Lock()
	p := e.peers[job.Host]
	e.mu.Unlock()
	if p == nil {
		return result, errors.New("원격 연결을 먼저 켜 주세요")
	}
	connection := p.conn()
	if connection == nil {
		return result, errors.New("원격 연결을 먼저 켜 주세요")
	}
	downloader, ok := connection.(interface {
		Download(context.Context, remote.Request, io.Writer) (remote.Response, error)
	})
	if !ok {
		return result, errors.New("원본 복사를 지원하는 연결이 아닙니다")
	}
	dir := filepath.Join(e.store.Root, "restores")
	if err = os.MkdirAll(dir, 0700); err != nil {
		return result, err
	}
	f, err := os.CreateTemp(dir, "original-*")
	if err != nil {
		return result, err
	}
	path := f.Name()
	keep := false
	defer func() {
		f.Close()
		if !keep {
			os.Remove(path)
		}
	}()
	hash := sha256.New()
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	response, err := downloader.Download(ctx, remote.Request{Op: "download", ID: job.ID, Size: job.Size, SHA256: job.SHA256, Extension: job.Extension}, io.MultiWriter(f, hash))
	if err != nil {
		return result, err
	}
	info, err := f.Stat()
	if err != nil {
		return result, err
	}
	if response.Image == nil || response.Image.ID != job.ID || response.Image.Extension != job.Extension || info.Size() != job.Size || fmt.Sprintf("%x", hash.Sum(nil)) != job.SHA256 {
		return result, errors.New("원본 이미지 검증에 실패했습니다")
	}
	current := e.Snapshot()
	if !current.On || current.Generation != snap.Generation {
		return result, errors.New("업무 상태가 변경됐습니다")
	}
	if err = f.Close(); err != nil {
		return result, err
	}
	keep = true
	return RestoredImage{Path: path, Extension: job.Extension, Size: job.Size}, nil
}
