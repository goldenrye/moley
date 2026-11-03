package main

import (
	"sync"

	"github.com/amnezia-vpn/amneziawg-go/v3/tun"
)

// The backend snapshots S4 before calling Read, and starts its read goroutine
// inside NewDevice, before IpcSet. Consume one empty read after configuration so
// the next iteration recomputes the correct offset before reading any IP data.
type startupTUN struct {
	tun.Device
	ready   chan struct{}
	release sync.Once
	first   sync.Once
}

func newStartupTUN(device tun.Device) *startupTUN {
	return &startupTUN{Device: device, ready: make(chan struct{})}
}

func (t *startupTUN) start() {
	t.release.Do(func() { close(t.ready) })
}

func (t *startupTUN) Read(packets [][]byte, sizes []int, offset int) (int, error) {
	first := false
	t.first.Do(func() {
		<-t.ready
		first = true
	})
	if first {
		return 0, nil
	}
	return t.Device.Read(packets, sizes, offset)
}

func (t *startupTUN) Close() error {
	// Also release Read if configuration or device startup failed.
	t.start()
	return t.Device.Close()
}
