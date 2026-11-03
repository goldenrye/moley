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
    var isObfuscated: Bool { !configuration.interface.amneziaSettings.isEmpty }
    var transportName: String { isObfuscated ? "AmneziaWG" : "WireGuard (unobfuscated)" }

    init(text: String) throws {
        guard text.utf8.count <= Self.maximumSize else {
            throw ProfileError(message: "This configuration is too large (maximum 32 KB).")
        }
        var section = ""
        var values: [String: [String: String]] = [:]
        let keys = [
            "interface": Set(["privatekey", "address", "dns", "mtu", "listenport"]).union(AmneziaSettings.keys),
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
        interface.amneziaSettings = try AmneziaSettings.parse(interfaceValues, mtu: Int(interface.mtu ?? 1280))
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

/// Conservative mobile limits also prevent imported signature templates from
/// driving unbounded allocations or producing oversized UDP packets in Go.
enum AmneziaSettings {
    static let required = ["jc", "jmin", "jmax", "s1", "s2", "h1", "h2", "h3", "h4"]
    static let keys = Set(required + ["s3", "s4", "i1", "i2", "i3", "i4", "i5",
                                      "headerprotectionkey", "contentpaddingaddition"])

    static func parse(_ input: [String: String], mtu: Int) throws -> [String: String] {
        guard !keys.isDisjoint(with: input.keys) else { return [:] }
        guard required.allSatisfy({ input[$0] != nil }) else {
            throw ProfileError(message: "Incomplete AmneziaWG profile. Include Jc, Jmin, Jmax, S1, S2, and H1-H4 from your server administrator.")
        }
        var output: [String: String] = [:]
        func number(_ key: String, maximum: UInt32) throws -> UInt32 {
            let value = input[key] ?? "0"
            guard isDecimal(value), let parsed = UInt32(value), parsed <= maximum else {
                throw ProfileError(message: "\(key.uppercased()) must be a whole number from 0 to \(maximum).")
            }
            output[key] = String(parsed)
            return parsed
        }
        let count = try number("jc", maximum: 32)
        let minimum = try number("jmin", maximum: 1280)
        let maximum = try number("jmax", maximum: 1280)
        guard minimum <= maximum, count == 0 || minimum > 0 else {
            throw ProfileError(message: "Jmin must not exceed Jmax, and must be positive when Jc is enabled.")
        }
        let s1 = try number("s1", maximum: 1024)
        let s2 = try number("s2", maximum: 1024)
        let s3 = try number("s3", maximum: 1024)
        let s4 = try number("s4", maximum: 128)
        guard s1 + 148 != s2 + 92 else {
            throw ProfileError(message: "S1 + 148 must differ from S2 + 92 for compatibility with older AmneziaWG servers.")
        }
        var headers: [ClosedRange<UInt32>] = []
        for key in ["h1", "h2", "h3", "h4"] {
            let range = try unsignedRange(input[key]!, field: key.uppercased(), minimum: 5, maximum: .max)
            guard !headers.contains(where: { $0.overlaps(range) }) else {
                throw ProfileError(message: "H1-H4 must use distinct, non-overlapping header values or ranges.")
            }
            headers.append(range)
            output[key] = encode(range)
        }
        for key in ["i1", "i2", "i3", "i4", "i5"] {
            if let value = input[key] { output[key] = try signature(value, field: key.uppercased()) }
        }
        if let value = input["headerprotectionkey"] {
            guard let key = PrivateKey(base64Key: value), key.rawValue.contains(where: { $0 != 0 }) else {
                throw ProfileError(message: "HeaderProtectionKey must be a nonzero base64-encoded 32-byte key.")
            }
            guard [s1, s2, s3, s4].allSatisfy({ $0 >= 12 }) else {
                throw ProfileError(message: "AmneziaWG 3 header protection requires S1-S4 to be at least 12.")
            }
            output["header_protection_key"] = key.hexKey
        }
        var contentPadding: UInt32 = 0
        if let value = input["contentpaddingaddition"] {
            let range = try unsignedRange(value, field: "ContentPaddingAddition", minimum: 0, maximum: 128)
            output["content_padding_addition"] = encode(range)
            contentPadding = range.upperBound
        }
        // 80 bytes covers IPv6 + UDP + WireGuard overhead; WG pads to 16 bytes.
        guard ((mtu + 15) / 16) * 16 + 80 + Int(s4) + Int(contentPadding) <= 1500 else {
            throw ProfileError(message: "MTU plus S4/content padding is too large. Use MTU 1280 or reduce padding on both client and server.")
        }
        return output
    }

    private static func isDecimal(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy { (48...57).contains($0) }
    }

    private static func unsignedRange(_ value: String, field: String, minimum: UInt32,
                                      maximum: UInt32) throws -> ClosedRange<UInt32> {
        let parts = value.components(separatedBy: "-")
        guard (1...2).contains(parts.count), parts.allSatisfy(isDecimal),
              let low = UInt32(parts[0]), let high = UInt32(parts.last!),
              minimum <= low, low <= high, high <= maximum else {
            throw ProfileError(message: "\(field) must be a value or ascending range between \(minimum) and \(maximum).")
        }
        return low...high
    }

    private static func encode(_ range: ClosedRange<UInt32>) -> String {
        range.lowerBound == range.upperBound
            ? String(range.lowerBound) : "\(range.lowerBound)-\(range.upperBound)"
    }

    private static func signature(_ value: String, field: String) throws -> String {
        var remaining = value[...]
        var tags: [String] = []
        var size = 0
        func invalid() -> ProfileError {
            ProfileError(message: "\(field) must contain only <b 0xHEX>, <r N>, <rd N>, <rc N>, or <t> tags, totaling 1-1280 bytes.")
        }
        while !remaining.isEmpty {
            remaining = remaining.drop(while: { $0 == " " || $0 == "\t" })
            if remaining.isEmpty { break }
            guard remaining.first == "<", let end = remaining.firstIndex(of: ">") else { throw invalid() }
            let parts = remaining[remaining.index(after: remaining.startIndex)..<end].split(whereSeparator: \.isWhitespace)
            guard let tag = parts.first else { throw invalid() }
            if tag == "t" {
                guard parts.count == 1 else { throw invalid() }
                size += 4
                tags.append("<t>")
            } else {
                guard parts.count == 2 else { throw invalid() }
                let argument = String(parts[1])
                switch tag {
                case "b":
                    let hex = argument.hasPrefix("0x") ? String(argument.dropFirst(2)) : argument
                    guard !hex.isEmpty, hex.count % 2 == 0,
                          hex.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) else { throw invalid() }
                    size += hex.count / 2
                    tags.append("<b 0x\(hex.lowercased())>")
                case "r", "rd", "rc":
                    guard isDecimal(argument), let length = Int(argument), (1...1280).contains(length) else { throw invalid() }
                    size += length
                    tags.append("<\(tag) \(length)>")
                default: throw invalid()
                }
            }
            guard size <= 1280 else { throw invalid() }
            remaining = remaining[remaining.index(after: end)...]
        }
        guard size > 0 else { throw invalid() }
        return tags.joined()
    }
}
