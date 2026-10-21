package storage

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"syscall"
	"time"

	"github.com/young-st511/worklink/internal/model"
)

type Store struct {
	Root   string
	Limits model.Limits
}

func DefaultRoot() string {
	if s := os.Getenv("WORKLINK_DATA_DIR"); s != "" {
		return s
	}
	h, _ := os.UserHomeDir()
	return filepath.Join(h, ".local", "share", "worklink")
}
func Open(root string, limits model.Limits) (*Store, error) {
	for _, d := range []string{root, filepath.Join(root, "inbox"), filepath.Join(root, "records"), filepath.Join(root, "queue"), filepath.Join(root, "staging"), filepath.Join(root, "file-inbox"), filepath.Join(root, "file-records")} {
		if e := os.MkdirAll(d, 0700); e != nil {
			return nil, e
		}
	}
	return &Store{root, limits}, nil
}
func AtomicJSON(path string, v any) error {
	b, e := json.MarshalIndent(v, "", "  ")
	if e != nil {
		return e
	}
	return AtomicBytes(path, b)
}
func AtomicBytes(path string, b []byte) error {
	f, e := os.CreateTemp(filepath.Dir(path), ".tmp-")
	if e != nil {
		return e
	}
	tmp := f.Name()
	defer os.Remove(tmp)
	if e = f.Chmod(0600); e == nil {
		_, e = f.Write(b)
	}
	if e == nil {
		e = f.Sync()
	}
	ce := f.Close()
	if e != nil {
		return e
	}
	if ce != nil {
		return ce
	}
	return os.Rename(tmp, path)
}
func (s *Store) LoadConfig() (model.Config, error) {
	c := model.DefaultConfig()
	b, e := os.ReadFile(filepath.Join(s.Root, "config.json"))
	if errors.Is(e, os.ErrNotExist) {
		return c, nil
	}
	if e != nil {
		return c, e
	}
	if e = json.Unmarshal(b, &c); e != nil {
		return c, e
	}
	return c, c.Validate()
}
func (s *Store) SaveConfig(c *model.Config) error {
	unlock, e := s.lock()
	if e != nil {
		return e
	}
	defer unlock()
	current, e := s.LoadConfig()
	if e != nil {
		return e
	}
	if current.Revision != c.Revision {
		return errors.New("설정이 다른 프로세스에서 변경됐습니다. 다시 불러온 후 저장해 주세요")
	}
	if e := c.Validate(); e != nil {
		return e
	}
	next := *c
	next.Revision++
	if e = AtomicJSON(filepath.Join(s.Root, "config.json"), next); e != nil {
		return e
	}
	*c = next
	return nil
}
func (s *Store) lock() (func(), error) {
	f, e := os.OpenFile(filepath.Join(s.Root, ".lock"), os.O_CREATE|os.O_RDWR, 0600)
	if e != nil {
		return nil, e
	}
	if e = syscall.Flock(int(f.Fd()), syscall.LOCK_EX); e != nil {
		f.Close()
		return nil, e
	}
	return func() { syscall.Flock(int(f.Fd()), syscall.LOCK_UN); f.Close() }, nil
}
func (s *Store) record(id string) string { return filepath.Join(s.Root, "records", id+".json") }
func (s *Store) Get(id string) (model.Image, error) {
	if !model.ValidID(id) {
		return model.Image{}, errors.New("invalid capture ID")
	}
	var i model.Image
	b, e := os.ReadFile(s.record(id))
	if e != nil {
		return i, e
	}
	if e = json.Unmarshal(b, &i); e != nil {
		return i, e
	}
	if i.ID != id || i.Status != "complete" || !model.ValidImageName(i) || filepath.Dir(i.Path) != filepath.Join(s.Root, "inbox") {
		return i, errors.New("invalid capture record")
	}
	st, e := os.Lstat(i.Path)
	if e != nil {
		return i, e
	}
	if !st.Mode().IsRegular() || st.Size() != i.Size {
		return i, errors.New("invalid capture file")
	}
	return i, nil
}
func (s *Store) List() ([]model.Image, error) {
	entries, e := os.ReadDir(filepath.Join(s.Root, "records"))
	if e != nil {
		return nil, e
	}
	out := []model.Image{}
	for _, x := range entries {
		if x.IsDir() || filepath.Ext(x.Name()) != ".json" {
			continue
		}
		id := x.Name()[:len(x.Name())-5]
		if i, e := s.Get(id); e == nil {
			out = append(out, i)
		}
	}
	sort.Slice(out, func(a, b int) bool { return out[a].CreatedAt.After(out[b].CreatedAt) })
	return out, nil
}
func (s *Store) Verify(id string) (model.Image, error) {
	i, e := s.Get(id)
	if e != nil {
		return i, e
	}
	_, h, e := DigestFile(i.Path)
	if e != nil {
		return i, e
	}
	if h != i.SHA256 {
		return i, errors.New("저장된 이미지가 원본과 달라졌습니다")
	}
	return i, nil
}
func (s *Store) Receive(id, ext, hash string, size int64, r io.Reader) (model.Image, error) {
	if !model.ValidID(id) || !model.ValidExtension(ext) || size < 1 || size > s.Limits.ImageBytes || len(hash) != 64 {
		return model.Image{}, errors.New("invalid image metadata or size limit exceeded")
	}
	if _, e := hex.DecodeString(hash); e != nil {
		return model.Image{}, e
	}
	unlock, e := s.lock()
	if e != nil {
		return model.Image{}, e
	}
	defer unlock()
	old, exists := s.Verify(id)
	if exists == nil {
		h := sha256.New()
		if _, e = io.CopyN(h, r, size); e != nil {
			return model.Image{}, e
		}
		if old.SHA256 != hash || old.Size != size || old.Extension != ext || hex.EncodeToString(h.Sum(nil)) != hash {
			return model.Image{}, errors.New("capture ID conflicts with different content")
		}
		return old, nil
	}
	if !errors.Is(exists, os.ErrNotExist) {
		return model.Image{}, exists
	}
	total, e := s.managedBytes()
	if e != nil {
		return model.Image{}, e
	}
	if total+size > s.Limits.InboxBytes {
		return model.Image{}, errors.New("원격 보관 용량이 가득 찼습니다. 정리 또는 용량 설정을 확인해 주세요")
	}
	f, e := os.CreateTemp(filepath.Join(s.Root, "inbox"), ".upload-")
	if e != nil {
		return model.Image{}, e
	}
	defer os.Remove(f.Name())
	h := sha256.New()
	_, e = io.CopyN(io.MultiWriter(f, h), r, size)
	if e == nil && hex.EncodeToString(h.Sum(nil)) != hash {
		e = errors.New("원본 이미지 해시가 일치하지 않습니다")
	}
	if e == nil {
		e = f.Sync()
	}
	ce := f.Close()
	if e != nil {
		return model.Image{}, e
	}
	if ce != nil {
		return model.Image{}, ce
	}
	now := time.Now().UTC()
	i := model.Image{ID: id, CreatedAt: now, Extension: ext, Size: size, SHA256: hash, Status: "complete"}
	i.Path = filepath.Join(s.Root, "inbox", model.CaptureName(now, id, ext))
	// Recover a fully renamed payload whose record was not yet committed at crash time.
	orphans, _ := filepath.Glob(filepath.Join(s.Root, "inbox", "worklink-capture-*-"+id+"."+ext))
	if len(orphans) > 1 {
		return i, errors.New("동일 ID의 저장 파일이 여러 개 있습니다")
	}
	if len(orphans) == 1 {
		p := orphans[0]
		st, err := os.Lstat(p)
		if err != nil || !st.Mode().IsRegular() {
			return i, errors.New("원격 저장 파일을 확인해 주세요")
		}
		n, h, err := DigestFile(p)
		if err != nil || n != size || h != hash {
			return i, errors.New("저장된 이미지가 원본과 달라졌습니다")
		}
		stamp := filepath.Base(p)[len("worklink-capture-") : len("worklink-capture-")+20]
		created, err := time.Parse("20060102T150405.000Z", stamp)
		if err != nil {
			return i, err
		}
		i.CreatedAt = created
		i.Path = p
		return i, AtomicJSON(s.record(id), i)
	}
	if e = os.Rename(f.Name(), i.Path); e != nil {
		return i, e
	}
	if e = AtomicJSON(s.record(id), i); e != nil {
		os.Remove(i.Path)
		return i, e
	}
	return i, nil
}
func (s *Store) Pin(id string, pin bool) error {
	unlock, e := s.lock()
	if e != nil {
		return e
	}
	defer unlock()
	i, e := s.Get(id)
	if e != nil {
		return e
	}
	i.Pinned = pin
	return AtomicJSON(s.record(id), i)
}
func (s *Store) Cleanup(now time.Time, dry bool) ([]string, error) {
	unlock, e := s.lock()
	if e != nil {
		return nil, e
	}
	defer unlock()
	all, e := s.List()
	if e != nil {
		return nil, e
	}
	out := []string{}
	for _, i := range all {
		if i.Pinned || now.Sub(i.CreatedAt) < 24*time.Hour {
			continue
		}
		if !dry {
			if e = os.Remove(i.Path); e != nil && !errors.Is(e, os.ErrNotExist) {
				return out, e
			}
			if e = os.Remove(s.record(i.ID)); e != nil {
				return out, e
			}
		}
		out = append(out, i.Path)
	}
	files, err := s.cleanupFiles(now, dry)
	out = append(out, files...)
	if err != nil {
		return out, err
	}
	if !dry {
		e = AtomicJSON(filepath.Join(s.Root, "cleanup.json"), map[string]any{"last_success": now.UTC()})
	}
	return out, e
}
func (s *Store) CleanupIfDue(now time.Time) error {
	var record struct {
		LastSuccess time.Time `json:"last_success"`
	}
	b, e := os.ReadFile(filepath.Join(s.Root, "cleanup.json"))
	if e != nil && !os.IsNotExist(e) {
		return e
	}
	if e == nil {
		if e = json.Unmarshal(b, &record); e != nil {
			return e
		}
		if now.Sub(record.LastSuccess) < 24*time.Hour {
			return nil
		}
	}
	_, e = s.Cleanup(now, false)
	return e
}
func DigestFile(path string) (int64, string, error) {
	f, e := os.Open(path)
	if e != nil {
		return 0, "", e
	}
	defer f.Close()
	h := sha256.New()
	n, e := io.Copy(h, f)
	return n, fmt.Sprintf("%x", h.Sum(nil)), e
}
