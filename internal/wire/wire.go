package wire

import (
	"encoding/binary"
	"encoding/json"
	"errors"
	"io"
)

const Version = 1
const MaxHeader = 64 << 10

func Write(w io.Writer, v any) error {
	b, e := json.Marshal(v)
	if e != nil {
		return e
	}
	if len(b) > MaxHeader {
		return errors.New("frame too large")
	}
	var n [4]byte
	binary.BigEndian.PutUint32(n[:], uint32(len(b)))
	if e = fullWrite(w, n[:]); e != nil {
		return e
	}
	return fullWrite(w, b)
}
func fullWrite(w io.Writer, b []byte) error {
	for len(b) > 0 {
		n, e := w.Write(b)
		if e != nil {
			return e
		}
		if n <= 0 || n > len(b) {
			return io.ErrShortWrite
		}
		b = b[n:]
	}
	return nil
}
func Read(r io.Reader, v any) error {
	var n [4]byte
	if _, e := io.ReadFull(r, n[:]); e != nil {
		return e
	}
	size := binary.BigEndian.Uint32(n[:])
	if size == 0 || size > MaxHeader {
		return errors.New("invalid frame length")
	}
	b := make([]byte, size)
	if _, e := io.ReadFull(r, b); e != nil {
		return e
	}
	return json.Unmarshal(b, v)
}
