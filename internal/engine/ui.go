package engine

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"os"
	"path/filepath"
	"sync"
	"syscall"
	"time"

	"github.com/young-st511/worklink/internal/address"
	"github.com/young-st511/worklink/internal/install"
	"github.com/young-st511/worklink/internal/model"
)

type Command struct {
	ID             string       `json:"id"`
	Method         string       `json:"method"`
	Days           int          `json:"days"`
	On             bool         `json:"on"`
	Config         model.Config `json:"config"`
	Input          string       `json:"input"`
	Paths          []string     `json:"paths"`
	Path           string       `json:"path"`
	Extension      string       `json:"extension"`
	ClipboardCount int          `json:"clipboard_count"`
	JobID          string       `json:"job_id"`
	PortID         string       `json:"port_id"`
}

// The output lock keeps reply/completion events intact and serializes the state cache.
func newEventEmitter(w io.Writer) func(Event) {
	var mu sync.Mutex
	var previousState []byte
	return func(event Event) {
		mu.Lock()
		defer mu.Unlock()
		data, err := json.Marshal(event)
		if err != nil {
			return
		}
		data = append(data, '\n')
		if event.Kind == "state" && bytes.Equal(data, previousState) {
			return
		}
		n, err := w.Write(data)
		if err == nil && n == len(data) && event.Kind == "state" {
			previousState = data
		}
	}
}

func ServeUI(root string, r io.Reader, w io.Writer) error {
	if err := os.MkdirAll(root, 0700); err != nil {
		return err
	}
	lock, err := os.OpenFile(filepath.Join(root, "engine.lock"), os.O_CREATE|os.O_RDWR, 0600)
	if err != nil {
		return err
	}
	defer lock.Close()
	if err = syscall.Flock(int(lock.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		return errors.New("같은 저장 공간을 사용하는 Worklink가 이미 실행 중입니다")
	}
	defer syscall.Flock(int(lock.Fd()), syscall.LOCK_UN)
	// Download scratch files are short lived; reclaim those left by an app crash.
	if err = os.RemoveAll(filepath.Join(root, "restores")); err != nil {
		return err
	}
	emit := newEventEmitter(w)
	e, err := New(root, nil, emit)
	if err != nil {
		return err
	}
	defer e.SetOn(false)
	e.publish()
	scan := bufio.NewScanner(r)
	scan.Buffer(make([]byte, 4096), 128<<10)
	handle := func(c Command) {
		event := Event{Kind: "reply", ID: c.ID}
		var problem error
		switch c.Method {
		case "state":
			event.Result = e.Snapshot()
		case "toggle":
			e.SetOn(c.On)
		case "save_config":
			var removed *model.Port
			removed, problem = e.saveConfig(c.Config)
			if removed != nil {
				event.Result = map[string]any{"removed_port": removed}
			}
		case "set_port_cleanup":
			problem = e.SetPortCleanup(c.On, c.Days)
		case "undo_port_cleanup":
			problem = e.UndoPortCleanup()
		case "pin_port":
			problem = e.SetPortPinned(c.PortID, c.On)
		case "parse":
			event.Result = address.Parse(c.Input)
		case "send_files":
			event.Result, problem = e.SendFiles(c.Paths)
		case "cancel_files":
			e.CancelFiles()
		case "copy_file_path":
			event.Result, problem = e.CopyFilePath(c.JobID)
		case "upload":
			var j Job
			j, problem = e.Enqueue(c.Path, c.Extension, c.ClipboardCount)
			if problem == nil {
				event.Job = &j
			}
		case "retry":
			problem = e.Retry(c.JobID)
		case "copy_path":
			event.Result, problem = e.CopyPath(c.JobID)
		case "restore_original":
			event.Result, problem = e.RestoreOriginal(c.JobID)
		case "title":
			problem = e.RefreshTitle(c.PortID)
		case "clear_pending":
			problem = e.ClearPending()
		case "install_remote":
			h, ok := e.Snapshot().Config.Host(c.Input)
			if !ok {
				problem = errors.New("SSH 대상을 등록해 주세요")
				break
			}
			ctx, cancel := context.WithTimeout(context.Background(), 90*time.Second)
			problem = install.Remote(ctx, h, c.Path)
			cancel()
		default:
			problem = errors.New("지원하지 않는 앱 명령입니다")
		}
		if problem != nil {
			event.Error = problem.Error()
		}
		emit(event)
		e.publish()
	}
	for scan.Scan() {
		var c Command
		if err = json.Unmarshal(scan.Bytes(), &c); err != nil {
			emit(Event{Kind: "reply", Error: err.Error()})
			continue
		}
		if c.Method == "send_files" || c.Method == "copy_file_path" || c.Method == "restore_original" || c.Method == "copy_path" || c.Method == "title" || c.Method == "install_remote" {
			go handle(c)
		} else {
			handle(c)
		}
	}
	return scan.Err()
}
func (e *Engine) ClearPending() error {
	e.mu.Lock()
	defer e.mu.Unlock()
	if e.state.On {
		return errors.New("업무 모드를 끈 뒤 대기 파일을 정리해 주세요")
	}
	out := []Job{}
	for _, j := range e.state.Jobs {
		if j.Status == "complete" {
			out = append(out, j)
			continue
		}
		if err := os.Remove(e.queuePath(j)); err != nil && !os.IsNotExist(err) {
			return err
		}
	}
	e.state.Jobs = out
	return e.saveJobsLocked()
}
