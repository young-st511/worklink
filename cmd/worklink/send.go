package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"github.com/young-st511/worklink/internal/model"
	"github.com/young-st511/worklink/internal/remote"
	"github.com/young-st511/worklink/internal/storage"
	"github.com/young-st511/worklink/internal/transport"
	"os"
	"path/filepath"
	"strings"
	"time"
)

func sendImage(args []string, c model.Config) error {
	f := flag.NewFlagSet("image send", flag.ContinueOnError)
	host := f.String("host", c.ImageHost, "SSH 대상")
	file := f.String("file", "", "원본 이미지 파일")
	if e := f.Parse(args); e != nil {
		return e
	}
	h, ok := c.Host(*host)
	if !ok {
		return errors.New("SSH 대상을 먼저 등록해 주세요")
	}
	ext := strings.TrimPrefix(strings.ToLower(filepath.Ext(*file)), ".")
	if !model.ValidExtension(ext) {
		return errors.New("원본 이미지 형식을 확인해 주세요")
	}
	size, hash, e := storage.DigestFile(*file)
	if e != nil {
		return e
	}
	if size < 1 || size > c.Limits.ImageBytes {
		return errors.New("원본 이미지 크기 제한을 초과했습니다")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 90*time.Second)
	defer cancel()
	conn, e := transport.Connect(ctx, h)
	if e != nil {
		return e
	}
	defer conn.Close()
	if _, e = conn.Call(ctx, remote.Request{Op: "limits", Limits: &c.Limits}, nil); e != nil {
		return e
	}
	src, e := os.Open(*file)
	if e != nil {
		return e
	}
	defer src.Close()
	r, e := conn.Call(ctx, remote.Request{Op: "upload", ID: model.NewID(), Extension: ext, Size: size, SHA256: hash}, src)
	if e != nil {
		return e
	}
	if r.Image == nil || r.Image.SHA256 != hash || r.Image.Size != size {
		return errors.New("원본 전송 완료 확인 실패")
	}
	fmt.Println(r.Image.Path)
	return nil
}
