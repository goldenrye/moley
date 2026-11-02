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

Moley compiles these sources directly with its native targets and bridging
header, like the upstream application, rather than resolving a Swift package.

The Go bridge has transitive dependencies recorded in `go.mod` and `go.sum`.
Review their licenses and security updates before release. Moley's configuration
parser and UI are independent of the upstream WireGuard app.
