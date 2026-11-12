import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct NotebookView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingSettings = false
    @State private var importingBackup = false
    @State private var preferredColumn: NavigationSplitViewColumn = .sidebar

    var body: some View {
        NavigationSplitView(preferredCompactColumn: $preferredColumn) {
            VStack(spacing: 0) {
                if model.notes.isEmpty {
                    ContentUnavailableView("Your next idea starts here", systemImage: "pencil.and.scribble",
                        description: Text("Create a note, pick up your Pencil, and make room to think."))
                } else {
                    List {
                        ForEach(model.notes) { note in
                            Button { model.select(note.id) } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: "doc.text").font(.title2).foregroundStyle(.primary)
                                        .frame(width: 32, height: 42)
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(note.title).font(.headline).foregroundStyle(.primary).lineLimit(2)
                                        Text(note.updatedAt.formatted(date: .abbreviated, time: .omitted))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                    if model.selectedID == note.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(.primary) }
                                }.padding(.vertical, 7)
                            }.buttonStyle(.plain)
                        }
                    }.listStyle(.sidebar)
                }
                Button { model.newNote() } label: {
                    Label("New Note", systemImage: "plus").frame(maxWidth: .infinity).padding(.vertical, 6)
                }.buttonStyle(.borderedProminent).tint(.primary).padding()
            }
            .navigationTitle("PencilNotes")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Notion settings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { importingBackup = true } label: { Image(systemName: "square.and.arrow.down") }
                        .accessibilityLabel("Restore Backup")
                }
            }
        } detail: {
            if let note = model.selectedNote {
                NoteEditorView(noteID: note.id).id(note.id)
            } else {
                ContentUnavailableView {
                    Label("A little space for big ideas", systemImage: "pencil.tip.crop.circle")
                } description: {
                    Text("Handwrite notes, keep your original strokes, and send a copy to Notion when you’re ready.")
                } actions: {
                    Button("Create your first note") { model.newNote() }.buttonStyle(.borderedProminent)
                }
            }
        }
        .background(NotebookTheme.surface)
        .allowsHitTesting(!model.isBusy)
        .onChange(of: model.selectedID) { _, id in
            preferredColumn = id == nil ? .sidebar : .detail
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let error = model.errorMessage { ErrorBanner(message: error) { model.errorMessage = nil } }
            if !model.storageIssues.isEmpty {
                DisclosureGroup("Storage needs attention (\(model.storageIssues.count))") {
                    ForEach(Array(model.storageIssues.enumerated()), id: \.offset) { _, issue in
                        Text(issue).font(.caption).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                    }
                }.padding().background(.yellow.opacity(0.14))
            }
        }
        .overlay {
            if model.isBusy {
                VStack(spacing: 16) {
                    ProgressView()
                    Text(model.progress).font(.headline).multilineTextAlignment(.center)
                    Text("Your local notes remain saved.").font(.caption).foregroundStyle(.secondary)
                }.padding(30).frame(maxWidth: 380).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22)).shadow(radius: 15)
            }
        }
        .sheet(isPresented: $showingSettings) { NotionSettingsView() }
        .sheet(item: $model.sharePayload) { payload in ShareSheet(files: payload.files) }
        .fileImporter(isPresented: $importingBackup, allowedContentTypes: [.data, .json], allowsMultipleSelection: false) { result in
            do { if let url = try result.get().first { model.importBackup(url: url) } }
            catch { model.errorMessage = error.localizedDescription }
        }
    }
}

struct ErrorBanner: View {
    let message: String
    let dismiss: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.primary)
            Text(message).font(.callout).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            Button(action: dismiss) { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("Dismiss message")
        }.padding().background(.regularMaterial)
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let files: [URL]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: files, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            // A separate directory per export avoids deleting another active share's files.
            for directory in Set(files.map { $0.deletingLastPathComponent() }) {
                try? FileManager.default.removeItem(at: directory)
            }
        }
        return controller
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
