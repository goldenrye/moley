import Combine
import Foundation
import NetworkExtension

@MainActor
final class VPNController: ObservableObject {
    @Published private(set) var status: NEVPNStatus = .invalid
    @Published private(set) var hasProfile = false
    @Published private(set) var endpoint = ""
    @Published private(set) var transportName = "WireGuard (unobfuscated)"
    @Published private(set) var isBusy = false
    @Published private(set) var isLoaded = false
    @Published private(set) var autoConnect = false
    @Published private(set) var health: TunnelHealth?
    @Published private(set) var session: TunnelSession?
    @Published private(set) var notificationWarning: String?
    @Published var errorMessage: String?

    private var manager: NETunnelProviderManager?
    private var observation: AnyCancellable?
    private var lastHealthResponse: Date?
    private let providerID = Bundle.main.bundleIdentifier! + ".tunnel"
    private var sessionReference: Data? {
        (manager?.protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration?["sessionReference"] as? Data
    }

    var sessionRemaining: TimeInterval { session?.remaining(at: .now) ?? 0 }

    init() {
        observation = NotificationCenter.default.publisher(for: .NEVPNStatusDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                Task { @MainActor [weak self] in
                    guard let self, let connection = notification.object as? NEVPNConnection,
                          connection === self.manager?.connection else { return }
                    self.updateStatus()
                }
            }
    }

    var isActive: Bool { [.connected, .connecting, .reasserting, .disconnecting].contains(status) }
    var canEdit: Bool { isLoaded && !isBusy && !isActive && !autoConnect }
    var statusTitle: String {
        switch status {
        case .connected: return "Tunnel active"
        case .connecting: return "Connecting"
        case .reasserting: return "Reconnecting"
        case .disconnecting: return "Disconnecting"
        case .disconnected, .invalid:
            return session != nil && sessionRemaining <= 0 ? "Session expired" : "Not connected"
        @unknown default: return "Status unavailable"
        }
    }

    var healthDescription: String {
        guard status == .connected else { return "Your internet uses its normal connection." }
        guard let lastHealthResponse, Date().timeIntervalSince(lastHealthResponse) < 15,
              let seconds = health?.lastHandshake else {
            return "Waiting for the server handshake. A tunnel alone does not confirm internet access."
        }
        let age = max(0, Int(Date().timeIntervalSince1970 - seconds))
        if age > 180 { return "No recent server handshake. Check the AWS server or your network." }
        return "Server handshake \(age)s ago. Website access depends on the server connection."
    }

    func load() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            let own = managers.filter {
                ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == providerID
            }
            guard own.count <= 1 else {
                throw ProfileError(message: "Multiple Moley profiles were found. Remove duplicates in iOS Settings > VPN, then reopen Moley.")
            }
            manager = own.first
            isLoaded = true
            updateStatus()
            // Also migrates old unrestricted on-demand profiles. No lease, no traffic.
            if sessionRemaining <= 0 {
                SessionNotifications.clear()
                if isActive { manager?.connection.stopVPNTunnel() }
                if let manager, manager.isOnDemandEnabled {
                    manager.isOnDemandEnabled = false
                    manager.onDemandRules = []
                    try await manager.saveToPreferences()
                    try await manager.loadFromPreferences()
                    updateStatus()
                }
            }
        } catch { errorMessage = error.localizedDescription }
    }

    func importProfile(_ text: String) async -> Bool {
        guard canEdit else {
            errorMessage = "Disconnect and turn off automatic connection before replacing the profile."
            return false
        }
        isBusy = true
        defer { isBusy = false }
        var newReference: Data?
        var saved = false
        do {
            let profile = try WireGuardProfile(text: text)
            let reference = try ProfileKeychain.store(profile.text)
            newReference = reference
            let current = manager ?? NETunnelProviderManager()
            let oldReference = (current.protocolConfiguration as? NETunnelProviderProtocol)?.passwordReference
            let oldSessionReference = sessionReference
            let previousProtocol = current.protocolConfiguration
            let settings = NETunnelProviderProtocol()
            settings.providerBundleIdentifier = providerID
            settings.serverAddress = profile.endpoint
            settings.passwordReference = reference
            // Only a display label goes in preferences; all protocol secrets stay in Keychain.
            settings.providerConfiguration = ["transport": profile.transportName]
            settings.disconnectOnSleep = false
            current.protocolConfiguration = settings
            current.localizedDescription = "Moley"
            current.isEnabled = true
            current.isOnDemandEnabled = false
            do {
                try await current.saveToPreferences()
            } catch {
                current.protocolConfiguration = previousProtocol
                throw error
            }
            // Once iOS saves this reference, never roll it back on a reload failure.
            saved = true
            manager = current
            updateStatus()
            if let oldReference { try ProfileKeychain.delete(oldReference) }
            if let oldSessionReference { try? ProfileKeychain.delete(oldSessionReference) }
            try await current.loadFromPreferences()
            updateStatus()
            return true
        } catch {
            if !saved, let newReference { try? ProfileKeychain.delete(newReference) }
            errorMessage = error.localizedDescription
            return saved
        }
    }

    func connect() async {
        guard let manager, !isBusy, !isActive else { return }
        #if targetEnvironment(simulator)
        errorMessage = "VPN connections require a signed app on a physical iPhone. The simulator supports UI and configuration tests only."
        return
        #else
        isBusy = true
        defer { isBusy = false }
        var createdReference: Data?
        do {
            let allowed = await SessionNotifications.requestPermission()
            notificationWarning = allowed ? nil : "Reminders are disabled. Moley still disconnects automatically after 30 minutes."
            let lease = TunnelSession(now: .now)
            let reference = try SessionStore.create(lease)
            createdReference = reference
            let oldReference = sessionReference
            guard let settings = manager.protocolConfiguration as? NETunnelProviderProtocol else {
                throw ProfileError(message: "Import a Moley configuration before connecting.")
            }
            var metadata = settings.providerConfiguration ?? [:]
            metadata["sessionReference"] = reference
            settings.providerConfiguration = metadata
            manager.protocolConfiguration = settings
            manager.isEnabled = true
            manager.isOnDemandEnabled = false
            manager.onDemandRules = []
            try await manager.saveToPreferences()
            try await manager.loadFromPreferences()
            if let oldReference { try? ProfileKeychain.delete(oldReference) }
            try manager.connection.startVPNTunnel()
            updateStatus()
            await scheduleReminder(lease, reference: reference)
        } catch {
            if let createdReference { try? ProfileKeychain.delete(createdReference) }
            SessionNotifications.clear()
            manager.connection.stopVPNTunnel()
            errorMessage = error.localizedDescription
            updateStatus()
        }
        #endif
    }

    func disconnect() async {
        guard let manager, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        SessionNotifications.clear()
        // Revoke first, so an automatic restart cannot reuse this session.
        if let reference = sessionReference {
            do { try ProfileKeychain.delete(reference) }
            catch { errorMessage = error.localizedDescription }
        }
        manager.connection.stopVPNTunnel()
        do {
            // Disable on-demand before stopping, otherwise iOS immediately reconnects.
            if manager.isOnDemandEnabled {
                manager.isOnDemandEnabled = false
                try await manager.saveToPreferences()
                try await manager.loadFromPreferences()
            }
            manager.connection.stopVPNTunnel()
            updateStatus()
        } catch {
            errorMessage = error.localizedDescription
            await reloadAfterFailure()
        }
    }

    func setAutoConnect(_ enabled: Bool) async {
        guard let manager, !isBusy else { return }
        guard !enabled || (sessionRemaining > 0 && isActive) else {
            errorMessage = "Start a 30-minute session before enabling reconnection."
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            let rule = NEOnDemandRuleConnect()
            rule.interfaceTypeMatch = .any
            manager.onDemandRules = enabled ? [rule] : []
            manager.isOnDemandEnabled = enabled
            manager.isEnabled = true
            try await manager.saveToPreferences()
            try await manager.loadFromPreferences()
            updateStatus()
        } catch {
            errorMessage = error.localizedDescription
            await reloadAfterFailure()
        }
    }

    func removeProfile() async {
        guard let manager, canEdit else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let reference = (manager.protocolConfiguration as? NETunnelProviderProtocol)?.passwordReference
            let leaseReference = sessionReference
            try await manager.removeFromPreferences()
            self.manager = nil
            updateStatus()
            if let reference { try ProfileKeychain.delete(reference) }
            if let leaseReference { try ProfileKeychain.delete(leaseReference) }
            SessionNotifications.clear()
        } catch { errorMessage = error.localizedDescription }
    }

    func refreshHealth() {
        updateStatus()
        if sessionRemaining <= 0 && (isActive || autoConnect) {
            Task { await disconnect() }
            return
        }
        guard status == .connected, let session = manager?.connection as? NETunnelProviderSession else { return }
        do {
            try session.sendProviderMessage(Data("health".utf8)) { [weak self, weak session] data in
                Task { @MainActor [weak self] in
                    guard let self, self.status == .connected,
                          session === self.manager?.connection else { return }
                    self.health = data.flatMap { try? JSONDecoder().decode(TunnelHealth.self, from: $0) }
                    self.lastHealthResponse = Date()
                }
            }
        } catch { health = nil }
    }

    func extendSession(expectedID: UUID? = nil, expectedRevision: Int? = nil) async {
        guard !isBusy, let reference = sessionReference else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            var lease = try SessionStore.read(reference)
            try lease.extend(at: .now, expectedID: expectedID ?? lease.id,
                             expectedRevision: expectedRevision ?? lease.revision)
            // Updating a deleted record fails rather than resurrecting a stopped session.
            try SessionStore.update(lease, reference: reference)
            updateStatus()
            if let connection = manager?.connection as? NETunnelProviderSession {
                try? connection.sendProviderMessage(Data("sessionChanged".utf8))
            }
            await scheduleReminder(lease, reference: reference)
        } catch { errorMessage = error.localizedDescription }
    }

    private func scheduleReminder(_ lease: TunnelSession, reference: Data) async {
        do {
            try await SessionNotifications.schedule(lease)
            // A Settings disconnect can delete the lease while notification scheduling awaits iOS.
            guard let saved = try? SessionStore.read(reference), saved == lease,
                  saved.remaining(at: .now) > 0 else {
                SessionNotifications.clear()
                return
            }
        } catch {
            notificationWarning = "The reminder could not be scheduled. Automatic disconnection is still active."
        }
    }

    private func reloadAfterFailure() async {
        try? await manager?.loadFromPreferences()
        updateStatus()
    }

    private func updateStatus() {
        status = manager?.connection.status ?? .invalid
        hasProfile = manager != nil
        endpoint = manager?.protocolConfiguration?.serverAddress ?? ""
        let settings = manager?.protocolConfiguration as? NETunnelProviderProtocol
        transportName = settings?.providerConfiguration?["transport"] as? String ?? "WireGuard (unobfuscated)"
        autoConnect = manager?.isOnDemandEnabled ?? false
        session = sessionReference.flatMap { try? SessionStore.read($0) }
        if status != .connected {
            health = nil
            lastHealthResponse = nil
        }
    }
}
