package model

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"net/url"
	"path/filepath"
	"regexp"
	"strings"
	"time"

	"github.com/young-st511/worklink/internal/address"
)

const Version = "0.1.0"

type Host struct {
	Name   string `json:"name"`
	Helper string `json:"helper"`
}
type Port struct {
	Pinned    bool             `json:"pinned,omitempty"`
	ID        string           `json:"id"`
	Name      string           `json:"name"`
	Host      string           `json:"host"`
	Endpoint  address.Endpoint `json:"endpoint"`
	LocalPort int              `json:"local_port"`
	Enabled   bool             `json:"enabled"`
	Title     string           `json:"title,omitempty"`
}
type Limits struct {
	ImageBytes int64 `json:"image_bytes"`
	QueueBytes int64 `json:"queue_bytes"`
	QueueCount int   `json:"queue_count"`
	InboxBytes int64 `json:"inbox_bytes"`
}
type PortCleanupHistory struct {
	LastRun   time.Time `json:"last_run"`
	RemovedAt time.Time `json:"removed_at"`
	Removed   []Port    `json:"removed"`
}
type Config struct {
	PortCleanupEnabled bool                `json:"port_cleanup_enabled"`
	PortCleanupDays    int                 `json:"port_cleanup_days"`
	PortCleanupHistory *PortCleanupHistory `json:"port_cleanup_history,omitempty"`
	Revision           uint64              `json:"revision"`
	Hosts              []Host              `json:"hosts"`
	Ports              []Port              `json:"ports"`
	ImageHost          string              `json:"image_host"`
	Limits             Limits              `json:"limits"`
}

func DefaultConfig() Config {
	return Config{PortCleanupDays: 7, Hosts: []Host{}, Ports: []Port{}, Limits: Limits{64 << 20, 256 << 20, 8, 2 << 30}}
}

var hostRE = regexp.MustCompile(`^[A-Za-z0-9_][A-Za-z0-9_.@-]{0,127}$`)
var helperRE = regexp.MustCompile(`^(~/|/)[A-Za-z0-9_./-]+$`)
var idRE = regexp.MustCompile(`^[a-f0-9]{32}$`)

func ValidID(id string) bool { return idRE.MatchString(id) }
func NewID() string {
	var b [16]byte
	if _, e := rand.Read(b[:]); e != nil {
		panic(e)
	}
	return hex.EncodeToString(b[:])
}
func ValidateHost(h Host) error {
	if !hostRE.MatchString(h.Name) || !helperRE.MatchString(h.Helper) || strings.Contains(h.Helper, "..") {
		return errors.New("SSH 별칭과 헬퍼 경로를 확인해 주세요 (기본: ~/.local/bin/worklink)")
	}
	return nil
}
func (c Config) Host(name string) (Host, bool) {
	for _, h := range c.Hosts {
		if h.Name == name {
			return h, true
		}
	}
	return Host{}, false
}
func (c Config) Validate() error { return c.validate(16) }

// ValidatePortAddition validates one pending addition before safe replacement.
func (c Config) ValidatePortAddition() error { return c.validate(17) }
func (c Config) validate(maxPorts int) error {
	if c.PortCleanupDays != 0 && c.PortCleanupDays != 3 && c.PortCleanupDays != 7 && c.PortCleanupDays != 14 && c.PortCleanupDays != 30 {
		return errors.New("포트 정리 기간은 3·7·14·30일 중 선택해 주세요")
	}
	if h := c.PortCleanupHistory; h != nil {
		if len(h.Removed) > 16 {
			return errors.New("포트 정리 기록이 너무 큽니다")
		}
		for _, p := range h.Removed {
			if !ValidID(p.ID) {
				return errors.New("포트 정리 기록을 확인해 주세요")
			}
		}
	}
	if len(c.Ports) > maxPorts || len(c.Hosts) > 8 {
		return errors.New("서버는 최대 16개, SSH 대상은 최대 8개까지 등록할 수 있습니다")
	}
	if c.Limits.ImageBytes <= 0 || c.Limits.ImageBytes > 256<<20 || c.Limits.QueueBytes < c.Limits.ImageBytes || c.Limits.QueueBytes > 1<<30 || c.Limits.QueueCount < 1 || c.Limits.QueueCount > 64 || c.Limits.InboxBytes < c.Limits.ImageBytes {
		return errors.New("용량 제한을 확인해 주세요")
	}
	seen := map[string]bool{}
	for _, h := range c.Hosts {
		if err := ValidateHost(h); err != nil {
			return err
		}
		if seen[h.Name] {
			return errors.New("SSH 대상이 중복됩니다")
		}
		seen[h.Name] = true
	}
	if c.ImageHost != "" && !seen[c.ImageHost] {
		return errors.New("이미지 전송 대상을 등록해 주세요")
	}
	ids := map[string]bool{}
	locals := map[int]bool{}
	ends := map[string]bool{}
	for _, p := range c.Ports {
		if _, err := url.QueryUnescape(p.Endpoint.Query); err != nil {
			return errors.New("query 인코딩을 확인해 주세요")
		}
		if p.Endpoint.RawPath != "" {
			decoded, err := url.PathUnescape(p.Endpoint.RawPath)
			if err != nil || decoded != p.Endpoint.Path {
				return errors.New("path 인코딩을 확인해 주세요")
			}
		}
		if p.Endpoint.RawFragment != "" {
			decoded, err := url.PathUnescape(p.Endpoint.RawFragment)
			if err != nil || decoded != p.Endpoint.Fragment {
				return errors.New("fragment 인코딩을 확인해 주세요")
			}
		}
		r := address.Parse(p.Endpoint.Scheme + "://" + p.Endpoint.Address() + p.Endpoint.Path)
		if !ValidID(p.ID) || r.Error != "" || r.NeedsPort || r.Endpoint.RemoteHost != p.Endpoint.RemoteHost || !seen[p.Host] || p.LocalPort < 1024 || p.LocalPort > 65535 {
			return errors.New("등록된 개발 서버 주소를 확인해 주세요")
		}
		if ids[p.ID] || locals[p.LocalPort] || ends[p.Host+"/"+p.Endpoint.Address()] {
			return errors.New("이미 등록된 서버 또는 로컬 포트입니다")
		}
		ids[p.ID] = true
		locals[p.LocalPort] = true
		ends[p.Host+"/"+p.Endpoint.Address()] = true
	}
	return nil
}

type Image struct {
	ID             string    `json:"id"`
	Host           string    `json:"host,omitempty"`
	CreatedAt      time.Time `json:"created_at"`
	Path           string    `json:"path"`
	Size           int64     `json:"size"`
	SHA256         string    `json:"sha256"`
	Extension      string    `json:"extension"`
	Pinned         bool      `json:"pinned"`
	Status         string    `json:"status,omitempty"`
	Error          string    `json:"error,omitempty"`
	ClipboardCount int       `json:"clipboard_count,omitempty"`
	Generation     uint64    `json:"generation,omitempty"`
}

func ValidExtension(ext string) bool {
	switch ext {
	case "png", "jpg", "jpeg", "tiff", "heic", "heif", "webp":
		return true
	}
	return false
}
func CaptureName(t time.Time, id, ext string) string {
	return fmt.Sprintf("worklink-capture-%s-%s.%s", t.UTC().Format("20060102T150405.000Z"), id, ext)
}
func ValidImageName(i Image) bool {
	return ValidID(i.ID) && ValidExtension(i.Extension) && filepath.Base(i.Path) == CaptureName(i.CreatedAt, i.ID, i.Extension)
}
