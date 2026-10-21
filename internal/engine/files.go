package engine

import (
	"context"
	"crypto/sha256"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"time"

	"github.com/young-st511/worklink/internal/model"
	"github.com/young-st511/worklink/internal/remote"
	"github.com/young-st511/worklink/internal/storage"
)

type FileTransfer struct {
	model.File
	Host   string `json:"host"`
	Status string `json:"status"`
	Sent   int64  `json:"sent"`
	Error  string `json:"error,omitempty"`
}
type fileUploader interface {
	UploadFile(context.Context, remote.Request, io.Reader) (remote.Response, error)
}

func (e *Engine) loadFiles() error {
	b, err := os.ReadFile(filepath.Join(e.store.Root, "file-transfers.json"))
	if os.IsNotExist(err) {
		return nil
	}
	if err != nil {
		return err
	}
	if err = json.Unmarshal(b, &e.state.Files); err != nil {
		return err
	}
	for i := range e.state.Files {
		if e.state.Files[i].Status == "sending" || e.state.Files[i].Status == "preparing" {
			e.state.Files[i].Status = "cancelled"
			e.state.Files[i].Error = "앱이 종료되어 중단됐습니다. 파일을 다시 보내 주세요"
		}
	}
	return nil
}
func (e *Engine) fileUpdate(f FileTransfer, persist bool) error {
	e.mu.Lock()
	found := false
	for i := range e.state.Files {
		if e.state.Files[i].ID == f.ID {
			e.state.Files[i] = f
			found = true
			break
		}
	}
	if !found {
		e.state.Files = append([]FileTransfer{f}, e.state.Files...)
	}
	if len(e.state.Files) > 8 {
		e.state.Files = e.state.Files[:8]
	}
	var err error
	if persist {
		err = e.saveFilesLocked()
		if err != nil {
			e.state.Error = err.Error()
		}
	}
	e.mu.Unlock()
	e.publish()
	return err
}
func (e *Engine) saveFilesLocked() error {
	return storage.AtomicJSON(filepath.Join(e.store.Root, "file-transfers.json"), e.state.Files)
}

// CancelFiles cancels only the explicit file batch, leaving tunnels and captures running.
func (e *Engine) CancelFiles() {
	e.mu.Lock()
	cancel := e.fileCancel
	e.mu.Unlock()
	if cancel != nil {
		cancel()
	}
}
func (e *Engine) SendFiles(paths []string) (completed []model.File, err error) {
	if !e.fileBatchMu.TryLock() {
		return nil, errors.New("파일 전송 중입니다. 완료 후 다시 보내 주세요")
	}
	defer e.fileBatchMu.Unlock()
	if len(paths) < 1 || len(paths) > model.MaxFileBatch {
		return nil, errors.New("한 번에 일반 파일 1~8개를 선택해 주세요")
	}
	// Validate the whole selection before sending its first item.
	for _, path := range paths {
		if err = validateSource(path); err != nil {
			return nil, err
		}
	}
	e.mu.Lock()
	host := e.state.Config.ImageHost
	gen := e.state.Generation
	p := e.peers[host]
	session := e.session
	ready := e.state.On && session != nil
	connected := false
	for _, h := range e.state.Hosts {
		if h.Host == host && h.Status == "connected" {
			connected = true
		}
	}
	e.mu.Unlock()
	if !ready || !connected || p == nil {
		return nil, errors.New("업무 ON 후 전송 대상의 SSH 연결을 기다려 주세요")
	}
	conn := p.conn()
	uploader, ok := conn.(fileUploader)
	if !ok {
		return nil, errors.New("원격 파일 전송을 지원하지 않는 연결입니다")
	}
	ctx, cancel := context.WithTimeout(session, 10*time.Minute)
	defer cancel()
	e.mu.Lock()
	e.fileCancel = cancel
	e.mu.Unlock()
	defer func() { e.mu.Lock(); e.fileCancel = nil; e.mu.Unlock() }()
	completed = []model.File{}
	for _, path := range paths {
		if err = ctx.Err(); err != nil {
			return completed, err
		}
		f := FileTransfer{File: model.File{ID: model.NewID(), Name: filepath.Base(path), CreatedAt: time.Now().UTC()}, Host: host, Status: "preparing"}
		if err = e.fileUpdate(f, true); err != nil {
			f.Status = "failed"
			f.Error = "전송 기록 저장 실패: " + err.Error()
			e.fileUpdate(f, false)
			return completed, err
		}
		transfer, problem := e.sendFile(ctx, uploader, path, f, gen)
		if problem != nil {
			if transfer.Status == "complete" {
				transfer.Error = "원격 전송은 완료했으나 기록 저장에 실패했습니다: " + problem.Error()
				e.fileUpdate(transfer, false)
				return append(completed, transfer.File), errors.New(transfer.Error)
			}
			f = transfer
			f.Status = "failed"
			if ctx.Err() != nil {
				f.Status = "cancelled"
			}
			f.Error = problem.Error()
			e.fileUpdate(f, true)
			return completed, fmt.Errorf("%s: %w", f.Name, problem)
		}
		completed = append(completed, transfer.File)
	}
	return completed, nil
}
func validateSource(path string) error {
	if !filepath.IsAbs(path) || strings.ContainsAny(path, "\x00\r\n") {
		return errors.New("파일 경로를 확인해 주세요")
	}
	if err := model.ValidateFileName(filepath.Base(path)); err != nil {
		return err
	}
	st, err := os.Lstat(path)
	if err != nil {
		return err
	}
	if !st.Mode().IsRegular() {
		return errors.New("일반 파일만 보낼 수 있습니다. 폴더·심볼릭 링크는 제외해 주세요")
	}
	if st.Size() > model.MaxFileBytes {
		return errors.New("파일당 256 MiB까지 보낼 수 있습니다")
	}
	return nil
}

