package main

import (
	"errors"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/amnezia-vpn/amneziawg-go/v3/conn"
)

type countingBind struct {
	conn.Bind
	sends atomic.Int64
}

func (b *countingBind) Send(_ [][]byte, _ conn.Endpoint) error {
	b.sends.Add(1)
	return nil
}

func TestSessionBindDeadline(t *testing.T) {
	underlying := &countingBind{}
	now := time.Now()
	guard := newSessionBind(underlying, 1)
	guard.now = func() time.Time { return now }
	guard.renew(30 * 60 * 1000)
	if err := guard.Send([][]byte{{1, 2, 3}}, nil); err != nil {
		t.Fatal(err)
	}
	now = now.Add(30 * time.Minute)
	// Covers all output: the wrapper doesn't special-case handshake or keepalive.
	for _, packet := range [][]byte{{1}, {2}, {3}, {4}, {99, 99}} {
		if err := guard.Send([][]byte{packet}, nil); !errors.Is(err, errSessionExpired) {
			t.Fatalf("expired traffic was not blocked: %v", err)
		}
	}
	if underlying.sends.Load() != 1 {
		t.Fatal("expired datagram reached UDP bind")
	}
}

func TestSessionBindExplicitRenewalAndRevocation(t *testing.T) {
	underlying := &countingBind{}
	guard := newSessionBind(underlying, 0)
	if !errors.Is(guard.Send(nil, nil), errSessionExpired) {
		t.Fatal("missing lease must fail closed")
	}
	guard.renew(1800000)
	if err := guard.Send(nil, nil); err != nil {
		t.Fatal(err)
	}
	for _, invalid := range []int64{0, -1, 1 << 62} {
		guard.renew(invalid)
		if !errors.Is(guard.Send(nil, nil), errSessionExpired) {
			t.Fatal("revoked or invalid lease allowed traffic")
		}
	}
}

func TestSessionBindConcurrentRenewal(t *testing.T) {
	guard := newSessionBind(&countingBind{}, 1800000)
	var workers sync.WaitGroup
	for i := 0; i < 8; i++ {
		workers.Add(1)
		go func() {
			defer workers.Done()
			for n := 0; n < 100; n++ {
				guard.renew(1800000)
				_ = guard.Send(nil, nil)
			}
		}()
	}
	workers.Wait()
}
