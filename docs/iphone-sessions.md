# iPhone Session Limits

Moley now starts a **30-minute session** when the user taps Connect. Setup time
counts toward the limit; failed handshakes do not reset it.

- A local notification is scheduled for minute 25, with **Extend 30 minutes**
  and **Disconnect now** actions. Actions open Moley; extending requires unlocking
  the phone. Merely opening or dismissing the reminder never extends access.
- Without an explicit extension, the session expires at minute 30.
- Extend adds 30 minutes to the existing deadline and moves the reminder to five
  minutes before that new deadline. Old or duplicate notification actions cannot
  renew a different session or apply an extension twice.
- The home screen shows the remaining time and an Extend button.
- Denying notifications does not disable expiry. Focus and iOS notification
  delivery policies can delay or hide the reminder.
- Reconnection is off by default. It can be enabled only during an active
  session, and never grants a new deadline. After expiry, open Moley and explicitly
  start another session. Starting a new session turns reconnection off again.
- Existing profiles without a session cannot start the new extension. Opening
  Moley disables legacy unrestricted on-demand settings and stops such a tunnel.

## Enforcement

Each explicit start creates a new device-only, shared Keychain record. VPN
preferences contain its persistent reference, not its contents. The app is the
only writer of extensions; stopping from iOS Settings can delete that specific
session record without affecting a newer one.

The record contains both an absolute deadline and a `mach_continuous_time`
deadline. The smaller remaining duration wins: moving the wall clock backward
does not extend the session, and device sleep counts toward elapsed time.
Missing, unreadable, corrupt, expired or reset-clock records are refused.
Both clocks are local, not a tamper-proof remote clock.

The tunnel extension checks the persisted deadline at start, on wake/sleep,
on app messages and approximately once a second while running. It stops the
backend and asks iOS to end the tunnel when the lease expires or is revoked.
Network-triggered backend restarts check the original persisted deadline again.

There is also a Go bind-level gate on **all outbound AmneziaWG datagrams**,
including handshakes, junk, cookies, keepalives and data. It uses the existing
sleep-aware Go runtime and a monotonic deadline. This prevents delayed extension
timer callbacks from continuing to submit new VPN datagrams after expiry.
The Swift/C deadline conversion reserves 100 milliseconds to avoid rounding up,
so transmission can stop fractionally before the displayed deadline.

iOS may retain an on-demand rule while the app is closed, but the extension
refuses expired starts before creating the backend. Opening the app clears those
rules. A currently executing socket write or data already queued by the OS cannot
be recalled; this is not a hard-real-time guarantee.

Once iOS removes the tunnel routes, traffic uses the normal network. This is a
short-session convenience, **not a kill switch or a censorship-safety threshold**.
It does not guarantee that a connection cannot be detected.

No AWS deployment, Android timeout, account service, push-notification server,
or server-side expiry is part of this change.

## Verification

Automated coverage includes exact expiry/reminder boundaries, explicit extension,
stale/duplicate actions, persistence, clock rollback/reset, notification payloads,
and packet gating. Real loopback AmneziaWG peers exchange IP packets while their
leases are valid and stop sending them after revocation.

Before distributing, use a signed physical iPhone and a controlled server:

- Leave Moley in the background, lock the phone, and verify the minute-25
  reminder and minute-30 local shutdown without touching the app.
- Repeat with notifications denied, Focus enabled and the app force-closed.
- Capture traffic at the phone's network or server to check for ongoing
  keepalives/handshake attempts after expiry. A VPN icon alone is not sufficient.
- Extend from the lock screen and in the app; check the new deadline and reminder.
  Tap a stale reminder after a newer session starts; it must not affect it.
- Cross the deadline in airplane mode or deep sleep, then restore connectivity.
  There must be no automatic renewal or fresh AmneziaWG handshake.
- Toggle Wi-Fi/cellular repeatedly, enable session reconnection, and restart the
  extension. The original deadline must remain in force.
- Stop from Settings while a reminder/extension is being processed. The old
  session must not restart or schedule a new reminder.
- Test an old installation with on-demand enabled, and reboot/first-unlock
  behavior. Unreadable or missing leases must fail closed.

Simulator and host tests cannot establish iOS background scheduling, signed
shared-Keychain access, actual notification delivery or filtering resistance.
