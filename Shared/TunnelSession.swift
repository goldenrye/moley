import Foundation
import Darwin
import Security

struct SessionClock {
    let date: Date
    let continuous: TimeInterval

    static var now: SessionClock {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        let seconds = Double(mach_continuous_time()) * Double(info.numer) / Double(info.denom) / 1_000_000_000
        return SessionClock(date: Date(), continuous: seconds)
    }
}

struct TunnelSession: Codable, Equatable {
    static let duration: TimeInterval = 30 * 60
    static let reminderLead: TimeInterval = 5 * 60
    let id: UUID
    let startedAt: Date
    let startedContinuous: TimeInterval
    var deadline: Date
    var continuousDeadline: TimeInterval
    var revision: Int

    init(now: SessionClock) {
        id = UUID()
        startedAt = now.date
        startedContinuous = now.continuous
        deadline = now.date.addingTimeInterval(Self.duration)
        continuousDeadline = now.continuous + Self.duration
        revision = 0
    }

    func remaining(at now: SessionClock) -> TimeInterval {
        guard now.continuous >= startedContinuous,
              deadline >= startedAt, continuousDeadline >= startedContinuous else { return 0 }
        // Wall-clock rollback must not lengthen a session; continuous time includes sleep.
        return max(0, min(deadline.timeIntervalSince(now.date), continuousDeadline - now.continuous))
    }

    mutating func extend(at now: SessionClock, expectedID: UUID, expectedRevision: Int) throws {
        guard id == expectedID, revision == expectedRevision, remaining(at: now) > 0 else {
            throw ProfileError(message: "This session or reminder has expired. Open Moley to start a new session.")
        }
        // Each explicit extension grants another 30 minutes beyond the current deadline.
        let remaining = remaining(at: now) + Self.duration
        guard remaining <= 7 * 24 * 60 * 60 else {
            throw ProfileError(message: "Session extension limit reached. Disconnect before starting a new session.")
        }
        deadline = now.date.addingTimeInterval(remaining)
        continuousDeadline = now.continuous + remaining
        revision += 1
    }

    var notificationID: String { "moley.session.\(id.uuidString).\(revision)" }

    func reminderDelay(at now: SessionClock) -> TimeInterval? {
        let remaining = remaining(at: now)
        return remaining > 0 ? max(1, remaining - Self.reminderLead) : nil
    }
}

enum SessionStore {
    static func create(_ session: TunnelSession) throws -> Data {
        try ProfileKeychain.store(String(decoding: JSONEncoder().encode(session), as: UTF8.self))
    }

    static func read(_ reference: Data) throws -> TunnelSession {
        try JSONDecoder().decode(TunnelSession.self, from: Data(ProfileKeychain.read(reference).utf8))
    }

    static func update(_ session: TunnelSession, reference: Data) throws {
        let status = SecItemUpdate([
            kSecClass: kSecClassGenericPassword,
            kSecValuePersistentRef: reference
        ] as CFDictionary, [kSecValueData: try JSONEncoder().encode(session)] as CFDictionary)
        guard status == errSecSuccess else {
            throw ProfileError(message: "Could not save the session deadline. The existing expiry still applies.")
        }
    }
}
