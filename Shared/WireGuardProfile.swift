import Foundation
import Network

struct ProfileError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// A deliberately narrow client profile: one server, dual-stack default routes,
/// explicit DNS, and no executable wg-quick hooks.
struct WireGuardProfile {
    static let maximumSize = 32_768
    let configuration: TunnelConfiguration
    let text: String

    var endpoint: String { configuration.peers[0].endpoint!.stringRepresentation }

    init(text: String) throws {
        guard text.utf8.count <= Self.maximumSize else {
            throw ProfileError(message: "This configuration is too large (maximum 32 KB).")
        }
        var section = ""
        var values: [String: [String: String]] = [:]
        let keys = [
            "interface": Set(["privatekey", "address", "dns", "mtu", "listenport"]),
            "peer": Set(["publickey", "presharedkey", "allowedips", "endpoint", "persistentkeepalive"])
        ]
        for (index, raw) in text.components(separatedBy: .newlines).enumerated() {
            let line = String(raw.prefix { $0 != "#" }).trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            let lower = line.lowercased()
            if lower == "[interface]" || lower == "[peer]" {
                section = String(lower.dropFirst().dropLast())
                guard values[section] == nil else {
                    throw ProfileError(message: "Use exactly one Interface and one Peer section.")
                }
                values[section] = [:]
                continue
            }
            guard let equals = line.firstIndex(of: "="), let allowed = keys[section] else {
                throw ProfileError(message: "Invalid configuration structure on line \(index + 1).")
            }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            guard allowed.contains(key), !value.isEmpty else {
                throw ProfileError(message: "Unsupported or empty setting on line \(index + 1). Server scripts are not supported.")
            }
            if let previous = values[section]?[key] {
                guard ["address", "dns", "allowedips"].contains(key) else {
                    throw ProfileError(message: "Duplicate setting on line \(index + 1).")
                }
                values[section]?[key] = previous + "," + value
            } else {
                values[section]?[key] = value
            }
        }
        guard let interfaceValues = values["interface"], let peerValues = values["peer"],
              let privateKey = PrivateKey(base64Key: interfaceValues["privatekey"] ?? ""),
              let publicKey = PublicKey(base64Key: peerValues["publickey"] ?? ""),
              privateKey.rawValue.contains(where: { $0 != 0 }),
              publicKey.rawValue.contains(where: { $0 != 0 }) else {
            throw ProfileError(message: "The profile needs an Interface private key and a Peer public key, each a valid nonzero WireGuard key.")
        }
        var interface = InterfaceConfiguration(privateKey: privateKey)
        interface.addresses = try Self.ranges(interfaceValues["address"])
        guard interface.addresses.contains(where: { $0.address is IPv4Address }),
              interface.addresses.contains(where: { $0.address is IPv6Address }) else {
            throw ProfileError(message: "Add both IPv4 and IPv6 interface addresses. See the Moley server setup guide.")
        }
        interface.dns = try Self.list(interfaceValues["dns"]).map {
            guard let server = DNSServer(from: $0) else {
                throw ProfileError(message: "DNS must contain IP addresses, not domain names.")
            }
            return server
        }
        guard !interface.dns.isEmpty else { throw ProfileError(message: "Add at least one DNS server.") }
        if let value = interfaceValues["mtu"] {
            guard let mtu = UInt16(value), (1280...1420).contains(mtu) else {
                throw ProfileError(message: "MTU must be between 1280 and 1420 for this dual-stack tunnel.")
            }
            interface.mtu = mtu
        }
        if let value = interfaceValues["listenport"] {
            guard let port = UInt16(value) else { throw ProfileError(message: "Invalid listen port.") }
            interface.listenPort = port
        }
        var peer = PeerConfiguration(publicKey: publicKey)
        peer.allowedIPs = try Self.ranges(peerValues["allowedips"])
        let routes = Set(peer.allowedIPs.map(\.stringRepresentation))
        guard routes == Set(["0.0.0.0/0", "::/0"]) else {
            throw ProfileError(message: "AllowedIPs must be 0.0.0.0/0, ::/0 to route IPv4 and IPv6 through Moley.")
        }
        guard let endpointText = peerValues["endpoint"], !endpointText.hasPrefix(":"),
              let endpoint = Endpoint(from: endpointText), endpoint.port.rawValue != 0 else {
            throw ProfileError(message: "Add a valid server Endpoint, such as vpn.example.com:51820.")
        }
        peer.endpoint = endpoint
        if let value = peerValues["presharedkey"] {
            guard let key = PreSharedKey(base64Key: value), key.rawValue.contains(where: { $0 != 0 }) else {
                throw ProfileError(message: "Invalid preshared key.")
            }
            peer.preSharedKey = key
        }
        if let value = peerValues["persistentkeepalive"] {
            guard let interval = UInt16(value) else {
                throw ProfileError(message: "PersistentKeepalive must be between 0 and 65535 seconds.")
            }
            peer.persistentKeepAlive = interval
        } else {
            peer.persistentKeepAlive = 25
        }
        configuration = TunnelConfiguration(name: "Moley", interface: interface, peers: [peer])
        self.text = text
    }

    private static func list(_ value: String?) throws -> [String] {
        guard let value else { return [] }
        let parts = value.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.allSatisfy({ !$0.isEmpty }) else {
            throw ProfileError(message: "A comma-separated setting contains an empty entry.")
        }
        return parts
    }

    private static func ranges(_ value: String?) throws -> [IPAddressRange] {
        try list(value).map { item in
            let parts = item.components(separatedBy: "/")
            guard parts.count == 2, let prefix = Int(parts[1]),
                  let range = IPAddressRange(from: item),
                  (0...(range.address is IPv4Address ? 32 : 128)).contains(prefix) else {
                throw ProfileError(message: "Invalid IP address or network prefix.")
            }
            return range
        }
    }
}
