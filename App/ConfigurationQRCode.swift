import Foundation

enum ConfigurationQRCode {
    static func profile(from payload: String?) throws -> WireGuardProfile {
        guard let payload, !payload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProfileError(message: "This QR code has no readable configuration text. Ask for a QR code containing your complete .conf file.")
        }
        // Use exactly the same limits and validation as file/paste import. Never open
        // URLs, fetch remote profiles, or interpret commands from a scanned code.
        return try WireGuardProfile(text: payload)
    }
}
