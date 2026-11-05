import NetworkExtension
import os
import UserNotifications

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private let logger = Logger(subsystem: "Moley", category: "Tunnel")
    private let control = DispatchQueue(label: "Moley.SessionControl")
    private var adapter: WireGuardAdapter?
    private var timer: DispatchSourceTimer?
    private var reference: Data?
    private var lease: TunnelSession?
    private var stopping = false

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        control.async { self.start(completionHandler) }
    }

    private func start(_ completionHandler: @escaping (Error?) -> Void) {
        do {
            guard let settings = protocolConfiguration as? NETunnelProviderProtocol,
                  let profileReference = settings.passwordReference,
                  let reference = settings.providerConfiguration?["sessionReference"] as? Data else {
                throw ProfileError(message: "Open Moley and start a new 30-minute session.")
            }
            let lease = try SessionStore.read(reference)
            guard lease.remaining(at: .now) > 0 else {
                throw ProfileError(message: "Session expired. Open Moley to start another 30 minutes.")
            }
            self.reference = reference
            self.lease = lease
            stopping = false
            let profile = try WireGuardProfile(text: ProfileKeychain.read(profileReference))
            let adapter = WireGuardAdapter(with: self, sessionTimeRemaining: {
                (try? SessionStore.read(reference).remaining(at: .now)) ?? 0
            }) { [weak self] level, _ in
                if level == .error { self?.logger.error("AmneziaWG reported a backend error.") }
            }
            self.adapter = adapter
            adapter.start(tunnelConfiguration: profile.configuration) { error in
                self.control.async {
                    guard error == nil, !self.stopping else {
                        self.adapter?.stop { _ in }
                        completionHandler(ProfileError(message: "The tunnel could not start. Check your session, network and profile."))
                        return
                    }
                    guard self.checkSession() else {
                        completionHandler(ProfileError(message: "Session expired while connecting."))
                        return
                    }
                    let timer = DispatchSource.makeTimerSource(queue: self.control)
                    timer.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(100))
                    timer.setEventHandler { [weak self] in _ = self?.checkSession() }
                    self.timer = timer
                    timer.resume()
                    completionHandler(nil)
                }
            }
        } catch {
            completionHandler(error)
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        control.async {
            self.stopping = true
            self.timer?.cancel()
            self.timer = nil
            if reason == .userInitiated, let reference = self.reference {
                if let latest = try? SessionStore.read(reference), latest.id == self.lease?.id {
                    self.lease = latest
                }
                self.clearReminder()
                try? ProfileKeychain.delete(reference)
            } else if (self.lease?.remaining(at: .now) ?? 0) <= 0 {
                self.clearReminder()
            }
            guard let adapter = self.adapter else { completionHandler(); return }
            adapter.stop { _ in completionHandler() }
        }
    }

    override func wake() {
        control.async { _ = self.checkSession() }
    }

    override func sleep(completionHandler: @escaping () -> Void) {
        control.async {
            _ = self.checkSession()
            completionHandler()
        }
    }

    @discardableResult
    private func checkSession() -> Bool {
        guard !stopping else { return false }
        guard let reference, let updated = try? SessionStore.read(reference),
              updated.id == lease?.id, updated.remaining(at: .now) > 0 else {
            stopping = true
            timer?.cancel()
            timer = nil
            clearReminder()
            adapter?.refreshSessionDeadline()
            adapter?.stop { _ in
                self.cancelTunnelWithError(ProfileError(message: "Moley session ended. Open Moley to start a new session."))
            }
            return false
        }
        if updated.revision != lease?.revision {
            lease = updated
            adapter?.refreshSessionDeadline()
        }
        return true
    }

    private func clearReminder() {
        guard let lease else { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [lease.notificationID])
        center.removeDeliveredNotifications(withIdentifiers: [lease.notificationID])
    }

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)? = nil) {
        control.async {
            guard self.checkSession() else { completionHandler?(nil); return }
            if messageData == Data("sessionChanged".utf8) { completionHandler?(nil); return }
            guard messageData == Data("health".utf8), let adapter = self.adapter else { completionHandler?(nil); return }
            adapter.getRuntimeConfiguration { runtime in
                let data = runtime.flatMap { try? JSONEncoder().encode(TunnelHealth.parse($0)) }
                completionHandler?(data)
            }
        }
    }
}
