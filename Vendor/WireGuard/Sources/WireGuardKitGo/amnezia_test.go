package main

import (
	"bytes"
	"crypto/ecdh"
	"crypto/rand"
	"encoding/binary"
	"encoding/hex"
	"fmt"
	"net/netip"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/amnezia-vpn/amneziawg-go/v3/conn"
	"github.com/amnezia-vpn/amneziawg-go/v3/device"
	"github.com/amnezia-vpn/amneziawg-go/v3/tun/tuntest"
)

// Use the same UDP bind as the Apple bridge, with in-memory TUNs (no root or VPN
// entitlements). Capture ciphertext to prove the obfuscation reaches the wire.
type recordingBind struct {
	conn.Bind
	mu      sync.Mutex
	packets [][]byte
}

func (b *recordingBind) Send(packets [][]byte, endpoint conn.Endpoint) error {
	b.mu.Lock()
	for _, packet := range packets {
		b.packets = append(b.packets, append([]byte(nil), packet...))
	}
	b.mu.Unlock()
	return b.Bind.Send(packets, endpoint)
}

func TestAmneziaPeerRoundTrip(t *testing.T) {
	const settings = "jc=4\njmin=40\njmax=80\ns1=32\ns2=48\ns3=16\ns4=16\n" +
		"h1=100001-100010\nh2=200001-200010\nh3=300001-300010\nh4=400001-400010\n" +
		"i1=<b 0xaabb><r 10><rd 5><rc 5><t>\n"
	for _, mode := range []struct {
		name     string
		settings string
		padding  int
		header   uint32
	}{
		{"legacy_wireguard", "", 0, 1},
		{"amnezia_v1", "jc=4\njmin=40\njmax=80\ns1=32\ns2=48\nh1=100001\nh2=200001\nh3=300001\nh4=400001\n", 32, 100001},
		{"amnezia_ranges_and_signatures", settings, 32, 100001},
		{"amnezia_header_protection", settings + "header_protection_key=" + strings.Repeat("ab", 32) + "\ncontent_padding_addition=16-32\n", 32, 0},
	} {
		t.Run(mode.name, func(t *testing.T) {
			var keys [2]*ecdh.PrivateKey
			var devices [2]*device.Device
			var tuns [2]*tuntest.ChannelTUN
			var binds [2]*recordingBind
			var ports [2]string
			for i := range keys {
				var err error
				keys[i], err = ecdh.X25519().GenerateKey(rand.Reader)
				if err != nil {
					t.Fatal(err)
				}
			}
			for i := range devices {
				tuns[i] = tuntest.NewChannelTUN()
				binds[i] = &recordingBind{Bind: conn.NewStdNetBind()}
				gatedTUN := newStartupTUN(tuns[i].TUN())
				devices[i] = device.NewDevice(gatedTUN, binds[i], device.NewLogger(device.LogLevelSilent, ""))
				t.Cleanup(devices[i].Close)
				config := mode.settings + fmt.Sprintf(
					"private_key=%s\nlisten_port=0\nreplace_peers=true\npublic_key=%s\nallowed_ip=10.66.66.%d/32\n",
					hex.EncodeToString(keys[i].Bytes()), hex.EncodeToString(keys[1-i].PublicKey().Bytes()), 3-i)
				if err := devices[i].IpcSet(config); err != nil {
					t.Fatalf("backend rejected %s configuration: %v", mode.name, err)
				}
				if err := devices[i].Up(); err != nil {
					t.Fatal(err)
				}
				gatedTUN.start()
				runtime, err := devices[i].IpcGet()
				if err != nil {
					t.Fatal(err)
				}
				for _, line := range strings.Split(runtime, "\n") {
					if strings.HasPrefix(line, "listen_port=") {
						ports[i] = strings.TrimPrefix(line, "listen_port=")
					}
				}
				if ports[i] == "" || ports[i] == "0" {
					t.Fatal("UDP socket did not bind")
				}
			}
			for i := range devices {
				config := fmt.Sprintf("public_key=%s\nendpoint=127.0.0.1:%s\n",
					hex.EncodeToString(keys[1-i].PublicKey().Bytes()), ports[1-i])
				if err := devices[i].IpcSet(config); err != nil {
					t.Fatal(err)
				}
			}
			for i := range devices {
				source := netip.MustParseAddr(fmt.Sprintf("10.66.66.%d", i+2))
				destination := netip.MustParseAddr(fmt.Sprintf("10.66.66.%d", 3-i))
				packet := tuntest.Ping(destination, source)
				select {
				case tuns[i].Outbound <- packet:
				case <-time.After(5 * time.Second):
					t.Fatal("TUN write timed out")
				}
				select {
				case received := <-tuns[1-i].Inbound:
					if !bytes.Equal(received, packet) {
						t.Fatal("decrypted packet differs")
					}
				case <-time.After(5 * time.Second):
					binds[i].mu.Lock()
					for _, sent := range binds[i].packets {
						t.Logf("sent UDP packet size: %d", len(sent))
					}
					binds[i].mu.Unlock()
					t.Fatal("encrypted round trip timed out")
				}
			}
			binds[0].mu.Lock()
			defer binds[0].mu.Unlock()
			foundHandshake := false
			for _, packet := range binds[0].packets {
				if len(packet) != 148+mode.padding {
					continue
				}
				header := binary.LittleEndian.Uint32(packet[mode.padding:])
				if mode.header == 0 || (header >= mode.header && header <= mode.header+9) {
					foundHandshake = true
				}
			}
			if !foundHandshake {
				t.Fatal("expected padded handshake/header was not sent")
			}
		})
	}
}
