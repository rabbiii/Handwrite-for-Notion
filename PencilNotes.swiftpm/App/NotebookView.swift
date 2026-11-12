import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct NotebookView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var search = ""
    @AppStorage("noteSort") private var sort = "Updated"
    @State private var showingTrash = false
    @State private var showingSettings = false
    @State private var importingBackup = false
    @State private var preferredColumn: NavigationSplitViewColumn = .detail
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var renaming = false
    @State private var noteToRename: Note?
    @State private var titleDraft = ""
    @State private var deleting = false
    @State private var noteToDelete: Note?
    @State private var isEditing = false
    @State private var bulkSelection = Set<UUID>()
    @State private var deletingSelection = false
    @State private var notesToDelete = Set<UUID>()

    private var noteAnimation: Animation { reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.85) }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility, preferredCompactColumn: $preferredColumn) {
            VStack(spacing: 0) {
                if model.notes.isEmpty {
                    ContentUnavailableView("✨ Your next idea starts here", systemImage: "pencil.and.scribble",
                        description: Text("Create a note, pick up your Pencil, and make room to think."))
                } else {
                    noteList
                }
                if isEditing {
                    selectionActions
                } else {
                    Button { withAnimation(noteAnimation) { model.newNote() } } label: {
                        Label("✍️ New Note", systemImage: "plus").frame(maxWidth: .infinity).padding(.vertical, 6)
                    }.buttonStyle(.borderedProminent).tint(.primary).foregroundStyle(NotebookTheme.surface).padding()
                }
            }
            .searchable(text: $search, prompt: "Search notes")
            .navigationTitle("PencilNotes")
            .toolbar {
                ToolbarItem(placement: .bottomBar) {
                    Menu("Library", systemImage: "line.3.horizontal.decrease") {
                        Picker("Sort", selection: $sort) {
                            Text("Last updated").tag("Updated")
                            Text("Title").tag("Title")
                            Text("Date created").tag("Created")
                        }
                        Button("🗑️ Recently Deleted", systemImage: "trash") { showingTrash = true }
                    }
                }
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button { showingSettings = true } label: { Text("⚙️") }
                        .accessibilityLabel("Settings")
                    SupportShortcut()
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { importingBackup = true } label: { Image(systemName: "square.and.arrow.down") }
                        .accessibilityLabel("Restore Backup")
                    Button(isEditing ? "Done" : "Edit") {
                        withAnimation(noteAnimation) {
                            isEditing.toggle()
                            bulkSelection.removeAll()
                            if isEditing { preferredColumn = .sidebar }
                        }
                    }.disabled(model.notes.isEmpty)
                }
            }
        } detail: {
            ZStack {
                if let note = model.selectedNote {
                    NoteEditorView(noteID: note.id).id(note.id)
                        .transition(.opacity.combined(with: .scale(scale: reduceMotion ? 1 : 0.98)))
                } else {
                    welcomeView.transition(.opacity)
                }
            }
            .animation(noteAnimation, value: model.selectedID)
            .overlay {
                if isEditing {
                    Color.clear.contentShape(Rectangle()).ignoresSafeArea()
                        .onTapGesture { finishSelecting() }
                        .accessibilityLabel("Finish selecting notes")
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { finishSelecting() }
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
        .onChange(of: model.notes.map(\.id)) { _, ids in
            bulkSelection.formIntersection(ids)
            if ids.isEmpty { finishSelecting() }
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
        .sheet(isPresented: $showingTrash) { RecentlyDeletedView() }
        .sheet(isPresented: $showingSettings) { NotionSettingsView() }
        .sheet(item: $model.sharePayload) { payload in ShareSheet(files: payload.files) }
        .alert("Rename note", isPresented: $renaming, presenting: noteToRename) { note in
            TextField("Title", text: $titleDraft)
            Button("Save") { model.rename(titleDraft, noteID: note.id) }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Move this note to Recently Deleted? Its Notion image will remain.",
                            isPresented: $deleting, titleVisibility: .visible, presenting: noteToDelete) { note in
            Button("Delete note", role: .destructive) { model.deleteNote(note.id) }
                .disabled(model.isSyncing)
        } message: { note in
            Text(note.title)
        }
        .confirmationDialog("Delete \(notesToDelete.count) selected notes?", isPresented: $deletingSelection, titleVisibility: .visible) {
            Button("Delete notes", role: .destructive) {
                withAnimation(noteAnimation) { bulkSelection.subtract(model.deleteNotes(notesToDelete)) }
            }.disabled(model.isSyncing)
        } message: {
            Text("Notes can be restored from Recently Deleted. Notion images stay on their pages.")
        }
        .fileImporter(isPresented: $importingBackup, allowedContentTypes: [.data, .json], allowsMultipleSelection: false) { result in
            do { if let url = try result.get().first { model.importBackup(url: url) } }
            catch { model.errorMessage = error.localizedDescription }
        }
    }

    private var welcomeView: some View {
        ContentUnavailableView {
            Text("💡 What's on your mind?")
                .font(.title.weight(.bold))
        } description: {
            Text(model.notes.isEmpty
                 ? "🌱 Create your first note and make room to think."
                 : "📚 Choose a note from the sidebar or start something new.")
        } actions: {
            VStack(spacing: 16) {
                Button { withAnimation(noteAnimation) { model.newNote() } } label: {
                    Label("✍️ New Note", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent).tint(.primary).foregroundStyle(NotebookTheme.surface)
                Text(model.notes.count == 1 ? "1 note on this iPad" : "\(model.notes.count) notes on this iPad")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var visibleNotes: [Note] {
        model.notes.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }.sorted {
            if ($0.isPinned ?? false) != ($1.isPinned ?? false) { return $0.isPinned ?? false }
            if sort == "Title" { return $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            if sort == "Created" { return $0.createdAt > $1.createdAt }
            return $0.updatedAt > $1.updatedAt
        }
    }
    private var noteList: some View {
        List {
            ForEach(visibleNotes) { note in
                NoteSidebarRow(note: note, isSelected: model.selectedID == note.id && !isEditing, isEditing: isEditing,
                               isBulkSelected: bulkSelection.contains(note.id),
                               onSelect: {
                                   withAnimation(noteAnimation) {
                                       if isEditing {
                                           if bulkSelection.contains(note.id) { bulkSelection.remove(note.id) }
                                           else { bulkSelection.insert(note.id) }
                                       } else { model.select(note.id) }
                                   }
                               },
                               onClose: { withAnimation(noteAnimation) { model.closeNote() } })
                    .contextMenu {
                        Button(note.isPinned == true ? "Unpin" : "Pin", systemImage: "pin") { model.togglePin(note.id) }
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            noteToDelete = note
                            deleting = true
                        } label: {
                            Image(uiImage: UIImage(systemName: "trash.fill")!.withTintColor(.systemRed, renderingMode: .alwaysOriginal))
                                .renderingMode(.original)
                        }.tint(Color(uiColor: .secondarySystemBackground))
                            .accessibilityLabel("Delete note").disabled(model.isSyncing || isEditing)
                        Button { startRenaming(note) } label: {
                            Image(uiImage: UIImage(systemName: "pencil")!.withTintColor(.systemBlue, renderingMode: .alwaysOriginal))
                                .renderingMode(.original)
                        }.tint(Color(uiColor: .secondarySystemBackground))
                            .accessibilityLabel("Rename note").disabled(isEditing)
                    }
            }
        }
        .listStyle(.sidebar)
        .animation(noteAnimation, value: model.selectedID)
    }

    private var selectionActions: some View {
        VStack(spacing: 10) {
            Text("\(bulkSelection.count) selected").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Select All") { bulkSelection = Set(visibleNotes.map(\.id)) }
                    .disabled(visibleNotes.allSatisfy { bulkSelection.contains($0.id) })
                Spacer()
                Button("Unselect All") { bulkSelection.removeAll() }.disabled(bulkSelection.isEmpty)
            }.buttonStyle(.bordered)
            HStack {
                Spacer()
                Menu {
                    if bulkSelection.count == 1, let note = model.notes.first(where: { bulkSelection.contains($0.id) }) {
                        Button("Rename", systemImage: "pencil") { startRenaming(note) }
                    }
                    Button("Share images", systemImage: "square.and.arrow.up") { model.shareNotes(bulkSelection) }
                    Button("Export backups", systemImage: "externaldrive") { model.shareNotes(bulkSelection, editableBackup: true) }
                } label: {
                    Label("Actions", systemImage: "ellipsis.circle")
                }.disabled(bulkSelection.isEmpty)
                Button(role: .destructive) {
                    notesToDelete = bulkSelection
                    deletingSelection = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }.buttonStyle(.bordered).tint(.red).disabled(bulkSelection.isEmpty || model.isSyncing)
            }
        }
        .padding().background(.bar)
    }

    private func startRenaming(_ note: Note) {
        noteToRename = note
        titleDraft = note.title
        renaming = true
    }

    private func finishSelecting() {
        withAnimation(noteAnimation) {
            isEditing = false
            bulkSelection.removeAll()
        }
    }
}

private struct NoteSidebarRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let note: Note
    let isSelected: Bool
    let isEditing: Bool
    let isBulkSelected: Bool
    @EnvironmentObject private var model: AppModel
    @State private var pickingIcon = false
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        content
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 24).fill(.clear).floatingGlass()
                        .transition(.opacity)
                }
            }
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 24).stroke(.primary.opacity(0.35), lineWidth: 1).allowsHitTesting(false)
                }
            }
            .foregroundStyle(.primary)
            .accessibilityElement(children: .contain)
    }

    private var content: some View {
        HStack(alignment: .center, spacing: 4) {
            if !isEditing {
                Button { pickingIcon = true } label: {
                    AnimatedNoteIcon(name: NoteIcons.name(for: note), active: isSelected)
                        .font(.title2).frame(width: 44, height: 44)
                }.buttonStyle(.plain).accessibilityLabel("Change note icon")
                    .popover(isPresented: $pickingIcon) {
                        NoteIconPicker(selected: NoteIcons.name(for: note)) { model.setIcon($0, for: note.id) }
                            .presentationCompactAdaptation(.sheet)
                    }
            }
            Button(action: onSelect) {
                HStack(spacing: 12) {
                    if isEditing {
                        Image(systemName: isBulkSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title2).foregroundStyle(isBulkSelected ? Color.blue : Color.secondary)
                            .accessibilityHidden(true)
                    }
                    noteLabel
                }.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isSelected || isBulkSelected ? .isSelected : [])
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20)).frame(width: 24, height: 44).accessibilityHidden(true)
                Button(action: onClose) {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 26)).symbolRenderingMode(.hierarchical)
                        .frame(width: 44, height: 44).contentShape(Circle())
                }
                .buttonStyle(PressFeedback())
                .accessibilityLabel("Close note")
                .accessibilityHint("Saves this note and returns to Home")
                .transition(.opacity.combined(with: .scale(scale: reduceMotion ? 1 : 0.8)))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 24))
    }

    private var noteLabel: some View {
        HStack(spacing: 12) {
            if isEditing { Image(systemName: NoteIcons.name(for: note)).font(.title2).frame(width: 32) }
            if note.isPinned == true { Image(systemName: "pin.fill").font(.caption).accessibilityLabel("Pinned") }
            VStack(alignment: .leading, spacing: 6) {
                Text(note.title).font(.headline).lineLimit(2)
                Text(note.updatedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }
}

struct ErrorBanner: View {
    let message: String
    let dismiss: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
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
