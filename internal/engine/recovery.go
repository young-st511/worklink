package engine

import (
	"encoding/json"
	"errors"
	"github.com/young-st511/worklink/internal/model"
	"github.com/young-st511/worklink/internal/storage"
	"os"
	"path/filepath"
	"strings"
)

func (e *Engine) journal(j Job) string { return filepath.Join(e.store.Root, "queue", j.ID+".json") }
func (e *Engine) queueUsage() (int, int64, error) {
	files, err := os.ReadDir(filepath.Join(e.store.Root, "queue"))
	if err != nil {
		return 0, 0, err
	}
	count := 0
	var total int64
	for _, f := range files {
		if strings.HasSuffix(f.Name(), ".json") || strings.HasPrefix(f.Name(), ".tmp-") {
			continue
		}
		st, err := f.Info()
		if err != nil {
			return 0, 0, err
		}
		if st.Mode().IsRegular() {
			count++
			total += st.Size()
		}
	}
	return count, total, nil
}
func (e *Engine) recoverQueue() error {
	seen := map[string]bool{}
	for _, j := range e.state.Jobs {
		if !model.ValidID(j.ID) || !model.ValidExtension(j.Extension) {
			return errors.New("대기 이미지 기록을 확인해 주세요")
		}
		seen[j.ID] = true
		if j.Status == "complete" {
			os.Remove(e.queuePath(j))
		}
	}
	files, err := os.ReadDir(filepath.Join(e.store.Root, "queue"))
	if err != nil {
		return err
	}
	for _, f := range files {
		if !strings.HasSuffix(f.Name(), ".json") {
			continue
		}
		id := strings.TrimSuffix(f.Name(), ".json")
		if !model.ValidID(id) {
			continue
		}
		if seen[id] {
			os.Remove(filepath.Join(e.store.Root, "queue", f.Name()))
			continue
		}
		var j Job
		b, err := os.ReadFile(filepath.Join(e.store.Root, "queue", f.Name()))
		if err != nil {
			return err
		}
		if err = json.Unmarshal(b, &j); err != nil || j.ID != id || !model.ValidExtension(j.Extension) {
			continue
		}
		j.Path = e.queuePath(j)
		size, hash, err := storage.DigestFile(j.Path)
		if os.IsNotExist(err) {
			os.Remove(e.journal(j))
			continue
		}
		if err != nil {
			return err
		}
		j.Status = "paused"
		if size != j.Size {
			j.Status = "failed"
			j.Error = "복사 중 앱이 종료됐습니다. 원본을 다시 캡처해 주세요"
		}
		j.SHA256 = hash
		e.state.Jobs = append(e.state.Jobs, j)
		seen[j.ID] = true
	}
	return e.saveJobsLocked()
}
