import SwiftUI
import UniformTypeIdentifiers

@MainActor
private final class ImportDraft: ObservableObject {
    @Published var text = ""
    @Published var showingFilePicker = false
    @Published var showingQRScanner = false
    var scanError: String?
    @Published var scannedEndpoint: String?
    @Published var localError: String?
    @Published var revealText = false
    @Published var isSaving = false
}

struct ImportProfileView: View {
    @ObservedObject var vpn: VPNController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var draft = ImportDraft()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Ask your family administrator for your personal AmneziaWG configuration as a QR code or .conf file. Its obfuscation settings must match the server. Never share it with another device.")
                    Text("Standard WireGuard files still work, but do not enable obfuscation.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Scan configuration QR code", systemImage: "qrcode.viewfinder") {
                        draft.revealText = false
                        draft.showingQRScanner = true
                    }
                    .accessibilityIdentifier("scanQRButton")
                    Button("Choose configuration file", systemImage: "doc.badge.plus") { draft.showingFilePicker = true }
                        .accessibilityIdentifier("chooseFileButton")
                    PasteButton(payloadType: String.self) { strings in
                        guard let candidate = strings.first else { return }
                        setText(candidate)
                    }
                    .accessibilityLabel("Paste VPN configuration")
                } header: { Text("Your invitation") }

                Section {
                    if draft.text.isEmpty {
                        Text("No configuration selected").foregroundStyle(.secondary)
                    } else {
                        Label("Configuration ready to validate", systemImage: "doc.badge.checkmark")
                    }
                    if let endpoint = draft.scannedEndpoint {
                        Text("Scanned server: \(endpoint)")
                            .font(.callout)
                            .accessibilityIdentifier("scannedEndpoint")
                    }
                    Toggle("Show or edit private configuration", isOn: $draft.revealText)
                        .accessibilityIdentifier("revealConfiguration")
                    if draft.revealText {
                        TextEditor(text: $draft.text)
                            .font(.system(.caption, design: .monospaced))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .frame(minHeight: 220)
                            .privacySensitive()
                            .accessibilityLabel("VPN configuration")
                            .accessibilityIdentifier("configurationEditor")
                            .onChange(of: draft.text) { _, value in
                                draft.scannedEndpoint = nil
                                if value.utf8.count > WireGuardProfile.maximumSize {
                                    draft.text = ""
                                    draft.localError = "Configuration is too large (maximum 32 KB)."
                                }
                            }
                    }
                } footer: {
                    Text("The QR code or file contains a private key. Only scan a code from your trusted administrator. Moley stores the configuration securely after import, but cannot delete copies in Files, messages, photos, or your clipboard. Remove those copies yourself.")
                }

                Section {
                    Button {
                        Task {
                            do {
                                _ = try WireGuardProfile(text: draft.text)
                                draft.isSaving = true
                                let success = await vpn.importProfile(draft.text)
                                draft.isSaving = false
                                if success { draft.text = ""; dismiss() }
                                else { draft.localError = vpn.errorMessage; vpn.errorMessage = nil }
                            } catch { draft.localError = error.localizedDescription }
                        }
                    } label: {
                        HStack {
                            Text("Save configuration")
                            Spacer()
                            if draft.isSaving { ProgressView() }
                        }
                    }
                    .disabled(draft.text.isEmpty || vpn.isBusy || draft.isSaving)
                    .accessibilityIdentifier("saveConfiguration")
                } footer: { Text("iOS will ask permission to add a VPN configuration. Saving does not connect until you choose Connect.") }
            }
            .navigationTitle("Set up Moley")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Cancel") { draft.text = ""; dismiss() }.disabled(draft.isSaving) }
            .interactiveDismissDisabled(draft.isSaving)
            .sheet(isPresented: $draft.showingQRScanner, onDismiss: {
                // Present validation errors after the camera sheet has closed.
                if let error = draft.scanError {
                    draft.localError = error
                    draft.scanError = nil
                }
            }) {
                QRCodeScannerView { payload in
                    do {
                        let profile = try ConfigurationQRCode.profile(from: payload)
                        setText(profile.text)
                        draft.scannedEndpoint = profile.endpoint
                    } catch {
                        draft.scanError = "Could not scan the configuration. Use a QR code containing the complete .conf text, not a website or vpn:// link. \(error.localizedDescription)"
                    }
                    draft.showingQRScanner = false
                }
            }
            .fileImporter(isPresented: $draft.showingFilePicker, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
                do {
                    guard let url = try result.get().first else { return }
                    let granted = url.startAccessingSecurityScopedResource()
                    defer { if granted { url.stopAccessingSecurityScopedResource() } }
                    let handle = try FileHandle(forReadingFrom: url)
                    defer { try? handle.close() }
                    let data = try handle.read(upToCount: WireGuardProfile.maximumSize + 1) ?? Data()
                    guard data.count <= WireGuardProfile.maximumSize,
                          let candidate = String(data: data, encoding: .utf8) else {
                        throw ProfileError(message: "Choose a UTF-8 AmneziaWG or WireGuard configuration up to 32 KB.")
                    }
                    setText(candidate)
                } catch { draft.localError = "Could not import the configuration. \(error.localizedDescription)" }
            }
            .alert("Check your configuration", isPresented: Binding(
                get: { draft.localError != nil },
                set: { if !$0 { draft.localError = nil } }
            )) { Button("OK") { draft.localError = nil } } message: { Text(draft.localError ?? "") }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { draft.revealText = false }
            }
            .onDisappear {
                if !draft.showingQRScanner { draft.text = "" }
            }
        }
    }

    private func setText(_ candidate: String) {
        guard candidate.utf8.count <= WireGuardProfile.maximumSize else {
            draft.localError = "Configuration is too large (maximum 32 KB)."
            return
        }
        draft.scannedEndpoint = nil
        draft.text = candidate
        draft.revealText = false
    }
}