type fileReader struct {
	ctx      context.Context
	r        io.Reader
	progress func(int)
}

func (r fileReader) Read(b []byte) (int, error) {
	if err := r.ctx.Err(); err != nil {
		return 0, err
	}
	n, err := r.r.Read(b)
	if n > 0 && r.progress != nil {
		r.progress(n)
	}
	return n, err
}
func (e *Engine) sendFile(ctx context.Context, u fileUploader, path string, f FileTransfer, gen uint64) (FileTransfer, error) {
	src, err := os.OpenFile(path, os.O_RDONLY|syscall.O_NOFOLLOW|syscall.O_NONBLOCK, 0)
	if err != nil {
		return f, err
	}
	defer src.Close()
	st, err := src.Stat()
	if err != nil {
		return f, err
	}
	if !st.Mode().IsRegular() || st.Size() > model.MaxFileBytes {
		return f, errors.New("일반 파일과 크기를 다시 확인해 주세요")
	}
	f.Size = st.Size()
	h := sha256.New()
	n, err := io.Copy(h, fileReader{ctx: ctx, r: io.LimitReader(src, model.MaxFileBytes+1)})
	if err != nil {
		return f, err
	}
	if n != f.Size {
		return f, errors.New("준비 중 파일이 변경됐습니다")
	}
	f.SHA256 = fmt.Sprintf("%x", h.Sum(nil))
	if _, err = src.Seek(0, io.SeekStart); err != nil {
		return f, err
	}
	f.Status = "sending"
	if err = e.fileUpdate(f, true); err != nil {
		return f, err
	}
	last := time.Now()
	r := fileReader{ctx: ctx, r: src, progress: func(n int) {
		f.Sent += int64(n)
		if time.Since(last) >= 500*time.Millisecond {
			e.fileUpdate(f, false)
			last = time.Now()
		}
	}}
	res, err := u.UploadFile(ctx, remote.Request{ID: f.ID, FileName: f.Name, Size: f.Size, SHA256: f.SHA256}, r)
	if err != nil {
		return f, err
	}
	if ctx.Err() != nil {
		return f, ctx.Err()
	}
	if !e.current(gen) {
		return f, errors.New("업무 상태가 변경되어 전송을 중단했습니다")
	}
	if res.File == nil || res.File.ID != f.ID || res.File.Name != f.Name || res.File.Size != f.Size || res.File.SHA256 != f.SHA256 || !filepath.IsAbs(res.File.Path) || filepath.Base(res.File.Path) != f.Name || strings.ContainsAny(res.File.Path, "\r\n") {
		return f, errors.New("원격 파일 완료 응답이 원본과 일치하지 않습니다")
	}
	f.File = *res.File
	f.Status = "complete"
	f.Sent = f.Size
	return f, e.fileUpdate(f, true)
}
func (e *Engine) CopyFilePath(id string) (string, error) {
	e.mu.Lock()
	var f FileTransfer
	for _, v := range e.state.Files {
		if v.ID == id {
			f = v
		}
	}
	p := e.peers[f.Host]
	on := e.state.On
	gen := e.state.Generation
	e.mu.Unlock()
	if !on || f.Status != "complete" || p == nil {
		return "", errors.New("업무 ON 후 파일의 SSH 대상에 연결해 주세요")
	}
	conn := p.conn()
	if conn == nil {
		return "", errors.New("원격 연결이 끊겼습니다")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	res, err := conn.Call(ctx, remote.Request{Op: "file_exists", ID: id}, nil)
	if err != nil {
		return "", err
	}
	if !res.Exists {
		return "", errors.New("원격 파일이 정리되어 경로가 만료됐습니다")
	}
	if !e.current(gen) || res.File == nil || res.File.Path != f.Path || res.File.SHA256 != f.SHA256 {
		return "", errors.New("원격 파일 또는 업무 상태가 바뀌었습니다")
	}
	return f.Path, nil
}
