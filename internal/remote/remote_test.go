package remote

import (
	"bytes"
	"crypto/sha256"
	"fmt"
	"github.com/young-st511/worklink/internal/address"
	"io"
	"net"
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

func TestDownloadOriginalAndNextFrame(t *testing.T) {
	s, _ := storage.Open(t.TempDir(), model.DefaultConfig().Limits)
	data := []byte{0, 255, 4, 3}
	id := model.NewID()
	_, err := s.Receive(id, "png", fmt.Sprintf("%x", sha256.Sum256(data)), int64(len(data)), bytes.NewReader(data))
	if err != nil {
		t.Fatal(err)
	}
	var in, out bytes.Buffer
	wire.Write(&in, Request{Version: 1, Op: "download", ID: id})
	wire.Write(&in, Request{Version: 1, Op: "hello"})
	if err = Serve(&in, &out, s); err != nil {
		t.Fatal(err)
	}
	var r Response
	if err = wire.Read(&out, &r); err != nil || r.Error != "" || r.Image == nil {
		t.Fatal(r, err)
	}
	got := make([]byte, len(data))
	if _, err = io.ReadFull(&out, got); err != nil || !bytes.Equal(got, data) {
		t.Fatal(got, err)
	}
	if err = wire.Read(&out, &r); err != nil || r.Root != s.Root {
		t.Fatal("download desynchronized channel", r, err)
	}
}

func TestCheckLoopbackFallback(t *testing.T) {
	for _, host := range []string{"127.0.0.1", "::1"} {
		t.Run(host, func(t *testing.T) {
			network := "tcp4"
			configured := "::1"
			if host == "::1" {
				network = "tcp6"
				configured = "127.0.0.1"
			}
			listener, err := net.Listen(network, net.JoinHostPort(host, "0"))
			if err != nil {
				t.Fatal(err)
			}
			defer listener.Close()
			port := listener.Addr().(*net.TCPAddr).Port
			s, _ := storage.Open(t.TempDir(), model.DefaultConfig().Limits)
			var in, out bytes.Buffer
			wire.Write(&in, Request{Version: 1, Op: "check", Endpoints: map[string]address.Endpoint{"registered": {Scheme: "http", RemoteHost: configured, RemotePort: port}}})
			if err = Serve(&in, &out, s); err != nil {
				t.Fatal(err)
			}
			var r Response
			if err = wire.Read(&out, &r); err != nil {
				t.Fatal(err)
			}
			if !r.Checks["registered"] || r.Targets["registered"] != host {
				t.Fatal("single family listener not resolved", r)
			}
		})
	}
}

func TestCheckPrefersRegisteredFamily(t *testing.T) {
	v4, err := net.Listen("tcp4", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer v4.Close()
	port := v4.Addr().(*net.TCPAddr).Port
	v6, err := net.Listen("tcp6", net.JoinHostPort("::1", fmt.Sprint(port)))
	if err != nil {
		t.Fatal(err)
	}
	defer v6.Close()
	s, _ := storage.Open(t.TempDir(), model.DefaultConfig().Limits)
	var in, out bytes.Buffer
	wire.Write(&in, Request{Version: 1, Op: "check", Endpoints: map[string]address.Endpoint{"v4": {Scheme: "http", RemoteHost: "127.0.0.1", RemotePort: port}, "v6": {Scheme: "http", RemoteHost: "::1", RemotePort: port}}})
	if err = Serve(&in, &out, s); err != nil {
		t.Fatal(err)
	}
	var response Response
	wire.Read(&out, &response)
	if response.Targets["v4"] != "127.0.0.1" || response.Targets["v6"] != "::1" {
		t.Fatal("preference lost", response)
	}
}
