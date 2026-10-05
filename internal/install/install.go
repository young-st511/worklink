package install

import (
	"bytes"
	"context"
	"encoding/xml"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/young-st511/worklink/internal/model"
)

func escape(s string) string { var b bytes.Buffer; xml.EscapeText(&b, []byte(s)); return b.String() }
func CleanupPlist(binary, root string, hour int) ([]byte, error) {
	if !filepath.IsAbs(binary) || !filepath.IsAbs(root) || hour < 0 || hour > 23 {
		return nil, errors.New("invalid cleanup installation options")
	}
	return []byte(fmt.Sprintf(`<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>Label</key><string>dev.worklink.cleanup</string>
<key>ProgramArguments</key><array><string>%s</string><string>image</string><string>cleanup</string></array>
<key>EnvironmentVariables</key><dict><key>WORKLINK_DATA_DIR</key><string>%s</string></dict>
<key>StartCalendarInterval</key><dict><key>Hour</key><integer>%d</integer><key>Minute</key><integer>0</integer></dict>
</dict></plist>`, escape(binary), escape(root), hour)), nil
}
func CleanupJob(root string, hour int, remove, dry bool) (string, error) {
	home, e := os.UserHomeDir()
	if e != nil {
		return "", e
	}
	binary, e := os.Executable()
	if e != nil {
		return "", e
	}
	path := filepath.Join(home, "Library", "LaunchAgents", "dev.worklink.cleanup.plist")
	if dry {
		data, e := CleanupPlist(binary, root, hour)
		return string(data), e
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	domain := "gui/" + strconv.Itoa(os.Getuid())
	exec.CommandContext(ctx, "/bin/launchctl", "bootout", domain, path).Run()
	if remove {
		e = os.Remove(path)
		if os.IsNotExist(e) {
			e = nil
		}
		return path, e
	}
	data, e := CleanupPlist(binary, root, hour)
	if e != nil {
		return "", e
	}
	if e = os.MkdirAll(filepath.Dir(path), 0700); e != nil {
		return "", e
	}
	if e = os.WriteFile(path, data, 0600); e != nil {
		return "", e
	}
	out, e := exec.CommandContext(ctx, "/bin/launchctl", "bootstrap", domain, path).CombinedOutput()
	if e != nil {
		return path, fmt.Errorf("일일 정리 등록 실패. 원격 사용자의 GUI 로그인을 확인해 주세요: %s", strings.TrimSpace(string(out)))
	}
	return path, nil
}
func Remote(ctx context.Context, h model.Host, resources string) error {
	if e := model.ValidateHost(h); e != nil {
		return e
	}
	options := []string{"-o", "BatchMode=yes", "-o", "RemoteCommand=none", "-o", "RequestTTY=no", "-o", "ClearAllForwardings=yes", "-o", "Compression=no", "-o", "ConnectTimeout=8", h.Name}
	out, e := exec.CommandContext(ctx, "/usr/bin/ssh", append(options, "uname -sm")...).Output()
	if e != nil {
		return e
	}
	platform := strings.Fields(string(out))
	if len(platform) != 2 || platform[0] != "Darwin" {
		return errors.New("원격 헬퍼 설치는 macOS만 지원합니다")
	}
	arch := "arm64"
	if platform[1] == "x86_64" {
		arch = "amd64"
	} else if platform[1] != "arm64" {
		return errors.New("지원하지 않는 원격 CPU입니다")
	}
	binary := filepath.Join(resources, "worklink-darwin-"+arch)
	file, e := os.Open(binary)
	if e != nil {
		return e
	}
	defer file.Close() // Host/helper names are validated; only these fixed commands enter the shell.
	dest := h.Helper
	dir := filepath.Dir(dest)
	command := "mkdir -p " + dir + " && cat > " + dest + ".new && chmod 700 " + dest + ".new && mv -f " + dest + ".new " + dest + " && " + dest + " cleanup install"
	cmd := exec.CommandContext(ctx, "/usr/bin/ssh", append(options, command)...)
	cmd.Stdin = file
	result, e := cmd.CombinedOutput()
	if e != nil {
		return fmt.Errorf("원격 설치 실패: %s", strings.TrimSpace(string(result)))
	}
	return nil
}
