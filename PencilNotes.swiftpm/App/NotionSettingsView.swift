import SwiftUI

struct NotionSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var token = ""
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(model.connectionStatus, systemImage: model.client == nil ? "link" : "checkmark.shield")
                    if model.client != nil {
                        Button("Verify Connection") { Task { await model.verifyConnection() } }
                        Button("Disconnect", role: .destructive) { model.disconnect() }
                    }
                } header: { Text("Notion connection") }
                Section {
                    SecureField("Internal integration token", text: $token)
                        .textContentType(.password).textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                    Button(model.client == nil ? "Connect Notion" : "Reconnect with this token") {
                        Task { if await model.connect(token: token) { token = "" } }
                    }.disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } footer: {
                    Text("Token stored securely in Keychain.")
                }
                Section("Notion setup") {
                    VStack(spacing: 12) {
                        integrationStep("Create internal integration", detail: "Choose your workspace", showsLink: true)
                        Image(systemName: "arrow.down")
                            .foregroundStyle(.secondary).accessibilityHidden(true)
                        integrationStep("Enable permissions", detail: "Read · Insert · Update content")
                        Image(systemName: "arrow.down")
                            .foregroundStyle(.secondary).accessibilityHidden(true)
                        integrationStep("Connect your page", detail: "Page → ••• → Connections → Your integration")
                        Image(systemName: "arrow.down")
                            .foregroundStyle(.secondary).accessibilityHidden(true)
                        integrationStep("Connect in this app", detail: "Paste token above → Connect Notion")
                    }
                    .padding(.vertical, 8)
                    Text("Search shows connected pages.").font(.footnote)
                }
                Section("Your data") {
                    Text("Notes stay on this iPad. Sync sends a PNG and title to Notion. Export backups to keep editable ink.")
                }
                Section("About & Support") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Made with \u{2764}\u{FE0F} by Morsalin Islam").font(.headline)
                        Text("A small notebook for your next big idea.").foregroundStyle(.secondary)
                        Link("GitHub", destination: URL(string: "https://github.com/rabbiii/Handwrite-for-Notion")!)
                        Link("Send feedback", destination: URL(string: "mailto:mar.rabbi40@gmail.com?subject=PencilNotes%20feedback")!)
                        DisclosureGroup("About the developer") {
                            Text("PencilNotes is an independent open-source project by Morsalin Islam. Feedback and contributions are welcome.")
                        }
                        Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.1.1")")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 8)
                }
                if model.isBusy { Section { ProgressView(model.progress) } }
                if let message = model.errorMessage {
                    Section { ErrorBanner(message: message) { model.errorMessage = nil } }
                }
            }
            .disabled(model.isBusy || model.isSyncing)
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { token = ""; dismiss() }.disabled(model.isBusy) } }
        }.interactiveDismissDisabled(model.isBusy).onDisappear { token = "" }
    }

    private func integrationStep(_ title: String, detail: String, showsLink: Bool = false) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.headline)
            Text(detail).font(.subheadline).foregroundStyle(.secondary)
            if showsLink {
                Button {
                    openURL(URL(string: "https://www.notion.so/profile/integrations")!)
                } label: {
                    Label("Open Notion", systemImage: "arrow.up.right")
                }.buttonStyle(.bordered)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
    }
}

struct DestinationPicker: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var pages: [NotionPage] = []
    @State private var loading = false
    @State private var error: String?
    @State private var reload = UUID()

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView("Finding accessible pages…")
                } else if let error {
                    ContentUnavailableView {
                        Label("Couldn’t load pages", systemImage: "wifi.exclamationmark")
                    } description: { Text(error) } actions: { Button("Retry") { reload = UUID() } }
                } else if pages.isEmpty {
                    ContentUnavailableView {
                        Label("No accessible pages", systemImage: "doc.text.magnifyingglass")
                    } description: {
                        Text("Share a page with your integration using Notion’s Connections menu. Search finds shared page titles; it cannot list every page in your workspace.")
                    } actions: { Button("Refresh") { reload = UUID() } }
                } else {
                    List(pages) { page in
                        Button {
                            model.chooseDestination(page)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(page.title).foregroundStyle(.primary)
                                Text("Page · \(page.id.prefix(8))").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Choose Notion Page")
            .searchable(text: $query, prompt: "Search accessible page titles")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task(id: "\(query):\(reload.uuidString)") {
                loading = true
                error = nil
                do {
                    try await Task.sleep(nanoseconds: 350_000_000)
                    guard let client = model.client else { error = "Connect Notion in Settings first."; loading = false; return }
                    let result = try await client.searchPages(query: query)
                    try Task.checkCancellation()
                    pages = result
                    loading = false
                } catch {
                    if Task.isCancelled { return }
                    self.error = error.localizedDescription
                    loading = false
                }
            }
        }
    }
}
