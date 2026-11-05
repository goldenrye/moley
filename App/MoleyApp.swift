import SwiftUI

@main
struct MoleyApp: App {
    @UIApplicationDelegateAdaptor(MoleyAppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            HomeView(vpn: delegate.vpn)
                .tint(.teal)
        }
    }
}
