import Combine
import Foundation
import NetworkExtension

@MainActor
final class VPNController: ObservableObject {
    @Published private(set) var status: NEVPNStatus = .invalid
    @Published private(set) var hasProfile = false
    @Published private(set) var endpoint = ""
    @Published private(set) var isBusy = false
    @Published private(set) var isLoaded = false
    @Published private(set) var autoConnect = false
    @Published private(set) var health: TunnelHealth?
    @Published var errorMessage: String?

    private var manager: NETunnelProviderManager?
    private var observation: AnyCancellable?
    private var lastHealthResponse: Date?
    private let providerID = Bundle.main.bundleIdentifier! + ".tunnel"

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
        case .disconnected, .invalid: return "Not connected"
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
            let previousProtocol = current.protocolConfiguration
            let settings = NETunnelProviderProtocol()
            settings.providerBundleIdentifier = providerID
            settings.serverAddress = profile.endpoint
            settings.passwordReference = reference
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
        do {
            manager.isEnabled = true
            try await manager.saveToPreferences()
            try await manager.loadFromPreferences()
            try manager.connection.startVPNTunnel()
            updateStatus()
        } catch { errorMessage = error.localizedDescription }
        #endif
    }

    func disconnect() async {
        guard let manager, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
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
            try await manager.removeFromPreferences()
            self.manager = nil
            updateStatus()
            if let reference { try ProfileKeychain.delete(reference) }
        } catch { errorMessage = error.localizedDescription }
    }

    func refreshHealth() {
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

    private func reloadAfterFailure() async {
        try? await manager?.loadFromPreferences()
        updateStatus()
    }

    private func updateStatus() {
        status = manager?.connection.status ?? .invalid
        hasProfile = manager != nil
        endpoint = manager?.protocolConfiguration?.serverAddress ?? ""
        autoConnect = manager?.isOnDemandEnabled ?? false
        if status != .connected {
            health = nil
            lastHealthResponse = nil
        }
    }
}
