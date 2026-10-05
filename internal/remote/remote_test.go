package remote

import (
	"bytes"
	"crypto/sha256"
	"fmt"
	"testing"

	"github.com/young-st511/worklink/internal/model"
	"github.com/young-st511/worklink/internal/storage"
	"github.com/young-st511/worklink/internal/wire"
)

func TestHelloAndEOF(t *testing.T) {
	s, _ := storage.Open(t.TempDir(), model.DefaultConfig().Limits)
	var in, out bytes.Buffer
	wire.Write(&in, Request{Version: wire.Version, Op: "hello"})
	if e := Serve(&in, &out, s); e != nil {
		t.Fatal(e)
	}
	var r Response
	if e := wire.Read(&out, &r); e != nil || r.Error != "" || r.Root != s.Root {
		t.Fatal(r, e)
	}
}
func TestUploadThenExistsAndList(t *testing.T) {
	s, _ := storage.Open(t.TempDir(), model.DefaultConfig().Limits)
	var in, out bytes.Buffer
	data := []byte{0, 255, 2, 3}
	id := model.NewID()
	wire.Write(&in, Request{Version: 1, Op: "upload", ID: id, Size: 4, Extension: "png", SHA256: fmt.Sprintf("%x", sha256.Sum256(data))})
	in.Write(data)
	wire.Write(&in, Request{Version: 1, Op: "exists", ID: id})
	wire.Write(&in, Request{Version: 1, Op: "list"})
	if e := Serve(&in, &out, s); e != nil {
		t.Fatal(e)
	}
	for n := 0; n < 3; n++ {
		var r Response
		if e := wire.Read(&out, &r); e != nil || r.Error != "" {
			t.Fatal(r, e)
		}
		if n == 0 && r.Image == nil {
			t.Fatal("no ACK")
		}
		if n == 1 && !r.Exists {
			t.Fatal("missing exists")
		}
		if n == 2 && len(r.Images) != 1 {
			t.Fatal("missing list")
		}
	}
}
func TestBadVersionAndTruncatedUpload(t *testing.T) {
	s, _ := storage.Open(t.TempDir(), model.DefaultConfig().Limits)
	for _, q := range []Request{{Version: 99, Op: "hello"}, {Version: 1, Op: "upload", ID: model.NewID(), Extension: "png", Size: 4, SHA256: fmt.Sprintf("%x", sha256.Sum256([]byte{1, 2, 3, 4}))}} {
		var in, out bytes.Buffer
		wire.Write(&in, q)
		if e := Serve(&in, &out, s); e == nil {
			t.Fatal("invalid request accepted")
		}
		var r Response
		if e := wire.Read(&out, &r); e != nil || r.Error == "" {
			t.Fatal(r, e)
		}
	}
}
