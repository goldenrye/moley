import NetworkExtension
import os

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private let logger = Logger(subsystem: "Moley", category: "Tunnel")
    private lazy var adapter = WireGuardAdapter(with: self) { [weak self] level, _ in
        // Never persist backend strings: they may contain endpoint/configuration data.
        if level == .error { self?.logger.error("WireGuard reported a backend error.") }
    }

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        do {
            guard let settings = protocolConfiguration as? NETunnelProviderProtocol,
                  let reference = settings.passwordReference else {
                throw ProfileError(message: "Import a Moley configuration before connecting.")
            }
            let profile = try WireGuardProfile(text: ProfileKeychain.read(reference))
            adapter.start(tunnelConfiguration: profile.configuration) { error in
                guard let error else { completionHandler(nil); return }
                let message: String
                switch error {
                case .dnsResolution:
                    message = "Cannot resolve the VPN server. Check your internet connection and server hostname."
                case .setNetworkSettings:
                    message = "iOS could not install the VPN routes."
                case .cannotLocateTunnelFileDescriptor, .startWireGuardBackend, .invalidState:
                    message = "The WireGuard tunnel could not start. Disconnect and try again."
                }
                completionHandler(ProfileError(message: message))
            }
        } catch {
            completionHandler(error)
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        adapter.stop { _ in completionHandler() }
    }

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)? = nil) {
        guard messageData == Data("health".utf8) else { completionHandler?(nil); return }
        adapter.getRuntimeConfiguration { runtime in
            let data = runtime.flatMap { try? JSONEncoder().encode(TunnelHealth.parse($0)) }
            completionHandler?(data)
        }
    }
}
