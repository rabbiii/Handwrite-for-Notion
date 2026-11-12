import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct NotebookView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var search = ""
    @State private var showingNoteActions = false
    @State private var pendingBackupImport = false
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
    @State private var swipedNoteID: UUID?

    // The reference iPad screenshot has a 700-pixel sidebar at 2x scale.
    private let sidebarWidth: CGFloat = 350
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
            .frame(maxHeight: .infinity)
            .navigationSplitViewColumnWidth(min: sidebarWidth, ideal: sidebarWidth, max: sidebarWidth)
            .notebookSidebarGlass()
            .toolbarBackground(.hidden, for: .navigationBar, .bottomBar)
            .navigationTitle("PencilNotes")
            .toolbar {
                ToolbarItem(placement: .bottomBar) {
                    Menu("Library", systemImage: "line.3.horizontal.decrease") {
                        Picker("Sort", selection: $sort) {
                            Text("Last updated").tag("Updated")
                            Text("Title").tag("Title")
                            Text("Date created").tag("Created")
                        }
                        Button("Recently Deleted", systemImage: "trash") { showingTrash = true }
                    }
                }
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button { showingSettings = true } label: { Text("⚙️") }
                        .accessibilityLabel("Settings")
                    SupportShortcut()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingNoteActions = true } label: {
                        Image(systemName: "ellipsis")
                            .overlay(alignment: .topTrailing) {
                                if !search.isEmpty {
                                    Circle().fill(.orange).frame(width: 6, height: 6)
                                        .offset(x: 5, y: -4).accessibilityHidden(true)
                                }
                            }
                    }
                    .accessibilityLabel("Search and note actions")
                    .accessibilityValue(search.isEmpty ? "" : "Search filter active")
                    .popover(isPresented: $showingNoteActions, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
                        noteActionsPopover
                            .presentationCompactAdaptation(.popover)
                            .onDisappear {
                                // Present the file picker only after this popover closes.
                                if pendingBackupImport {
                                    pendingBackupImport = false
                                    importingBackup = true
                                }
                            }
                    }
                }
            }
        } detail: {
            ZStack {
                if let note = model.selectedNote {
                    NoteEditorView(noteID: note.id, onCanvasInteractionBegan: hideSidebarForCanvas).id(note.id)
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
        // Keep canvas geometry stable when the sidebar hides during a stroke.
        .navigationSplitViewStyle(.prominentDetail)
        .background(NotebookTheme.surface)
        .allowsHitTesting(!model.isBusy)
        .onChange(of: model.selectedID) { _, id in
            swipedNoteID = nil
            preferredColumn = .detail
            if id == nil { columnVisibility = .all }
        }
        .onChange(of: model.notes.map(\.id)) { _, ids in
            if let swipedNoteID, !ids.contains(swipedNoteID) { self.swipedNoteID = nil }
            bulkSelection.formIntersection(ids)
            if ids.isEmpty { finishSelecting() }
        }
        .onChange(of: isEditing) { _, _ in swipedNoteID = nil }
        .onChange(of: search) { _, _ in swipedNoteID = nil }
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

    private var noteActionsPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Notes").font(.headline)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search notes", text: $search)
                    .textFieldStyle(.plain)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { showingNoteActions = false }
                    .accessibilityLabel("Search notes by title")
                if !search.isEmpty {
                    Button { search = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary).frame(width: 44, height: 44)
                    }.buttonStyle(.plain).accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .floatingGlass()
            if !search.isEmpty {
                Text("\(visibleNotes.count) \(visibleNotes.count == 1 ? "note" : "notes") found")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            Button {
                showingNoteActions = false
                withAnimation(noteAnimation) {
                    isEditing.toggle()
                    bulkSelection.removeAll()
                    if isEditing { preferredColumn = .sidebar }
                }
            } label: {
                selectionControlLabel(isEditing ? "Done selecting" : "Edit notes",
                                      icon: isEditing ? "checkmark" : "checklist")
            }
            .notebookGlassButtons()
            .disabled(model.notes.isEmpty)
            Button {
                pendingBackupImport = true
                showingNoteActions = false
            } label: {
                selectionControlLabel("Restore Backup", icon: "square.and.arrow.down")
            }.notebookGlassButtons()
        }
        .foregroundStyle(Color.primary)
        .frame(width: 280)
        .padding(16)
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
                .notebookGlassButtons().foregroundStyle(Color.primary)
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
                GlassNoteSwipeRow(noteID: note.id, revealedID: $swipedNoteID, enabled: !isEditing,
                                  canDelete: !model.isSyncing,
                                  rename: { startRenaming(note) },
                                  delete: { noteToDelete = note; deleting = true }) {
                    NoteSidebarRow(note: note, isSelected: model.selectedID == note.id && !isEditing, isEditing: isEditing,
                                   isBulkSelected: bulkSelection.contains(note.id),
                                   onSelect: {
                                       withAnimation(noteAnimation) {
                                           if swipedNoteID != nil { swipedNoteID = nil; return }
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
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .animation(noteAnimation, value: model.selectedID)
    }

    private var selectionActions: some View {
        VStack(spacing: 12) {
            Text("\(bulkSelection.count) selected").font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10),
                                     count: dynamicTypeSize.isAccessibilitySize ? 1 : 2), spacing: 10) {
                Button { bulkSelection = Set(visibleNotes.map(\.id)) } label: {
                    selectionControlLabel("Select All")
                }
                .notebookGlassButtons()
                .disabled(visibleNotes.allSatisfy { bulkSelection.contains($0.id) })
                Button { bulkSelection.removeAll() } label: {
                    selectionControlLabel("Unselect All")
                }
                .notebookGlassButtons()
                .disabled(bulkSelection.isEmpty)
                Menu {
                    if bulkSelection.count == 1, let note = model.notes.first(where: { bulkSelection.contains($0.id) }) {
                        Button("Rename", systemImage: "pencil") { startRenaming(note) }
                    }
                    Button("Share images", systemImage: "square.and.arrow.up") { model.shareNotes(bulkSelection) }
                    Button("Export backups", systemImage: "externaldrive") { model.shareNotes(bulkSelection, editableBackup: true) }
                } label: {
                    selectionControlLabel("Actions", icon: "ellipsis.circle")
                }
                .notebookGlassButtons()
                .disabled(bulkSelection.isEmpty)
                Button(role: .destructive) {
                    notesToDelete = bulkSelection
                    deletingSelection = true
                } label: {
                    selectionControlLabel("Delete", icon: "trash")
                }
                .notebookGlassButtons().tint(.red)
                .disabled(bulkSelection.isEmpty || model.isSyncing)
            }
        }
        .padding(12)
        .floatingGlass()
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private func selectionControlLabel(_ title: String, icon: String? = nil) -> some View {
        HStack(spacing: 6) {
            if let icon { Image(systemName: icon) }
            Text(title)
        }
        .font(.subheadline.weight(.medium))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity, minHeight: 44)
        .contentShape(Capsule())
    }

    private func hideSidebarForCanvas() {
        guard !isEditing, columnVisibility != .detailOnly else { return }
        swipedNoteID = nil
        showingNoteActions = false
        preferredColumn = .detail
        if reduceMotion {
            columnVisibility = .detailOnly
        } else {
            withAnimation(.easeOut(duration: 0.2)) { columnVisibility = .detailOnly }
        }
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

/// Real SwiftUI buttons allow custom glass; native swipeActions flatten their labels.
private struct GlassNoteSwipeRow<Content: View>: View {
    let noteID: UUID
    @Binding var revealedID: UUID?
    let enabled: Bool
    let canDelete: Bool
    let rename: () -> Void
    let delete: () -> Void
    @ViewBuilder let content: () -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var dragOffset: CGFloat = 0
    private let revealWidth: CGFloat = 120

    private var revealed: Bool { enabled && revealedID == noteID }
    private var animation: Animation { .easeOut(duration: reduceMotion ? 0 : 0.2) }
    private var offset: CGFloat {
        enabled ? min(0, max(-revealWidth, (revealed ? -revealWidth : 0) + dragOffset)) : 0
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: 12) {
                Button {
                    close(); rename()
                } label: { actionIcon("pencil", color: .blue) }
                    .accessibilityLabel("Rename note")
                Button(role: .destructive) {
                    close(); delete()
                } label: { actionIcon("trash.fill", color: .red) }
                    .accessibilityLabel("Delete note").disabled(!canDelete)
                    .opacity(canDelete ? 1 : 0.4)
            }
            .buttonStyle(PressFeedback())
            .padding(.trailing, 6)
            .opacity(min(1, -offset / revealWidth))
            .allowsHitTesting(revealed && dragOffset == 0)
            .accessibilityHidden(!revealed)

            content()
                .offset(x: offset)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 20)
                        .updating($dragOffset) { value, translation, _ in
                            guard enabled, abs(value.translation.width) > abs(value.translation.height) * 1.3 else { return }
                            translation = value.translation.width
                        }
                        .onEnded { value in
                            guard enabled, abs(value.translation.width) > abs(value.translation.height) * 1.3 else { return }
                            let projected = (revealed ? -revealWidth : 0) + value.predictedEndTranslation.width
                            withAnimation(animation) {
                                revealedID = projected < -revealWidth / 2 ? noteID : nil
                            }
                        }
                )
        }
        .animation(animation, value: revealed)
        .clipped()
        .accessibilityActions {
            if enabled {
                Button("Rename note") { close(); rename() }
                if canDelete { Button("Delete note") { close(); delete() } }
            }
        }
    }

    private func close() { withAnimation(animation) { revealedID = nil } }

    private func actionIcon(_ name: String, color: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 48, height: 48)
            .modifier(SwipeActionGlass())
    }
}

private struct SwipeActionGlass: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: Circle())
        } else {
            content.background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(.primary.opacity(0.18), lineWidth: 0.5))
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
