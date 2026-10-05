package main

import (
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"github.com/young-st511/worklink/internal/address"
	"github.com/young-st511/worklink/internal/engine"
	"github.com/young-st511/worklink/internal/model"
	"github.com/young-st511/worklink/internal/remote"
	"github.com/young-st511/worklink/internal/storage"
	"io"
	"os"
	"path/filepath"
	"strconv"
)

func output(v any) error { return json.NewEncoder(os.Stdout).Encode(v) }
func main() {
	if e := run(os.Args[1:]); e != nil {
		fmt.Fprintln(os.Stderr, e)
		os.Exit(1)
	}
}
func run(args []string) error {
	if len(args) == 0 {
		return errors.New("사용법: worklink parse|host|port|image|remote|version|doctor")
	}
	if args[0] == "version" {
		fmt.Println(model.Version)
		return nil
	}
	if args[0] == "parse" {
		if len(args) != 2 {
			return errors.New("worklink parse <주소>")
		}
		return output(address.Parse(args[1]))
	}
	if args[0] == "ui" {
		if len(args) != 2 || args[1] != "--stdio" {
			return errors.New("worklink ui --stdio")
		}
		return engine.ServeUI(storage.DefaultRoot(), os.Stdin, os.Stdout)
	}
	s, e := storage.Open(storage.DefaultRoot(), model.DefaultConfig().Limits)
	if e != nil {
		return e
	}
	c, e := s.LoadConfig()
	if e != nil {
		return e
	}
	s.Limits = c.Limits
	switch args[0] {
	case "remote":
		if len(args) != 2 || args[1] != "--stdio" {
			return errors.New("worklink remote --stdio")
		}
		return remote.Serve(os.Stdin, os.Stdout, s)
	case "doctor":
		return output(map[string]any{"version": model.Version, "data_dir": s.Root, "config_valid": true, "hosts": len(c.Hosts), "ports": len(c.Ports)})
	case "host":
		if len(args) < 2 {
			return errors.New("worklink host add|list|remove|select")
		}
		switch args[1] {
		case "list":
			return output(c.Hosts)
		case "add":
			f := flag.NewFlagSet("host add", flag.ContinueOnError)
			name := f.String("name", "", "SSH 별칭")
			helper := f.String("helper", "~/.local/bin/worklink", "원격 헬퍼")
			if e = f.Parse(args[2:]); e != nil {
				return e
			}
			h := model.Host{Name: *name, Helper: *helper}
			if e = model.ValidateHost(h); e != nil {
				return e
			}
			for _, old := range c.Hosts {
				if old.Name == h.Name {
					return errors.New("이미 등록한 SSH 대상입니다")
				}
			}
			c.Hosts = append(c.Hosts, h)
			if c.ImageHost == "" {
				c.ImageHost = h.Name
			}
		case "select":
			if len(args) != 3 {
				return errors.New("worklink host select <별칭>")
			}
			c.ImageHost = args[2]
		case "remove":
			if len(args) != 3 {
				return errors.New("worklink host remove <별칭>")
			}
			name := args[2]
			for _, p := range c.Ports {
				if p.Host == name {
					return errors.New("이 대상의 서버 등록부터 삭제해 주세요")
				}
			}
			out := []model.Host{}
			for _, h := range c.Hosts {
				if h.Name != name {
					out = append(out, h)
				}
			}
			c.Hosts = out
			if c.ImageHost == name {
				c.ImageHost = ""
			}
		default:
			return errors.New("지원하지 않는 host 명령")
		}
		return s.SaveConfig(&c)
	case "port":
		if len(args) < 2 {
			return errors.New("worklink port add|list|remove")
		}
		switch args[1] {
		case "list":
			return output(c.Ports)
		case "add":
			f := flag.NewFlagSet("port add", flag.ContinueOnError)
			input := f.String("address", "", "원격 URL 또는 포트")
			host := f.String("host", c.ImageHost, "SSH 별칭")
			name := f.String("name", "", "표시 이름")
			rp := f.Int("remote-port", 0, "원격 포트")
			lp := f.Int("local-port", 0, "로컬 포트")
			if e = f.Parse(args[2:]); e != nil {
				return e
			}
			if *input == "" {
				*input = strconv.Itoa(*rp)
			}
			r := address.Parse(*input)
			if r.Error != "" {
				return errors.New(r.Error)
			}
			if r.NeedsPort || len(r.Candidates) > 0 {
				return errors.New("포트를 지정하거나 URL 후보 하나를 선택해 주세요")
			}
			if *lp == 0 {
				*lp = r.Endpoint.RemotePort
			}
			c.Ports = append(c.Ports, model.Port{ID: model.NewID(), Name: *name, Host: *host, Endpoint: r.Endpoint, LocalPort: *lp, Enabled: true})
			return s.SaveConfig(&c)
		case "remove":
			if len(args) != 3 {
				return errors.New("worklink port remove <이름 또는 ID>")
			}
			out := []model.Port{}
			for _, p := range c.Ports {
				if p.ID != args[2] && p.Name != args[2] {
					out = append(out, p)
				}
			}
			c.Ports = out
			return s.SaveConfig(&c)
		default:
			return errors.New("지원하지 않는 port 명령")
		}
	case "image":
		if len(args) < 2 {
			return errors.New("worklink image latest|list|cleanup|pin|export")
		}
		switch args[1] {
		case "list":
			all, e := s.List()
			if e != nil {
				return e
			}
			return output(all)
		case "send":
			return sendImage(args[2:], c)
		case "latest":
			all, e := s.List()
			if e != nil {
				return e
			}
			if len(all) == 0 {
				return errors.New("완료한 이미지가 없습니다")
			}
			fmt.Println(all[0].Path)
			return nil
		case "cleanup":
			dry := len(args) == 3 && args[2] == "--dry-run"
			if len(args) > 3 || (len(args) == 3 && !dry) {
				return errors.New("worklink image cleanup [--dry-run]")
			}
			paths, e := s.Cleanup(now(), dry)
			if e != nil {
				return e
			}
			return output(paths)
		case "pin":
			if len(args) != 3 {
				return errors.New("worklink image pin <ID>")
			}
			return s.Pin(args[2], true)
		case "export":
			if len(args) != 4 {
				return errors.New("worklink image export <ID> <새 파일 경로>")
			}
			i, e := s.Get(args[2])
			if e != nil {
				return e
			}
			src, e := os.Open(i.Path)
			if e != nil {
				return e
			}
			defer src.Close()
			dest := filepath.Clean(args[3])
			f, e := os.OpenFile(dest, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0600)
			if e != nil {
				return e
			}
			_, e = io.Copy(f, src)
			ce := f.Close()
			if e != nil {
				os.Remove(dest)
				return e
			}
			return ce
		default:
			return errors.New("지원하지 않는 image 명령")
		}
	}
	return errors.New("지원하지 않는 명령")
}
