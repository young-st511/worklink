package transport

import (
	"context"
	"github.com/young-st511/worklink/internal/remote"
	"testing"
	"time"
)

func TestRPCWaitHonorsDeadline(t *testing.T) {
	s := &SSH{rpc: make(chan struct{}, 1)}
	s.rpc <- struct{}{}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Millisecond)
	defer cancel()
	start := time.Now()
	_, err := s.Call(ctx, remote.Request{Op: "hello"}, nil)
	if err != context.DeadlineExceeded || time.Since(start) > 100*time.Millisecond {
		t.Fatal("RPC waiter ignored deadline", err, time.Since(start))
	}
}
