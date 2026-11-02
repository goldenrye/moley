import SwiftUI

@main
struct MoleyApp: App {
    @StateObject private var vpn = VPNController()

    var body: some Scene {
        WindowGroup {
            HomeView(vpn: vpn)
                .tint(.teal)
        }
    }
}
