package main

import (
	"errors"
	"sync"
	"time"

	"github.com/amnezia-vpn/amneziawg-go/v3/conn"
)

var errSessionExpired = errors.New("Moley session expired")

// Guard every outgoing datagram, including handshake retries, junk, cookies and
// keepalives. Go's patched monotonic clock includes device sleep on iOS.
type sessionBind struct {
	conn.Bind
	mu       sync.RWMutex
	deadline time.Time
	now      func() time.Time
}

func newSessionBind(bind conn.Bind, milliseconds int64) *sessionBind {
	b := &sessionBind{Bind: bind, now: time.Now}
	b.renew(milliseconds)
	return b
}

func (b *sessionBind) renew(milliseconds int64) {
	b.mu.Lock()
	defer b.mu.Unlock()
	// Reject malformed/overflowing lifetimes. Zero explicitly stops transmission.
	if milliseconds <= 0 || milliseconds > int64(7*24*time.Hour/time.Millisecond) {
		b.deadline = time.Time{}
		return
	}
	b.deadline = b.now().Add(time.Duration(milliseconds) * time.Millisecond)
}

func (b *sessionBind) Send(packets [][]byte, endpoint conn.Endpoint) error {
	b.mu.RLock()
	defer b.mu.RUnlock()
	if !b.now().Before(b.deadline) {
		return errSessionExpired
	}
	return b.Bind.Send(packets, endpoint)
}
