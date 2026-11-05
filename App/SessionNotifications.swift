import UIKit
import UserNotifications

@MainActor
enum SessionNotifications {
    static let category = "MOLEY_SESSION"
    static let extend = "MOLEY_EXTEND"
    static let disconnect = "MOLEY_DISCONNECT"

    static func register() {
        let actions = [
            UNNotificationAction(identifier: extend, title: "Extend 30 minutes", options: [.foreground, .authenticationRequired]),
            UNNotificationAction(identifier: disconnect, title: "Disconnect now", options: [.foreground])
        ]
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: category, actions: actions, intentIdentifiers: [])
        ])
    }

    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static func schedule(_ session: TunnelSession) async throws {
        clear()
        guard let request = request(for: session, now: .now) else { return }
        try await UNUserNotificationCenter.current().add(request)
    }

    static func request(for session: TunnelSession, now: SessionClock) -> UNNotificationRequest? {
        guard let delay = session.reminderDelay(at: now) else { return nil }
        let content = UNMutableNotificationContent()
        content.title = session.remaining(at: now) < TunnelSession.reminderLead
            ? "Moley disconnects soon" : "Moley disconnects in 5 minutes"
        content.body = "Extend your session or disconnect now. No response means the tunnel turns off automatically."
        content.sound = .default
        content.categoryIdentifier = category
        content.userInfo = ["sessionID": session.id.uuidString, "revision": session.revision]
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: delay, repeats: false
        )
        return UNNotificationRequest(identifier: session.notificationID, content: content, trigger: trigger)
    }

    static func clear() {
        // Moley only schedules session reminders.
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }
}

@MainActor
final class MoleyAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    let vpn = VPNController()

    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        SessionNotifications.register()
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completion: @escaping (UNNotificationPresentationOptions) -> Void) {
        completion([.banner, .sound, .list])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completion: @escaping () -> Void) {
        Task { @MainActor in
            defer { completion() }
            let info = response.notification.request.content.userInfo
            guard let idString = info["sessionID"] as? String, let id = UUID(uuidString: idString),
                  let revision = info["revision"] as? Int else { return }
            // The cold-launch view can already be loading preferences.
            for _ in 0..<100 where vpn.isBusy { try? await Task.sleep(for: .milliseconds(50)) }
            await vpn.load()
            if response.actionIdentifier == SessionNotifications.extend {
                await vpn.extendSession(expectedID: id, expectedRevision: revision)
            } else if response.actionIdentifier == SessionNotifications.disconnect {
                guard vpn.session?.id == id, vpn.session?.revision == revision else { return }
                await vpn.disconnect()
            }
        }
    }
}
