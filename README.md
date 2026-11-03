# Moley for iPhone

A native SwiftUI client that connects your family's devices to your own US
AmneziaWG server. Requires iOS 17 or later. Also supports iPad layouts.

## What's implemented

- AmneziaWG packet tunnel using Apple's Network Extension, the WireGuardKit
  adapter, and pinned `amneziawg-go v3.1.20260828`.
- Validated junk/padding/header/signature settings and optional AWG 3 header
  protection. Legacy WireGuard profiles are explicitly labeled unobfuscated.
- Import from Files or an explicit paste action, with strict validation.
- One profile per device; private configuration stored in a shared, device-only
  Keychain item, accessible after the first unlock following a reboot.
- Connect/disconnect, opt-in on-demand connection, replacement and removal.
- Real system VPN status plus a separate server-handshake indicator.
- Unit tests and a simulator UI smoke test.

There is no server deployed, account backend, browser proxy, subscription, or
analytics. AWS egress addresses are not guaranteed to be accepted by every
website; services may block VPNs or data-center IPs. Use in accordance with local
law and service terms. AmneziaWG changes recognizable packet patterns, but still
uses UDP and can be detected or blocked. No censorship-resistance guarantee is made.

## Build and Run

1. Install Xcode with an iOS SDK and Go 1.25 or newer. The checked-in Xcode project is ready to
   open; Ruby is only needed when regenerating it after adding source files.
2. Create `Config/Local.xcconfig` using `Config/Local.xcconfig.example` as a guide.
   Choose your unique bundle prefix, Apple development team, and the directory
   containing the `go` executable.
3. Open `Moley.xcodeproj`, select the `Moley` scheme and a physical iPhone.
4. Enable Network Extensions (Packet Tunnel) and Keychain Sharing for **both**
   app IDs (`YOUR_BUNDLE_ID` and `YOUR_BUNDLE_ID.tunnel`) in your paid Apple
   Developer team. Both use the same keychain group
   `$(AppIdentifierPrefix)$(MOLEY_BUNDLE_ID).shared`.
5. Let Xcode provision both targets.
   Build and run, import the device's configuration, allow iOS to add the VPN,
   then tap Connect.

WireGuardKit's Swift/C sources are vendored at a pinned revision and compiled
directly, with no Swift package resolution required. See
`Vendor/WireGuard/UPSTREAM.md` and `COPYING` for provenance and licensing.
The bridge target compiles the real AmneziaWG Go backend, including upstream's
sleep-aware runtime patch. Its first build downloads Go modules and copies the
Go runtime into DerivedData. It does not modify your installed Go runtime.
Dependency revisions are pinned; review upstream and transitive dependency
security updates before distributing production builds.

### Simulator and Tests

The simulator can exercise UI and parsing, but **cannot validate a real VPN**.
Use a fresh simulator with no Moley profile for the UI test.

```bash
xcodebuild -project Moley.xcodeproj -scheme Moley \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/moley-build CODE_SIGNING_ALLOWED=NO build

xcodebuild -project Moley.xcodeproj -scheme Moley \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -derivedDataPath /tmp/moley-build -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO test
```

Set `MOLEY_GO_BIN=/path/to/go/bin` on the command line if Go is not installed in
`/opt/homebrew/bin`. Replace the simulator name with one installed on your Mac.
Build intermediates, including the isolated Go runtime, are stored in DerivedData.

To regenerate the project (the generator and generated project are both source):

```bash
gem install --user-install xcodeproj
ruby scripts/generate-project.rb
```

### Verified Locally

On 2026-11-03 with Xcode 27.1 and Go 1.26.2:

- Simulator app built; 29 unit tests and 1 setup UI test passed.
- Unsigned physical-iPhone app and packet tunnel extension built successfully.
- Four local Go peer-exchange scenarios passed, including first-packet padding
  and AWG 3 header protection, repeated under the race detector.
- Four private-settings generator tests passed.

Signing, shared-Keychain access on a real device, live AWS connectivity, DNS/IPv6
behavior, and sleep/on-demand recovery still require the physical-device checklist.

## Connect the Family

Follow [the AWS setup guide](docs/aws-wireguard.md). Generate a separate private
key and tunnel address for every device. Share the file privately, import it,
then delete the delivery copies. Removing a profile from the app does not revoke
the server peer; remove that peer on AWS as well.

Read [supported AmneziaWG settings and migration notes](docs/amneziawg.md).
Other devices need compatible AmneziaWG clients for obfuscated profiles; plain
WireGuard clients cannot connect to this server configuration.
For future **browser-only** access, see [the architecture notes](docs/architecture.md).
A normal browser page cannot become a device-wide VPN.

## Security Boundaries

- Imports require IPv4 and IPv6 default routes, interface addresses for both
  families, and explicit DNS. Split tunneling and shell hooks are rejected.
- Obfuscation settings must match the server. Moley never silently retries an
  AmneziaWG profile using plain WireGuard. Installing the new app alone does not
  upgrade old profiles or the server.
- This is **not** a guaranteed always-on VPN or kill switch. Normal connectivity
  resumes after disconnect. iOS may exempt system traffic. On-demand is a
  convenience, not a fail-closed security guarantee.
- WireGuard encrypts traffic to AWS, not from AWS to every website. Use HTTPS.
  Your server and chosen DNS resolver can observe connection metadata.
- Keys are never sent to an enrollment API or put in VPN provider settings.
  `passwordReference` contains only a persistent Keychain reference.
- The extension returns only handshake time and byte counts, never raw runtime
  configuration (which includes secrets).
- Revealed configuration is hidden when the app becomes inactive. This does not
  prevent deliberate screenshots, third-party keyboards, or copies outside Moley.
- There is no app-specific usage logging, but iOS and upstream dependencies may
  produce system diagnostics. Do not distribute diagnostics without review.

## Before Family Distribution

Use [the device verification checklist](docs/device-checklist.md). A simulator
build is not a substitute for signing, a real AWS server, or physical-device
tests. Review the included app icon, add a privacy policy/support contact, and complete
Apple's current VPN-app and encryption/export requirements before App Store or
TestFlight submission. Apple may require an organization enrollment for public
VPN app distribution; verify the current rules. TestFlight builds expire after
90 days, so plan ongoing distribution and maintenance.
