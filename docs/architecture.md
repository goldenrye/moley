# Architecture and Future Browser Mode

## Current Native Client

```text
SwiftUI app
  | NETunnelProviderManager: install / start / stop / on-demand
  | Keychain persistent reference (never raw keys in VPN preferences)
  v
PacketTunnelProvider
  | reads its profile from shared Keychain
  | starts WireGuardKit adapter + pinned amneziawg-go
  v
iOS packet tunnel -- obfuscated encrypted UDP --> AWS US AmneziaWG gateway
                                         |
                                         +-- public internet via IPv4 NAT
                                         +-- private/VPC/metadata access denied
                                         +-- IPv6 rejected in starter setup
```

- `App/`: user interface and system VPN lifecycle. One saved Moley profile.
- `Shared/WireGuardProfile.swift`: strict, non-executable AmneziaWG/WireGuard
  client format, including bounded padding, ranges and signature validation.
- `Shared/ProfileKeychain.swift`: device-only secret storage and persistent refs.
- `Shared/TunnelHealth.swift`: allowlisted runtime diagnostics with no secrets.
- `Tunnel/`: network extension. The tunnel runs independently of the app process.
- `Vendor/WireGuard/`: upstream Swift/C/Go library sources, license and revision.
- `scripts/`: project regeneration and native Go bridge build.

The iOS routing state is not a connectivity test. The UI calls it "Tunnel active"
and separately reports the last WireGuard handshake. Neither proves access to a
particular website. We deliberately avoid an unsolicited third-party IP-check
request. A future self-hosted HTTPS connectivity endpoint could verify egress.

There is currently no enrollment API, login, server inventory, certificate
infrastructure, or family member database. Profiles are provisioned manually.
This keeps VPN keys independent from any eventual web application.

AmneziaWG settings reach the backend as device-level UAPI fields; they are not
HTTP/TLS wrappers. The adapter retains these settings on network-change restarts.
The startup TUN wrapper prevents the first IP packet from using an old padding
offset. Legacy WireGuard configurations are explicitly labeled unobfuscated;
there is no automatic fallback from a failed AmneziaWG connection to WireGuard.
See [the protocol notes](amneziawg.md) for supported versions and boundaries.

## Non-iPhone Family Members Today

Android, Windows, macOS, and Linux can use compatible AmneziaWG clients against
the same gateway, each with a unique key and address and matching obfuscation
settings. Standard WireGuard clients only work with an unobfuscated WireGuard
server profile. Other devices do not need a custom
Moley port to get access. This is the simplest near-term cross-platform path.

## Browser-Only Access Later

A website cannot install device routes or turn its browser into a general UDP
WireGuard client. WebSocket or WebRTC availability does not change that routing
restriction. Choose a separate browser experience:

### Recommended: Authenticated Remote Browser

Run a browser in an isolated session on US infrastructure and stream its screen
and input over HTTPS/WebSocket/WebRTC to the family's browser. The remote
browser's requests originate in the US. Existing remote-desktop/browser systems
can provide this transport; evaluate maintained options before implementation.

```text
Family web browser -- HTTPS + strong login --> session gateway
                                                |
                                    isolated browser per session
                                                |
                                         US internet egress
```

This works without installing a native VPN but only affects browsing inside that
remote session. It costs more CPU/RAM, adds latency, and may not support all
video, DRM, passkey, download, or accessibility flows. Personal credentials,
cookies, and page contents live on your infrastructure.

Required before exposing it:

- MFA or passkeys, invite-only accounts, session expiry, rate limits and quotas.
- Separate hardened containers or VMs per user/session, no privileged mounts,
  no AWS instance credentials, and prompt browser/OS security updates.
- Server-side egress deny rules for private networks, metadata, loopback,
  link-local, IPv6 equivalents and other sessions; defend against DNS rebinding.
- Authenticated, origin-checked streaming connections; short-lived session tokens
  scoped to one browser session, never WireGuard private keys.
- Explicit download/clipboard policy and lifecycle for cookies/profile storage.
- Resource limits, idle shutdown, cost alarms, and an operational update plan.

Do not put this browser service in an unrestricted trust relationship with the
VPN server. Prefer separate instances/subnets/security groups. They may share
family enrollment identity later, but not transport credentials.

### Not Recommended: Arbitrary URL-Rewriting Proxy

Fetching a URL on AWS and rewriting the HTML breaks many modern sites: cookies,
CSP, CORS, authentication redirects, WebSockets, service workers and subresources
all need careful handling. It can become an SSRF/open-proxy vulnerability and
puts the proxy operator in the middle of sensitive content. It is not an
equivalent general-purpose replacement for this VPN.

## Possible Enrollment Upgrade

When manual files become inconvenient, add a small authenticated control plane:
the phone generates its private key locally, submits only the public key with a
one-time invitation, and receives its address, server public key, endpoint and
DNS and versioned AmneziaWG settings. The server allocates unique peer addresses
and supports revocation. Shared header-protection keys need private delivery and
coordinated rotation, distinct from each device's private WireGuard key.
Use HTTPS, replay-resistant invitations, authorization, and audit events without
secret payloads. Do not reuse remote-browser session tokens as VPN keys.

These are future architecture boundaries, not implemented browser/enrollment
features in this version.
