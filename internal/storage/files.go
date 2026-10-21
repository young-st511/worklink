package storage

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/young-st511/worklink/internal/model"
)

func (s *Store) fileRecord(id string) string {
	return filepath.Join(s.Root, "file-records", id+".json")
}
func (s *Store) GetFile(id string) (f model.File, err error) {
	if !model.ValidID(id) {
		return f, errors.New("invalid file ID")
	}
	b, err := os.ReadFile(s.fileRecord(id))
	if err != nil {
		return f, err
	}
	if err = json.Unmarshal(b, &f); err != nil {
		return f, err
	}
	dir := filepath.Join(s.Root, "file-inbox", id)
	if f.ID != id || model.ValidateFileName(f.Name) != nil || f.Path != filepath.Join(dir, f.Name) || f.Size < 0 || f.Size > model.MaxFileBytes || f.CreatedAt.IsZero() {
		return f, errors.New("invalid file record")
	}
	st, err := os.Lstat(dir)
	if err != nil {
		return f, err
	}
	if !st.IsDir() || st.Mode()&os.ModeSymlink != 0 {
		return f, errors.New("invalid file directory")
	}
	st, err = os.Lstat(f.Path)
	if err != nil {
		return f, err
	}
	if !st.Mode().IsRegular() || st.Size() != f.Size {
		return f, errors.New("invalid managed file")
	}
	return f, nil
}
func (s *Store) ListFiles() ([]model.File, error) {
	entries, err := os.ReadDir(filepath.Join(s.Root, "file-records"))
	if err != nil {
		return nil, err
	}
	out := []model.File{}
	for _, x := range entries {
		if !x.IsDir() && filepath.Ext(x.Name()) == ".json" {
			if f, err := s.GetFile(x.Name()[:len(x.Name())-5]); err == nil {
				out = append(out, f)
			}
		}
	}
	return out, nil
}
func (s *Store) ReceiveFile(id, name, hash string, size int64, r io.Reader) (f model.File, err error) {
	if !model.ValidID(id) || model.ValidateFileName(name) != nil || size < 0 || size > model.MaxFileBytes || len(hash) != 64 {
		return f, errors.New("파일 이름 또는 크기 제한을 확인해 주세요 (파일당 256 MiB)")
	}
	if _, err = hex.DecodeString(hash); err != nil {
		return f, err
	}
	// Stream without holding the store lock so health checks, captures and cleanup remain responsive.
	staged, err := os.CreateTemp(filepath.Join(s.Root, "staging"), "worklink-file-upload-")
	if err != nil {
		return f, err
	}
	defer os.Remove(staged.Name())
	h := sha256.New()
	_, err = io.CopyN(io.MultiWriter(staged, h), r, size)
	if err == nil && hex.EncodeToString(h.Sum(nil)) != hash {
		err = errors.New("원본 파일 해시가 일치하지 않습니다")
	}
	if err == nil {
		err = staged.Sync()
	}
	ce := staged.Close()
	if err != nil {
		return f, err
	}
	if ce != nil {
		return f, ce
	}
	unlock, err := s.lock()
	if err != nil {
		return f, err
	}
	defer unlock()
	old, oldErr := s.GetFile(id)
	if oldErr == nil {
		if old.Name != name || old.Size != size || old.SHA256 != hash {
			return f, errors.New("file ID conflicts with different content")
		}
		_, storedHash, err := DigestFile(old.Path)
		if err != nil {
			return f, err
		}
		if storedHash != hash {
			return f, errors.New("저장된 파일이 원본과 다릅니다")
		}
		return old, nil
	}
	if !errors.Is(oldErr, os.ErrNotExist) {
		return f, oldErr
	}
	total, err := s.managedBytes()
	if err != nil {
		return f, err
	}
	if total+size > s.Limits.InboxBytes {
		return f, errors.New("원격 보관 용량이 가득 찼습니다")
	}
	dir := filepath.Join(s.Root, "file-inbox", id)
	// A UUID directory is owned by this single transfer. Never overwrite an orphan.
	if err = os.Mkdir(dir, 0700); err != nil {
		return f, err
	}
	dest := filepath.Join(dir, name)
	f = model.File{ID: id, Name: name, CreatedAt: time.Now().UTC(), Path: dest, Size: size, SHA256: hash}
	pending := s.filePending(id)
	if err = AtomicJSON(pending, f); err != nil {
		os.Remove(dir)
		return f, err
	}
	committed := false
	defer func() {
		if !committed {
			os.Remove(dest)
			os.Remove(dir)
			os.Remove(pending)
		}
	}()
	if err = os.Rename(staged.Name(), dest); err != nil {
		return f, err
	}
	if err = AtomicJSON(s.fileRecord(id), f); err != nil {
		return f, err
	}
	committed = true
	os.Remove(pending)
	return f, nil
}
func (s *Store) managedBytes() (int64, error) {
	images, err := s.List()
	if err != nil {
		return 0, err
	}
	files, err := s.ListFiles()
	if err != nil {
		return 0, err
	}
	var total int64
	for _, i := range images {
		total += i.Size
	}
	for _, f := range files {
		total += f.Size
	}
	return total, nil
}
func (s *Store) cleanupFiles(now time.Time, dry bool) ([]string, error) {
	files, err := s.ListFiles()
	if err != nil {
		return nil, err
	}
	out := []string{}
	for _, f := range files {
		if now.Sub(f.CreatedAt) < 24*time.Hour {
			continue
		}
		if !dry {
			if err = os.Remove(f.Path); err != nil {
				return out, err
			}
			if err = os.Remove(filepath.Dir(f.Path)); err != nil {
				return out, err
			}
			if err = os.Remove(s.fileRecord(f.ID)); err != nil {
				return out, err
			}
		}
		out = append(out, f.Path)
	}
	remnants, err := s.cleanupFileRemnants(now, dry)
	out = append(out, remnants...)
	return out, err
}

