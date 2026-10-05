package wire

import (
	"bytes"
	"encoding/binary"
	"testing"
)

func TestFrames(t *testing.T) {
	var b bytes.Buffer
	if e := Write(&b, map[string]int{"version": 1}); e != nil {
		t.Fatal(e)
	}
	var out map[string]int
	if e := Read(&b, &out); e != nil || out["version"] != 1 {
		t.Fatal(out, e)
	}
	var n [4]byte
	binary.BigEndian.PutUint32(n[:], MaxHeader+1)
	if Read(bytes.NewReader(n[:]), &out) == nil {
		t.Fatal("unbounded frame")
	}
}
