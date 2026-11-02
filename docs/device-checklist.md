# Physical-Device Verification

Run with a signed Moley build on a real iPhone and your configured AWS server.
Nothing below is claimed to have passed simply because the simulator builds.

## Setup and Secrets

- [ ] Both app and extension profiles include Network Extension and shared
      Keychain entitlements with the same team prefix and group.
- [ ] Install, import a unique valid profile, allow the iOS VPN prompt.
- [ ] Cancel the VPN permission prompt: no usable half-installed profile remains.
- [ ] Kill/relaunch the app: saved profile and system status are restored.
- [ ] Import with Files and explicit paste. Oversized/invalid files fail clearly.
- [ ] Reject missing IPv6 defaults, DNS, malformed keys, and server shell hooks.
- [ ] Revealed keys are hidden when backgrounding; delivery copies are removed.

## Connectivity

- [ ] Connect: server `wg show` and app report a recent handshake.
- [ ] External IPv4 matches the AWS Elastic IP.
- [ ] IPv6 does not expose the original network address; for the starter
      deployment, IPv6-only destinations fail and dual-stack sites use IPv4.
- [ ] DNS queries use the configured resolver via the tunnel.
- [ ] HTTPS websites work, including required family websites.
- [ ] VPN peers cannot reach metadata, VPC/internal services, other peers, or
      server administration ports, including through its public IP.
- [ ] Wi-Fi to cellular and back recovers; test weak signal and airplane mode.
- [ ] Lock/unlock, sleep, app termination, and server reboot recover correctly.
- [ ] Reboot iPhone: test first unlock before automatic connection.
- [ ] Unreachable server, wrong public key, blocked UDP and DNS failure do not
      falsely show a successful server handshake.
- [ ] No traffic works through a stale tunnel even though iOS says connected;
      UI reports missing/stale handshake rather than promising working internet.

## Lifecycle and UX

- [ ] On-demand is off by default; enabling requires confirmation.
- [ ] Manual Disconnect disables on-demand and does not immediately reconnect.
- [ ] Disconnect/change profile quickly; double-taps do not cause duplicate saves.
- [ ] Replace/remove is blocked while active or on-demand is enabled.
- [ ] Failed replacement preserves the previous working profile.
- [ ] Removal deletes the system profile and Keychain entry; server revocation is
      separately performed and verified.
- [ ] Changing VPN status in Settings is reflected when returning to Moley.
- [ ] VoiceOver, large text, dark mode, iPad rotation and narrow screens work.
- [ ] Simulator UI test runs on a fresh simulator without a pre-existing profile.

## Release

- [ ] Audit pinned WireGuard/Go dependencies and licenses; update as necessary.
- [ ] Review the included app icon and add support/privacy information.
- [ ] Complete Apple VPN-app eligibility, signing, encryption/export, privacy
      disclosures and review requirements for the chosen distribution channel.
- [ ] Configure AWS budget alarms, patching, peer revocation and secure key backup.
- [ ] Decide how expired TestFlight/ad-hoc builds will be renewed.
