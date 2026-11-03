# AmneziaWG Profiles

Moley's Apple adapter uses the pinned MIT-licensed
`github.com/amnezia-vpn/amneziawg-go/v3 v3.1.20260828` backend. This is a real
transport change, not padding applied to the configuration file or a cosmetic
protocol label. The existing WireGuard encryption/key format remains in use.

## Supported Settings

Place these in the `[Interface]` section of a standard `.conf` file:

| Setting | Moley accepts | Purpose |
| --- | --- | --- |
| Jc | 0-32 | Junk packets before each handshake |
| Jmin, Jmax | 0-1280, minimum <= maximum | Junk packet sizes; minimum must be positive when Jc > 0 |
| S1, S2 | 0-1024 | Initiation and response padding |
| S3 | 0-1024; defaults to 0 | Cookie-response padding |
| S4 | 0-128; defaults to 0 | Transport packet padding |
| H1-H4 | uint32 values or inclusive `low-high` ranges | Message headers; must be >= 5 and mutually non-overlapping |
| I1-I5 | Optional tag sequences, 1-1280 output bytes each | Packets sent before the handshake |
| HeaderProtectionKey | Optional nonzero base64 32-byte key | AWG 3 header protection; requires every S1-S4 >= 12 |
| ContentPaddingAddition | Optional value/range, 0-128 | AWG 3 additional encrypted content padding |

When any AmneziaWG field is present, **Jc, Jmin, Jmax, S1, S2 and H1-H4 are all
required**. Partial configurations are rejected, not silently interpreted as
ordinary WireGuard. Headers 0-4 are rejected to avoid retaining WireGuard's
standard message IDs. `S1 + 148` must differ from `S2 + 92` for older server
compatibility.

Signature tags supported by the importer:

- `<b 0xAABB>`: literal hex bytes; nonempty, even length.
- `<r 32>`: random bytes.
- `<rd 8>`: random digit bytes.
- `<rc 8>`: random letter bytes.
- `<t>`: four-byte timestamp.

For example, `<b 0xAABB><r 32><t>` produces 38 bytes. No executable commands,
unknown tags, or text outside tags are allowed. These packets are not a promise
that the connection convincingly implements TLS or any other protocol.

Moley deliberately limits imports more strictly than the backend. It rejects
unbounded allocations, oversized signatures, duplicate scalar settings, and
MTU + worst-case padding + overhead above a 1500-byte budget. Use **MTU 1280**
with the provided generator. Smaller real path MTUs may still need adjustment.
Both IP families and explicit DNS remain mandatory.

The current importer does **not** support custom AWG 3 timing fields,
`RandomTrailers`, `DisableCookies`, data-embedding signature tags, tunneled
proxies, or the Amnezia app's compressed `vpn://` invitations. Export a supported
plain-text `.conf` file. Unknown fields cause an error rather than being dropped.

## Compatibility and Migration

- Scalar H1-H4 with S3/S4 absent supports original AmneziaWG-compatible profiles.
- Ranged headers, S3/S4 and I1-I5 require a server/client version supporting those
  features. HeaderProtectionKey/ContentPaddingAddition require AWG 3.
- S1-S4, H1-H4 and HeaderProtectionKey must match the server. Junk/signature
  settings and content padding may differ, but begin with a copied shared block.
- Existing plain WireGuard files remain usable and are explicitly labeled
  **WireGuard (unobfuscated)**. They are not automatically upgraded.
- There is no automatic protocol fallback. A mismatched AmneziaWG profile must
  fail to handshake, not retry using standard WireGuard.
- Keep the same app/extension bundle IDs when upgrading so existing Keychain
  references and VPN preferences remain accessible.
- Disconnect and disable on-demand before replacing the configuration. Upgrade
  the server separately using [the AWS guide](aws-wireguard.md).

Generate a private AWG 3 shared block with:

```bash
python3 scripts/generate_amnezia_settings.py /existing/private/directory/awg-shared.conf
```

The file is created with mode 0600 and must not already exist. Copy the whole
block into `[Interface]` on the server and every device. Keep separate device
private/public keys and preshared keys. If HeaderProtectionKey is compromised,
coordinate its rotation across all peers. Never upload the shared block to git.

## Implementation and Verification

The importer validates fields, converts the header key to UAPI hex, and attaches
the resulting settings to `InterfaceConfiguration`. The settings generator
serializes them **before** the first peer's `public_key` line. They remain on the
configuration object for adapter restarts after network changes. Endpoint-only
updates do not reset them.

The Go bridge delays the first real TUN read until configuration has been
applied, then forces the backend to recalculate its S4 offset. Without this
startup barrier, a first IP packet can be read with zero padding before IpcSet
and dropped by a correctly configured peer. Error paths release the barrier and
close the whole device, including its goroutines and duplicated TUN descriptor.

Only handshake timestamps and byte counters leave the extension through the
health message. Raw UAPI output, signatures, and header-protection keys do not.
The preferences display label contains no obfuscation settings or keys.

The Go tests create two actual backend peers with loopback UDP sockets and
in-memory TUNs, exchange encrypted IP packets in both directions, and inspect
handshake sizes/headers. They exercise the same startup wrapper as the Apple
bridge, including S4 and AWG 3 header protection:

```bash
go -C Vendor/WireGuard/Sources/WireGuardKitGo test -race -count=3 -v ./...
python3 -B -m unittest discover -s scripts -p 'test_*.py' -v
```

This proves local backend behavior, not resistance to China's filtering or
real-device routing. AmneziaWG still uses UDP and cannot hide a blocked AWS IP,
guarantee access, or replace physical-device testing. Use the
[device checklist](device-checklist.md) for Wi-Fi/cellular changes, sleep, DNS,
IPv6, and server-side validation.
