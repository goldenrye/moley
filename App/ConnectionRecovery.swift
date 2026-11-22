import Foundation
import NetworkExtension

/// Foreground connection recovery is independent of the 30-minute session lease.
struct ConnectionRecovery {
    static let timeout: TimeInterval = 30
    private(set) var id = UUID()
    private(set) var failure: String?
    private var waitingSince: TimeInterval?
    private var sawActiveConnection = false

    mutating func begin(at now: TimeInterval) {
        self = ConnectionRecovery()
        waitingSince = now
    }

    mutating func fail(_ message: String) {
        failure = message
        waitingSince = nil
    }

    /// Returns true once when an unsuccessful attempt needs to be stopped.
    mutating func observe(status: NEVPNStatus, serverResponding: Bool, at now: TimeInterval) -> Bool {
        guard failure == nil else { return false }
        switch status {
        case .connected where serverResponding:
            waitingSince = nil
            sawActiveConnection = true
            return false
        case .connecting, .connected, .reasserting:
            sawActiveConnection = true
            if waitingSince == nil { waitingSince = now }
        case .disconnected, .invalid:
            if sawActiveConnection {
                fail("The connection ended. Unlock your iPhone if iOS requested authentication, then tap Retry connection.")
                return true
            }
        case .disconnecting:
            break
        @unknown default:
            break
        }
        if let waitingSince, now - waitingSince >= Self.timeout {
            fail("The server did not respond within 30 seconds. Check your network and server settings, then tap Retry connection.")
            return true
        }
        return false
    }
}
