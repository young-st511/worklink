package model

import (
	"errors"
	"path/filepath"
	"strings"
	"time"
)

const MaxFileBytes int64 = 256 << 20
const MaxFileBatch = 8

// File is a managed, byte-for-byte copy of an explicitly selected ordinary file.
type File struct {
	ID        string    `json:"id"`
	Name      string    `json:"name"`
	CreatedAt time.Time `json:"created_at"`
	Path      string    `json:"path"`
	Size      int64     `json:"size"`
	SHA256    string    `json:"sha256"`
}

func ValidateFileName(name string) error {
	if name == "" || name == "." || name == ".." || len(name) > 255 || filepath.Base(name) != name || strings.ContainsAny(name, "/\\\x00\r\n") {
		return errors.New("일반 파일 이름을 확인해 주세요 (경로·개행은 사용할 수 없습니다)")
	}
	return nil
}
