# TestFlight Test Information

Copy each field into App Store Connect → Moley → TestFlight. Fields marked
**(external)** are needed only for external testing groups, which go through
Beta App Review.

## Test Information (App Information)

### Beta App Description (external)

```text
Moley is a tiny private tunnel to a server you own. It connects your family's iPhones and iPads to your own WireGuard server so they can browse the open web smoothly and safely wherever they are.

There are no shared servers, no accounts, no analytics, and no logs you don't control. Each family member imports a personal WireGuard configuration provided by the server administrator. Moley stores the private key in the device Keychain and uses Apple's Network Extension with the official WireGuard implementation.

Features in this beta:
- Import a personal configuration from Files or by pasting it
- Connect and disconnect with one tap
- Optional automatic reconnection on Wi-Fi and cellular
- Live VPN status plus a separate server-handshake indicator, so you can tell when the server is really reachable
- Replace or remove the configuration on this device

Moley requires a WireGuard server operated by you or your family administrator. It does not provide servers.
```

### Feedback Email

```text
jianwpi@gmail.com
```

### Marketing URL (optional)

Leave blank, or use the project's homepage if you publish one.

### Privacy Policy URL (external)

You need a public page. A short policy is enough. Suggested text to host (for example as a GitHub Pages or Gist page):

```text
Moley Privacy Policy

Moley does not collect, store, or transmit any personal data to the developer. There is no account, analytics, advertising, or tracking.

Your WireGuard configuration, including its private key, is stored only in this device's Keychain. Network traffic is sent through an encrypted WireGuard tunnel to the server named in your configuration, which is operated by you or your family administrator, not by the Moley developer. That server operator and the DNS provider in your configuration can see connection metadata.

Contact: jianwpi@gmail.com
```

## Build: What to Test

Shown to every tester when they install the build (internal and external).

```text
Thanks for testing Moley!

Before you start: ask your family administrator for your personal WireGuard .conf file. Each device needs its own file. Don't share it.

Please try:
1. Tap "Set up Moley" and import your configuration: "Choose configuration file", or copy the text and tap Paste. Then tap "Save configuration". Allow iOS to add the VPN configuration when asked.
2. Tap Connect. Within a few seconds the app should show "Tunnel active" and a recent server handshake.
3. Open Safari and visit a few sites you use every day. Check that they load normally.
4. Switch between Wi-Fi and cellular, lock the phone for a few minutes, then come back. Does the connection recover?
5. Optional: turn on "Connect automatically", then tap Disconnect and confirm it stays off.

Please report:
- Sites or apps that don't work while connected
- Times the app says "Tunnel active" but nothing loads, or the handshake looks stale
- Anything confusing in the setup or wording

Send feedback with a screenshot from TestFlight (take a screenshot, then tap Share Beta Feedback) or email jianwpi@gmail.com.
```

## Beta App Review Information (external)

### Contact Information

- First name / Last name: your name
- Phone: your phone number
- Email: jianwpi@gmail.com

### Sign-in required

**No.** Moley has no account or login.

### Review Notes

The reviewer needs a working configuration. Create a dedicated reviewer peer on
the server (its own key and tunnel address), paste its configuration into the
notes below, and revoke that peer after the build is approved.

```text
Moley is a personal VPN client for a family-operated WireGuard server. There is no account or login; access is granted by importing a WireGuard configuration issued by the server owner.

To test:
1. Copy the configuration below (from [Interface] to the end).
2. Open Moley, tap "Set up Moley", tap Paste, then tap "Save configuration". Allow iOS to add the VPN configuration.
3. Tap Connect. The app shows "Tunnel active" and a recent server handshake. Browsing in Safari then goes through the test server (located in the US).

This configuration is a temporary key created only for App Review and will be revoked after review.

Moley does not offer a public VPN service, sell subscriptions, collect user data, or include analytics. The tunnel uses the official WireGuard implementation via NEPacketTunnelProvider. Each user's private key stays in the device Keychain.

--- Reviewer configuration ---
<paste reviewer .conf here>
```

## Export Compliance

When the build shows **Missing Compliance**, answer that the app uses only
standard encryption algorithms (WireGuard: ChaCha20-Poly1305, Curve25519) and
qualifies for the exemption. To skip the question on future builds, add
`ITSAppUsesNonExemptEncryption` = `NO` to `Config/App-Info.plist`.
