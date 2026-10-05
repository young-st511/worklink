package transport

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/young-st511/worklink/internal/model"
	"github.com/young-st511/worklink/internal/remote"
	"github.com/young-st511/worklink/internal/wire"
)

type Connection interface {
	Call(context.Context, remote.Request, io.Reader) (remote.Response, error)
	Forward(context.Context, model.Port, bool) error
	Close()
}
type limitedLog struct {
	mu sync.Mutex
	b  []byte
}

func (l *limitedLog) Write(b []byte) (int, error) {
	l.mu.Lock()
	defer l.mu.Unlock()
	l.b = append(l.b, b...)
	if len(l.b) > 4096 {
		l.b = l.b[len(l.b)-4096:]
	}
	return len(b), nil
}
func (l *limitedLog) String() string {
	l.mu.Lock()
	defer l.mu.Unlock()
	return strings.TrimSpace(string(l.b))
}

type SSH struct {
	host                   model.Host
	dir, socket            string
	master, helper         *exec.Cmd
	masterDone, helperDone chan struct{}
	in                     io.WriteCloser
	out                    io.ReadCloser
	log                    limitedLog
	rpc                    chan struct{}
	once                   sync.Once
}

func options() []string {
	return []string{"-o", "BatchMode=yes", "-o", "RemoteCommand=none", "-o", "RequestTTY=no", "-o", "Compression=no", "-o", "ConnectTimeout=8", "-o", "ServerAliveInterval=30", "-o", "ServerAliveCountMax=2", "-o", "ExitOnForwardFailure=yes"}
}
func Connect(ctx context.Context, h model.Host) (Connection, error) {
	if e := model.ValidateHost(h); e != nil {
		return nil, e
	}
	dir, e := os.MkdirTemp("/tmp", "wl-")
	if e != nil {
		return nil, e
	}
	s := &SSH{rpc: make(chan struct{}, 1), host: h, dir: dir, socket: filepath.Join(dir, "ctl"), masterDone: make(chan struct{}), helperDone: make(chan struct{})}
	args := append(options(), "-o", "ClearAllForwardings=yes", "-M", "-N", "-S", s.socket, "-o", "ControlMaster=yes", "-o", "ControlPersist=no", h.Name)
	s.master = exec.CommandContext(ctx, "/usr/bin/ssh", args...)
	s.master.Stderr = &s.log
	if e = s.master.Start(); e != nil {
		os.RemoveAll(dir)
		return nil, e
	}
	go func() { s.master.Wait(); close(s.masterDone) }()
	deadline := time.NewTimer(10 * time.Second)
	defer deadline.Stop()
	ticker := time.NewTicker(50 * time.Millisecond)
	defer ticker.Stop()
	ready := false
	for !ready {
		select {
		case <-ctx.Done():
			s.Close()
			return nil, ctx.Err()
		case <-s.masterDone:
			s.Close()
			return nil, fmt.Errorf("SSH 연결 실패: %s", s.log.String())
		case <-deadline.C:
			s.Close()
			return nil, errors.New("SSH 연결 시간 초과")
		case <-ticker.C:
			_, e = os.Stat(s.socket)
			ready = e == nil
		}
	}
	args = append(options(), "-S", s.socket, "-o", "ControlMaster=no", "-o", "ClearAllForwardings=yes", "-T", h.Name, "exec "+h.Helper+" remote --stdio")
	s.helper = exec.CommandContext(ctx, "/usr/bin/ssh", args...)
	s.helper.Stderr = &s.log
	s.in, e = s.helper.StdinPipe()
	if e == nil {
		s.out, e = s.helper.StdoutPipe()
	}
	if e != nil {
		s.Close()
		return nil, e
	}
	if e = s.helper.Start(); e != nil {
		s.Close()
		return nil, e
	}
	go func() { s.helper.Wait(); close(s.helperDone) }()
	hello, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	if _, e = s.Call(hello, remote.Request{Op: "hello"}, nil); e != nil {
		s.Close()
		return nil, fmt.Errorf("원격 헬퍼 확인 실패: %w (%s)", e, s.log.String())
	}
	return s, nil
}
func (s *SSH) Call(ctx context.Context, q remote.Request, payload io.Reader) (remote.Response, error) {
	select {
	case s.rpc <- struct{}{}:
	case <-ctx.Done():
		return remote.Response{}, ctx.Err()
	}
	defer func() { <-s.rpc }()
	q.Version = wire.Version
	type result struct {
		r remote.Response
		e error
	}
	done := make(chan result, 1)
	go func() {
		e := wire.Write(s.in, q)
		if e == nil && payload != nil {
			_, e = io.CopyN(s.in, payload, q.Size)
		}
		var r remote.Response
		if e == nil {
			e = wire.Read(s.out, &r)
		}
		if e == nil && r.Version != wire.Version {
			e = errors.New("원격 프로토콜 버전이 다릅니다")
		}
		if e == nil && r.Error != "" {
			e = errors.New(r.Error)
		}
		done <- result{r, e}
	}()
	select {
	case <-ctx.Done():
		s.Close()
		return remote.Response{}, ctx.Err()
	case r := <-done:
		return r.r, r.e
	}
}
func (s *SSH) Forward(ctx context.Context, p model.Port, remove bool) error {
	verb := "forward"
	if remove {
		verb = "cancel"
	}
	remoteHost := p.Endpoint.RemoteHost
	if strings.Contains(remoteHost, ":") {
		remoteHost = "[" + remoteHost + "]"
	}
	target := remoteHost + ":" + strconv.Itoa(p.Endpoint.RemotePort)
	a := "127.0.0.1:" + strconv.Itoa(p.LocalPort) + ":" + target
	b := "[::1]:" + strconv.Itoa(p.LocalPort) + ":" + target
	args := append(options(), "-F", "/dev/null", "-S", s.socket, "-O", verb, "-L", a, "-L", b, s.host.Name)
	cmd := exec.CommandContext(ctx, "/usr/bin/ssh", args...)
	out, e := cmd.CombinedOutput()
	if e != nil && !remove {
		rollback := exec.CommandContext(ctx, "/usr/bin/ssh", append(options(), "-F", "/dev/null", "-S", s.socket, "-O", "cancel", "-L", a, "-L", b, s.host.Name)...)
		rollback.Run()
	}
	if e != nil {
		return fmt.Errorf("로컬 포트 %d 연결 실패 (이미 사용 중인지 확인): %s", p.LocalPort, bytes.TrimSpace(out))
	}
	return nil
}
func (s *SSH) Close() {
	s.once.Do(func() {
		if s.in != nil {
			s.in.Close()
		}
		if s.out != nil {
			s.out.Close()
		}
		if s.helper != nil && s.helper.Process != nil {
			s.helper.Process.Kill()
		}
		ctx, cancel := context.WithTimeout(context.Background(), time.Second)
		defer cancel()
		exec.CommandContext(ctx, "/usr/bin/ssh", "-F", "/dev/null", "-S", s.socket, "-O", "exit", s.host.Name).Run()
		if s.master != nil && s.master.Process != nil {
			s.master.Process.Kill()
		}
		os.RemoveAll(s.dir)
	})
}
func (s *SSH) Address(port int) string { return net.JoinHostPort("localhost", strconv.Itoa(port)) }
