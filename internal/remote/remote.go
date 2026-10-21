package remote

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net"
	"os"
	"sync"
	"time"

	"github.com/young-st511/worklink/internal/address"
	"github.com/young-st511/worklink/internal/model"
	"github.com/young-st511/worklink/internal/storage"
	"github.com/young-st511/worklink/internal/wire"
)

type Request struct {
	Limits    *model.Limits               `json:"limits,omitempty"`
	Version   int                         `json:"version"`
	Op        string                      `json:"op"`
	ID        string                      `json:"id,omitempty"`
	FileName  string                      `json:"file_name,omitempty"`
	Extension string                      `json:"extension,omitempty"`
	SHA256    string                      `json:"sha256,omitempty"`
	Size      int64                       `json:"size,omitempty"`
	Endpoints map[string]address.Endpoint `json:"endpoints,omitempty"`
	Dry       bool                        `json:"dry,omitempty"`
	Pinned    bool                        `json:"pinned,omitempty"`
}
type Response struct {
	Version     int               `json:"version"`
	Error       string            `json:"error,omitempty"`
	File        *model.File       `json:"file,omitempty"`
	Image       *model.Image      `json:"image,omitempty"`
	Images      []model.Image     `json:"images,omitempty"`
	Checks      map[string]bool   `json:"checks,omitempty"`
	Targets     map[string]string `json:"targets,omitempty"`
	CheckErrors map[string]string `json:"check_errors,omitempty"`
	Removed     []string          `json:"removed,omitempty"`
	Exists      bool              `json:"exists,omitempty"`
	Root        string            `json:"root,omitempty"`
}

func Serve(r io.Reader, w io.Writer, s *storage.Store) error {
	if err := s.CleanupIfDue(time.Now()); err != nil {
		return err
	}
	// The lease also ends an orphaned helper while no requests arrive.
	var inputMu sync.Mutex
	lease := time.AfterFunc(2*time.Minute, func() {
		inputMu.Lock()
		if c, ok := r.(io.Closer); ok {
			c.Close()
		}
		inputMu.Unlock()
	})
	defer lease.Stop()
	for {
		var q Request
		if e := wire.Read(r, &q); e != nil {
			if errors.Is(e, io.EOF) {
				return nil
			}
			return e
		}
		lease.Reset(2 * time.Minute)
		res := Response{Version: wire.Version}
		var err error
		var download *os.File
		if q.Version != wire.Version {
			res.Error = "프로토콜 버전이 다릅니다"
			wire.Write(w, res)
			return errors.New(res.Error)
		}
		switch q.Op {
		case "limits":
			if q.Limits == nil {
				err = errors.New("용량 설정이 없습니다")
				break
			}
			c, e := s.LoadConfig()
			if e != nil {
				err = e
				break
			}
			c.Limits = *q.Limits
			if err = c.Validate(); err == nil {
				err = s.SaveConfig(&c)
				if err == nil {
					s.Limits = c.Limits
				}
			}
		case "hello":
			res.Root = s.Root
		case "upload_file":
			lease.Reset(11 * time.Minute)
			var f model.File
			f, err = s.ReceiveFile(q.ID, q.FileName, q.SHA256, q.Size, r)
			if err == nil {
				res.File = &f
			}
		case "file_exists":
			var f model.File
			f, err = s.GetFile(q.ID)
			if errors.Is(err, os.ErrNotExist) {
				err = nil
			} else if err == nil {
				res.Exists = true
				res.File = &f
			}
		case "upload":
			var i model.Image
			i, err = s.Receive(q.ID, q.Extension, q.SHA256, q.Size, r)
			if err == nil {
				res.Image = &i
			}
		case "exists":
			var i model.Image
			i, err = s.Verify(q.ID)
			if errors.Is(err, os.ErrNotExist) {
				err = nil
			} else if err == nil {
				res.Exists = true
				res.Image = &i
			}
		case "download":
			var image model.Image
			image, err = s.Verify(q.ID)
			if errors.Is(err, os.ErrNotExist) {
				err = errors.New("원격 이미지가 정리되어 원본이 만료됐습니다")
			}
			if err == nil {
				download, err = os.Open(image.Path)
				if err == nil {
					res.Image = &image
				}
			}
		case "list":
			res.Images, err = s.List()
			if len(res.Images) > 32 {
				res.Images = res.Images[:32]
			}
		case "pin":
			err = s.Pin(q.ID, q.Pinned)
		case "cleanup":
			res.Removed, err = s.Cleanup(time.Now(), q.Dry)
			if len(res.Removed) > 128 {
				res.Removed = res.Removed[:128]
			}
		case "check":
			if len(q.Endpoints) > 16 {
				err = errors.New("등록 서버 수 제한을 초과했습니다")
				break
			}
			res.Checks = make(map[string]bool)
			res.Targets = make(map[string]string)
			res.CheckErrors = make(map[string]string)
			var mu sync.Mutex
			var wg sync.WaitGroup
			sem := make(chan struct{}, 2)
			for id, ep := range q.Endpoints {
				parsed := address.Parse(ep.Scheme + "://" + ep.Address())
				if parsed.Error != "" || parsed.NeedsPort {
					err = errors.New("등록 주소를 확인해 주세요")
					break
				}
				wg.Add(1)
				go func(id string, ep address.Endpoint) {
					defer wg.Done()
					sem <- struct{}{}
					defer func() { <-sem }()
					target := ""
					for _, host := range ep.Candidates() {
						ctx, cancel := context.WithTimeout(context.Background(), 400*time.Millisecond)
						c, problem := (&net.Dialer{}).DialContext(ctx, "tcp", net.JoinHostPort(host, fmt.Sprint(ep.RemotePort)))
						cancel()
						if problem == nil {
							c.Close()
							target = host
							break
						}
					}
					mu.Lock()
					res.Checks[id] = target != ""
					if target != "" {
						res.Targets[id] = target
					} else {
						res.CheckErrors[id] = "등록한 원격 포트의 loopback 주소에 연결할 수 없습니다. 서버 실행 상태를 확인해 주세요."
					}
					mu.Unlock()
				}(id, ep)
			}
			wg.Wait()
		default:
			err = errors.New("지원하지 않는 원격 명령입니다")
		}
		if err != nil {
			res.Error = err.Error()
		}
		if e := wire.Write(w, res); e != nil {
			if download != nil {
				download.Close()
			}
			return e
		}
		if download != nil {
			_, transferErr := io.CopyN(w, download, res.Image.Size)
			download.Close()
			if transferErr != nil {
				return transferErr
			}
		}
		// A rejected upload may leave unread payload. Never reuse its stream.
		if (q.Op == "upload" || q.Op == "upload_file") && err != nil {
			return err
		}
	}
}
