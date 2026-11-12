import SwiftUI

struct NoteEditorView: View {
    let noteID: UUID
    var onCanvasInteractionBegan: () -> Void = {}
    @EnvironmentObject private var model: AppModel
    @StateObject private var canvasActions = CanvasActions()
    @State private var fingerDrawing = false
    @State private var choosingPage = false
    @State private var renaming = false
    @State private var titleDraft = ""
    @State private var deletingNote = false
    @State private var clearingCanvas = false
    @State private var resolvingSync = false
    @State private var resettingLink = false
    @AppStorage("dottedPaperEnabled") private var dottedPaper = false

    private var note: Note? { model.notes.first { $0.id == noteID } }
    private var validTitleDraft: Bool {
        let title = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        return !title.isEmpty && title.count <= 200
    }
    var body: some View {
        if let note, let page = note.pages.first {
            ZStack(alignment: .top) {
                Color(uiColor: NotebookTheme.canvasBackground).ignoresSafeArea()
                InkCanvas(drawingData: page.drawing, fingerDrawing: fingerDrawing, dottedPaper: dottedPaper, actions: canvasActions,
                          changed: { model.drawingChanged($0, pageID: page.id) },
                          interaction: { active in
                              model.canvasInteraction(active)
                              if active { onCanvasInteractionBegan() }
                          })
                    .id("\(note.id.uuidString):\(page.id.uuidString)")
                    .ignoresSafeArea(edges: .bottom)
                    .notebookBackgroundExtension()

                VStack(alignment: .leading, spacing: 8) {
                    ScrollView(.horizontal, showsIndicators: true) {
                        HStack(spacing: 6) {
                            tool("Undo", "arrow.uturn.backward") { canvasActions.undo() }
                            tool("Redo", "arrow.uturn.forward") { canvasActions.redo() }
                            separator
                            Button { fingerDrawing.toggle() } label: {
                                Label("Finger", systemImage: "hand.draw")
                                    .padding(.horizontal, 12).padding(.vertical, 10)
                                    .background(fingerDrawing ? Color.primary.opacity(0.1) : .clear, in: Capsule())
                            }.accessibilityLabel("Draw with finger").accessibilityValue(fingerDrawing ? "On" : "Off")
                            tool("Clear canvas", "eraser") { clearingCanvas = true }
                            tool("Save", "checkmark.circle") { model.saveNow() }
                            Toggle(isOn: $dottedPaper) {
                                Label("Dotted paper", systemImage: "circle.grid.3x3")
                            }
                            .toggleStyle(.button)
                            .padding(.horizontal, 6)
                            .accessibilityIdentifier("dottedPaperToggle")
                            Menu {
                                Button("🖼️ Share image", systemImage: "square.and.arrow.up") { model.export() }
                                Button("📦 Editable backup", systemImage: "externaldrive") { model.exportBackup() }
                            } label: { Label("Export", systemImage: "square.and.arrow.up").padding(.horizontal, 12).padding(.vertical, 10) }
                            separator
                            tool(note.destination?.title ?? "Choose Notion page", "doc.badge.arrow.up") { choosingPage = true }
                                .disabled(model.client == nil || model.isSyncing)
                            Button { Task { await model.sync() } } label: {
                                HStack(spacing: 7) {
                                    if model.isSyncing { ProgressView().controlSize(.small) }
                                    else { Image(systemName: "arrow.up.doc") }
                                    Text("Sync to Notion")
                                }.padding(.horizontal, 12).padding(.vertical, 10)
                            }.disabled(model.isSyncing).accessibilityIdentifier("syncButton")
                            Button { model.autoSyncEnabled.toggle() } label: {
                                Label(model.autoSyncPaused ? "Auto sync paused" : "Auto sync",
                                      systemImage: model.autoSyncEnabled ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.triangle.2.circlepath.circle")
                                    .padding(.horizontal, 12).padding(.vertical, 10)
                                    .background(model.autoSyncEnabled ? Color.primary.opacity(0.1) : .clear, in: Capsule())
                            }.accessibilityIdentifier("autoSyncButton")
                                .accessibilityValue(model.autoSyncEnabled ? "On" : "Off")
                            Menu {
                                Button("Rename note", systemImage: "pencil") { beginRenaming(note) }
                                if note.sync?.pendingMarker != nil {
                                    Button("Resolve uncertain sync", systemImage: "questionmark.circle") { resolvingSync = true }
                                } else if note.sync?.blockID != nil {
                                    Button("Reset Notion link", systemImage: "arrow.triangle.2.circlepath") { resettingLink = true }
                                }
                                Button("Delete note", systemImage: "trash", role: .destructive) { deletingNote = true }
                            } label: { Image(systemName: "ellipsis").padding(12) }.accessibilityLabel("Note actions")
                        }.font(.subheadline.weight(.medium)).buttonStyle(.plain)
                            .foregroundStyle(.primary).padding(8)
                    }.fixedSize(horizontal: false, vertical: true)
                        .floatingGlass()
                    HStack(spacing: 6) {
                        Image(systemName: model.isSyncing ? "arrow.triangle.2.circlepath" : "checkmark")
                        Text(model.isSyncing || !model.progress.isEmpty ? model.progress : model.saveStatus)
                            .lineLimit(1)
                    }.font(.caption).foregroundStyle(.secondary)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .allowsHitTesting(false)
                }.padding(.horizontal, 12)
            }
            .navigationTitle(note.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Button { beginRenaming(note) } label: {
                        HStack(spacing: 6) {
                            Text(note.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Image(systemName: "pencil")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .foregroundStyle(Color.primary)
                        .frame(maxWidth: 240)
                    }
                    .notebookGlassButtons()
                    .controlSize(.small)
                    .frame(minHeight: 44)
                    .accessibilityLabel("Rename note: \(note.title)")
                    .accessibilityHint("Opens the note title editor")
                    .accessibilityIdentifier("renameTitleButton")
                }
            }
            .sheet(isPresented: $choosingPage) { DestinationPicker() }
            .alert("Rename note", isPresented: $renaming) {
                TextField("Title", text: $titleDraft)
                Button("Save") { model.rename(titleDraft, noteID: noteID) }
                    .disabled(!validTitleDraft)
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog("Clear every stroke? You can undo this while this note stays open.", isPresented: $clearingCanvas, titleVisibility: .visible) {
                Button("Clear canvas", role: .destructive) { canvasActions.clear() }
            }
            .confirmationDialog("Move this note to Recently Deleted? Its Notion image will remain.", isPresented: $deletingNote, titleVisibility: .visible) {
                Button("Delete note", role: .destructive) { model.deleteSelected() }.disabled(model.isSyncing)
            }
            .confirmationDialog("Inspect the original destination in Notion first. Only reset this attempt if its PencilNotes block is absent; a delayed response can otherwise cause a duplicate.", isPresented: $resolvingSync, titleVisibility: .visible) {
                Button("I checked: no block exists", role: .destructive) { model.resolveUncertainSync() }
            }
            .confirmationDialog("Next sync checks the selected page for this note and updates its image, or creates one if absent. A block moved elsewhere stays there.", isPresented: $resettingLink, titleVisibility: .visible) {
                Button("Reset Notion link") { model.resetNotionLink() }
            }
        }
    }
    private func beginRenaming(_ note: Note) {
        titleDraft = note.title
        renaming = true
    }

    private var separator: some View { Divider().frame(height: 22).padding(.horizontal, 2) }
    private func tool(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).lineLimit(1).padding(.horizontal, 12).padding(.vertical, 10)
        }
    }
}
