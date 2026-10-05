package model

import (
	"testing"

	"github.com/young-st511/worklink/internal/address"
)

func TestConfigCanonicalAndDuplicate(t *testing.T) {
	c := DefaultConfig()
	c.Hosts = []Host{{Name: "office", Helper: "~/.local/bin/worklink"}}
	ep := address.Parse("5173").Endpoint
	c.Ports = []Port{{ID: NewID(), Host: "office", Endpoint: ep, LocalPort: 5173}}
	if e := c.Validate(); e != nil {
		t.Fatal(e)
	}
	p := c.Ports[0]
	p.ID = NewID()
	p.LocalPort = 15173
	c.Ports = append(c.Ports, p)
	if c.Validate() == nil {
		t.Fatal("duplicate endpoint")
	}
	c.Ports = c.Ports[:1]
	c.Ports[0].Endpoint.RemoteHost = "localhost"
	if c.Validate() == nil {
		t.Fatal("noncanonical endpoint")
	}
}
