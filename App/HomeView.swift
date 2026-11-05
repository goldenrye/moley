import SwiftUI
import NetworkExtension

@MainActor
private final class HomePresentation: ObservableObject {
    @Published var showingImport = false
    @Published var confirmingRemoval = false
    @Published var confirmingAutoConnect = false
}

struct HomeView: View {
    @ObservedObject var vpn: VPNController
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var presentation = HomePresentation()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 12) {
                        Image("MoleyLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 112, height: 112)
                            .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
                            .accessibilityHidden(true)
                        Text("A little closer to home.")
                            .font(.largeTitle.bold())
                            .multilineTextAlignment(.center)
                        Text("Your family's connection through your US server.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical, 16)

                    VStack(spacing: 18) {
                        Label(vpn.statusTitle, systemImage: vpn.status == .connected ? "checkmark.circle.fill" : "circle")
                            .font(.title2.bold())
                            .accessibilityIdentifier("vpnStatus")
                        Text(vpn.healthDescription)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        if vpn.isActive, let session = vpn.session {
                            TimelineView(.periodic(from: .now, by: 1)) { _ in
                                let seconds = Int(ceil(session.remaining(at: .now)))
                                Text(String(format: "Session ends in %02d:%02d", seconds / 60, seconds % 60))
                                    .font(.headline.monospacedDigit())
                                    .accessibilityIdentifier("sessionCountdown")
                            }
                            Button("Extend 30 minutes") { Task { await vpn.extendSession() } }
                                .disabled(vpn.isBusy || vpn.sessionRemaining <= 0)
                                .accessibilityIdentifier("extendSessionButton")
                        }
                        Text("30-minute sessions. Reminder after 25 minutes; no response means automatic disconnection.")
                            .font(.footnote).foregroundStyle(.secondary)
                            .accessibilityIdentifier("sessionPolicy")
                        if let warning = vpn.notificationWarning {
                            Text(warning).font(.footnote).foregroundStyle(.orange)
                        }
                        if vpn.hasProfile {
                            Button {
                                Task {
                                    if vpn.isActive { await vpn.disconnect() }
                                    else { await vpn.connect() }
                                }
                            } label: {
                                Text(vpn.isActive ? "Disconnect" : "Connect for 30 minutes")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity, minHeight: 38)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(vpn.isBusy || vpn.status == .disconnecting)
                            .accessibilityIdentifier("connectButton")
                        } else {
                            Button("Set up Moley") { presentation.showingImport = true }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                                .disabled(!vpn.isLoaded || vpn.isBusy)
                                .accessibilityIdentifier("setupButton")
                        }
                        if vpn.isBusy { ProgressView().accessibilityLabel("Updating VPN settings") }
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity)
                    .background(.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 24))

                    if vpn.hasProfile {
                        VStack(alignment: .leading, spacing: 18) {
                            Label("Your server", systemImage: "server.rack").font(.headline)
                            Text(vpn.endpoint).font(.callout.monospaced()).textSelection(.enabled)
                            Label(vpn.transportName, systemImage: "network")
                                .accessibilityIdentifier("transportName")
                            if vpn.transportName != "AmneziaWG" {
                                Text("This profile has no traffic obfuscation. Import a matching AmneziaWG server configuration to enable it.")
                                    .font(.footnote).foregroundStyle(.orange)
                            }
                            Toggle("Reconnect during this session", isOn: Binding(
                                get: { vpn.autoConnect },
                                set: { enabled in
                                    if enabled { presentation.confirmingAutoConnect = true }
                                    else { Task { await vpn.setAutoConnect(false) } }
                                }
                            ))
                            .disabled(vpn.isBusy || (!vpn.autoConnect && (!vpn.isActive || vpn.sessionRemaining <= 0)))
                            Text("Off by default. Reconnection never extends the deadline. Start a new session in Moley after expiry.")
                                .font(.footnote).foregroundStyle(.secondary)
                            Divider()
                            Button("Replace configuration") { presentation.showingImport = true }
                                .disabled(!vpn.canEdit)
                            Button("Remove from this iPhone", role: .destructive) { presentation.confirmingRemoval = true }
                                .disabled(!vpn.canEdit)
                            if !vpn.canEdit && !vpn.isBusy {
                                Text("Disconnect and turn off automatic connection to change the profile.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        .padding(22)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Label("Private by design", systemImage: "key.fill").font(.headline)
                        Text("Your VPN key stays in this iPhone's Keychain. Moley has no analytics or account service.")
                        Text("The server operator and DNS provider can see connection metadata. Use HTTPS for websites.")
                        Text("AmneziaWG changes recognizable traffic patterns, but cannot guarantee access or make VPN use undetectable. It still uses UDP.")
                        Text("This is not an always-on kill switch. When the VPN is off, traffic uses your normal network. Some iOS system traffic may bypass VPN routes.")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    #if targetEnvironment(simulator)
                    Text("Simulator preview: a physical iPhone is required for VPN connections.")
                        .font(.footnote).foregroundStyle(.orange)
                    #endif
                }
                .padding(24)
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("moley")
            .toolbar {
                if !vpn.isLoaded && !vpn.isBusy {
                    Button("Retry") { Task { await vpn.load() } }
                }
            }
            .sheet(isPresented: $presentation.showingImport) { ImportProfileView(vpn: vpn) }
            .alert("Moley needs your attention", isPresented: Binding(
                get: { vpn.errorMessage != nil },
                set: { if !$0 { vpn.errorMessage = nil } }
            )) {
                Button("OK") { vpn.errorMessage = nil }
            } message: { Text(vpn.errorMessage ?? "") }
            .confirmationDialog("Remove the saved VPN and its private key?", isPresented: $presentation.confirmingRemoval, titleVisibility: .visible) {
                Button("Remove configuration", role: .destructive) { Task { await vpn.removeProfile() } }
            } message: { Text("This does not revoke access on AWS. Ask the server administrator to remove this device's peer too.") }
            .confirmationDialog("Reconnect within this session?", isPresented: $presentation.confirmingAutoConnect, titleVisibility: .visible) {
                Button("Enable session reconnection") { Task { await vpn.setAutoConnect(true) } }
            } message: { Text("iOS can reconnect on Wi-Fi or cellular until the current deadline. Expired sessions cannot automatically restart.") }
            .task { await vpn.load() }
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                while !Task.isCancelled {
                    vpn.refreshHealth()
                    try? await Task.sleep(for: .seconds(5))
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await vpn.load() } }
            }
        }
    }
}