// Reclaim only Worklink-owned, stale transfer remnants after a process crash.
// Live batches have a 10 minute deadline, so 24 hours cannot overlap a live upload.
func (s *Store) cleanupFileRemnants(now time.Time, dry bool) ([]string, error) {
	out := []string{}
	staged, err := os.ReadDir(filepath.Join(s.Root, "staging"))
	if err != nil {
		return out, err
	}
	for _, entry := range staged {
		if !strings.HasPrefix(entry.Name(), "worklink-file-upload-") {
			continue
		}
		path := filepath.Join(s.Root, "staging", entry.Name())
		info, err := os.Lstat(path)
		if err != nil {
			return out, err
		}
		if !info.Mode().IsRegular() || now.Sub(info.ModTime()) < 24*time.Hour {
			continue
		}
		if !dry {
			if err = os.Remove(path); err != nil {
				return out, err
			}
		}
		out = append(out, path)
	}
	records, err := os.ReadDir(filepath.Join(s.Root, "file-records"))
	if err != nil {
		return out, err
	}
	for _, entry := range records {
		if !strings.HasSuffix(entry.Name(), ".pending.json") {
			continue
		}
		id := strings.TrimSuffix(entry.Name(), ".pending.json")
		if !model.ValidID(id) {
			continue
		}
		pending := s.filePending(id)
		var f model.File
		b, err := os.ReadFile(pending)
		if err != nil {
			return out, err
		}
		if json.Unmarshal(b, &f) != nil || !s.validFileManifest(id, f) || now.Sub(f.CreatedAt) < 24*time.Hour {
			continue
		}
		if complete, err := s.GetFile(id); err == nil {
			if complete.Name == f.Name && complete.SHA256 == f.SHA256 && complete.Path == f.Path {
				if !dry {
					if err = os.Remove(pending); err != nil {
						return out, err
					}
				}
				out = append(out, pending)
			}
			continue
		}
		// Only the durable pending manifest proves ownership; a UUID directory alone never does.
		if _, err := os.Lstat(s.fileRecord(id)); err == nil {
			continue
		} else if !os.IsNotExist(err) {
			return out, err
		}
		dir := filepath.Dir(f.Path)
		info, err := os.Lstat(dir)
		if os.IsNotExist(err) {
			if !dry {
				if err = os.Remove(pending); err != nil {
					return out, err
				}
			}
			out = append(out, pending)
			continue
		}
		if err != nil {
			return out, err
		}
		if !info.IsDir() || info.Mode()&os.ModeSymlink != 0 {
			continue
		}
		children, err := os.ReadDir(dir)
		if err != nil {
			return out, err
		}
		if len(children) > 1 {
			continue
		}
		safe := true
		for _, child := range children {
			st, err := os.Lstat(filepath.Join(dir, child.Name()))
			if err != nil || child.Name() != f.Name || !st.Mode().IsRegular() || st.Size() != f.Size {
				safe = false
			}
		}
		if safe && len(children) == 1 {
			n, hash, err := DigestFile(f.Path)
			if err != nil || n != f.Size || hash != f.SHA256 {
				safe = false
			}
		}
		if !safe {
			continue
		}
		if !dry {
			if len(children) == 1 {
				if err = os.Remove(f.Path); err != nil {
					return out, err
				}
			}
			if err = os.Remove(dir); err != nil {
				return out, err
			}
			if err = os.Remove(pending); err != nil {
				return out, err
			}
		}
		out = append(out, dir)
	}
	return out, nil
}
func (s *Store) filePending(id string) string {
	return filepath.Join(s.Root, "file-records", id+".pending.json")
}
func (s *Store) validFileManifest(id string, f model.File) bool {
	_, hashErr := hex.DecodeString(f.SHA256)
	return f.ID == id && model.ValidID(id) && model.ValidateFileName(f.Name) == nil && f.Path == filepath.Join(s.Root, "file-inbox", id, f.Name) && f.Size >= 0 && f.Size <= model.MaxFileBytes && !f.CreatedAt.IsZero() && len(f.SHA256) == 64 && hashErr == nil
}
