# Upstream Provenance

Source: https://git.zx2c4.com/wireguard-apple

Revision: `2fec12a6e1f6e3460b6ee483aa00ad29cddadab1` (tag `1.0.16-27`).

Only `Sources/WireGuardKit`, `Sources/WireGuardKitC`, `Sources/WireGuardKitGo`,
`Package.swift`, and `COPYING` are included. The MIT license is in `COPYING`.

Local changes:

- Change the manifest's Swift tools version from 5.3 to 5.5, the minimum needed
  for its `.macOS(.v12)` and `.iOS(.v15)` platform declarations.
- Include `<sys/types.h>` in `WireGuardKitC.h` so its BSD integer types are
  self-contained when building explicit Clang modules with current Xcode.
- Add validated AmneziaWG settings to `InterfaceConfiguration`, include them
  in equality, and serialize them in device scope before any peer UAPI fields.
- Replace the original WireGuard Go module with
  `github.com/amnezia-vpn/amneziawg-go/v3 v3.1.20260828`, upstream revision
  `b5928efb6ca19f0153958460c3d141f04abc5c2e`. Source:
  https://github.com/amnezia-vpn/amneziawg-go . Its license is included as
  `AMNEZIAWG-LICENSE`; dependencies/checksums are pinned in `go.mod`/`go.sum`.
- Link the AmneziaWG backend through the local C bridge. Update version reporting,
  close the device on initialization failure, check `Up()` errors, and bound
  stack-dump writes.
- Extend the local `wgTurnOn` ABI with a session duration and add
  `wgSetSessionDuration`. The adapter reads the persisted remaining lifetime at
  startup and network recovery; `session_bind.go` gates every outgoing datagram
  using the sleep-aware monotonic clock. Explicit extensions refresh that deadline.
  The Swift adapter and bridge header must be built together.
- Add `startup_tun.go` to prevent the initial read from using a stale zero S4
  padding offset before configuration. Its behavior is covered by
  `amnezia_test.go` using real loopback UDP and in-memory TUN devices.
- Rebuild archives when bridge Go sources/checksums change and isolate patched
  GOROOT directories by installed Go version.

Moley compiles these sources directly with its native targets and bridging
header, like the upstream application, rather than resolving a Swift package.

The Go bridge has transitive dependencies recorded in `go.mod` and `go.sum`.
Review their licenses and security updates before release. Moley's configuration
parser and UI are independent of the upstream WireGuard app.

The native AmneziaWG Apple integration was consulted for backend API
compatibility at revision `9d5ee60edefa95b933a738dd7cda671dd18021fc`:
https://github.com/amnezia-vpn/amneziawg-apple . Moley does not import that app's
Xray integration or unrelated dependencies. The on-disk WireGuard directory and
C symbols are retained to avoid unnecessary Xcode/signing changes; the linked
Go packet engine is AmneziaWG.
