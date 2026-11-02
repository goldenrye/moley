import Foundation

/// Only these non-secret fields cross the extension-to-app message boundary.
struct TunnelHealth: Codable {
    let lastHandshake: TimeInterval?
    let receivedBytes: UInt64
    let sentBytes: UInt64

    static func parse(_ runtime: String) -> TunnelHealth {
        var handshake: TimeInterval?
        var received: UInt64 = 0
        var sent: UInt64 = 0
        for line in runtime.split(separator: "\n") {
            let pair = line.split(separator: "=", maxSplits: 1)
            guard pair.count == 2 else { continue }
            switch pair[0] {
            case "last_handshake_time_sec":
                if let value = TimeInterval(pair[1]), value > 0, value.isFinite { handshake = value }
            case "rx_bytes": received = UInt64(pair[1]) ?? 0
            case "tx_bytes": sent = UInt64(pair[1]) ?? 0
            default: break
            }
        }
        return TunnelHealth(lastHandshake: handshake, receivedBytes: received, sentBytes: sent)
    }
}
