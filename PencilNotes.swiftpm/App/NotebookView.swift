import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct NotebookView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingSettings = false
    @State private var importingBackup = false
    @State private var preferredColumn: NavigationSplitViewColumn = .detail
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var renaming = false
    @State private var noteToRename: Note?
    @State private var titleDraft = ""
    @State private var deleting = false
    @State private var noteToDelete: Note?

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility, preferredCompactColumn: $preferredColumn) {
            VStack(spacing: 0) {
                if model.notes.isEmpty {
                    ContentUnavailableView("Your next idea starts here", systemImage: "pencil.and.scribble",
                        description: Text("Create a note, pick up your Pencil, and make room to think."))
                } else {
                    List {
                        ForEach(model.notes) { note in
                            NoteSidebarRow(note: note, isSelected: model.selectedID == note.id,
                                           onSelect: { model.select(note.id) }, onClose: { model.closeNote() })
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button("Delete", systemImage: "trash", role: .destructive) {
                                        noteToDelete = note
                                        deleting = true
                                    }.disabled(model.isSyncing)
                                    Button("Rename", systemImage: "pencil") {
                                        noteToRename = note
                                        titleDraft = note.title
                                        renaming = true
                                    }
                                }
                        }
                    }.listStyle(.sidebar)
                }
                Button { model.newNote() } label: {
                    Label("New Note", systemImage: "plus").frame(maxWidth: .infinity).padding(.vertical, 6)
                }.buttonStyle(.borderedProminent).tint(.primary).foregroundStyle(NotebookTheme.surface).padding()
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
                    Label("What's on your mind?", systemImage: "pencil.tip.crop.circle")
                } description: {
                    Text(model.notes.isEmpty
                         ? "Create your first note and make room to think."
                         : "Choose a note from the sidebar or start something new.")
                } actions: {
                    VStack(spacing: 16) {
                        Button { model.newNote() } label: {
                            Label("New Note", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent).tint(.primary).foregroundStyle(NotebookTheme.surface)
                        Text(model.notes.count == 1 ? "1 note on this iPad" : "\(model.notes.count) notes on this iPad")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .background(NotebookTheme.surface)
        .allowsHitTesting(!model.isBusy)
        .onChange(of: model.selectedID) { _, id in
            preferredColumn = .detail
            if id == nil { columnVisibility = .all }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let error = model.errorMessage { ErrorBanner(message: error) { model.errorMessage = nil } }
            if !model.storageIssues.isEmpty {
                DisclosureGroup("Storage needs attention (\(model.storageIssues.count))") {
                    ForEach(Array(model.storageIssues.enumerated()), id: \.offset) { _, issue in
                        Text(issue).font(.caption).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                    }
                }.padding().background(.regularMaterial)
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
        .alert("Rename note", isPresented: $renaming, presenting: noteToRename) { note in
            TextField("Title", text: $titleDraft)
            Button("Save") { model.rename(titleDraft, noteID: note.id) }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete this note and its local recovery copies? Its Notion image will remain.",
                            isPresented: $deleting, titleVisibility: .visible, presenting: noteToDelete) { note in
            Button("Delete note", role: .destructive) { model.deleteNote(note.id) }
                .disabled(model.isSyncing)
        } message: { note in
            Text(note.title)
        }
        .fileImporter(isPresented: $importingBackup, allowedContentTypes: [.data, .json], allowsMultipleSelection: false) { result in
            do { if let url = try result.get().first { model.importBackup(url: url) } }
            catch { model.errorMessage = error.localizedDescription }
        }
    }
}

private struct NoteSidebarRow: View {
    let note: Note
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    private static let icons = [
        "book.closed", "pencil", "paintbrush", "lightbulb", "leaf", "star",
        "moon", "sun.max", "bolt", "sparkles", "heart", "paperplane"
    ]

    var body: some View {
        Group {
            if isSelected {
                content.floatingGlass()
                    .overlay {
                        RoundedRectangle(cornerRadius: 24).stroke(.primary.opacity(0.35), lineWidth: 1)
                            .allowsHitTesting(false)
                    }
            } else {
                content
            }
        }
        .foregroundStyle(.primary)
        .accessibilityElement(children: .contain)
    }

    private var content: some View {
        HStack(alignment: .top, spacing: 4) {
            Button(action: onSelect) {
                HStack(spacing: 12) {
                    // UUIDs are random and persisted, so icons stay stable across edits and launches.
                    Image(systemName: Self.icons[Int(note.id.uuid.0) % Self.icons.count])
                        .font(.title2).frame(width: 32).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(note.title).font(.headline).lineLimit(2)
                        Text(note.updatedAt.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3).opacity(isSelected ? 1 : 0).accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isSelected ? .isSelected : [])

            if isSelected {
                Button(action: onClose) {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 26)).symbolRenderingMode(.hierarchical)
                        .frame(width: 44, height: 44).contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close note")
                .accessibilityHint("Saves this note and returns to Home")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 24))
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
