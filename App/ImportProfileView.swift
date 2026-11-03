import SwiftUI
import UniformTypeIdentifiers

@MainActor
private final class ImportDraft: ObservableObject {
    @Published var text = ""
    @Published var showingFilePicker = false
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
                    Text("Ask your family administrator for your personal AmneziaWG .conf file. Its obfuscation settings must match the server. Never share your file with another device.")
                    Text("Standard WireGuard files still work, but do not enable obfuscation.")
                        .font(.footnote).foregroundStyle(.secondary)
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
                                if value.utf8.count > WireGuardProfile.maximumSize {
                                    draft.text = ""
                                    draft.localError = "Configuration is too large (maximum 32 KB)."
                                }
                            }
                    }
                } footer: {
                    Text("The file contains a private key. Moley stores it securely after import, but cannot delete copies in Files, messages, or your clipboard. Remove those copies yourself.")
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
            .onDisappear { draft.text = "" }
        }
    }

    private func setText(_ candidate: String) {
        guard candidate.utf8.count <= WireGuardProfile.maximumSize else {
            draft.localError = "Configuration is too large (maximum 32 KB)."
            return
        }
        draft.text = candidate
        draft.revealText = false
    }
}
