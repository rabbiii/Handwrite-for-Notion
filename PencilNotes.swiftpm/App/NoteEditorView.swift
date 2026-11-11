import SwiftUI

struct NoteEditorView: View {
    let noteID: UUID
    @EnvironmentObject private var model: AppModel
    @StateObject private var canvasActions = CanvasActions()
    @State private var fingerDrawing = false
    @State private var choosingPage = false
    @State private var renaming = false
    @State private var titleDraft = ""
    @State private var deletingNote = false
    @State private var deletingPage = false
    @State private var resolvingSync = false
    @State private var resettingLink = false

    private var note: Note? { model.notes.first { $0.id == noteID } }
    var body: some View {
        if let note {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        Button { canvasActions.undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                        Button { canvasActions.redo() } label: { Label("Redo", systemImage: "arrow.uturn.forward") }
                        Divider().frame(height: 24)
                        Toggle(isOn: $fingerDrawing) { Label("Draw with finger", systemImage: "hand.draw") }
                            .toggleStyle(.button)
                        Button { model.saveNow() } label: { Label("Save", systemImage: "checkmark.circle") }
                        Menu {
                            Button("PNG · all pages", systemImage: "photo") { model.export(.png) }
                            Button("PDF · all pages", systemImage: "doc.richtext") { model.export(.pdf) }
                            Button("Editable Backup", systemImage: "externaldrive") { model.exportBackup() }
                        } label: { Label("Export", systemImage: "square.and.arrow.up") }
                    }.buttonStyle(.bordered).padding(.horizontal).padding(.vertical, 10)
                }.background(.bar)

                if let page = model.selectedPage {
                    InkCanvas(drawingData: page.drawing, fingerDrawing: fingerDrawing, actions: canvasActions) { data in
                        model.drawingChanged(data, pageID: page.id)
                    }.id("\(note.id.uuidString):\(page.id.uuidString)")
                }

                HStack {
                    Button { model.movePage(-1) } label: { Image(systemName: "chevron.left") }
                        .disabled(model.pageIndex == 0).accessibilityLabel("Previous page")
                    Text("Page \(model.pageIndex + 1) of \(note.pages.count)").font(.subheadline.monospacedDigit())
                    Button { model.movePage(1) } label: { Image(systemName: "chevron.right") }
                        .disabled(model.pageIndex >= note.pages.count - 1).accessibilityLabel("Next page")
                    Button { model.addPage() } label: { Label("Add Page", systemImage: "plus") }
                    Spacer()
                    Text(model.saveStatus).font(.caption).foregroundStyle(.secondary)
                }.buttonStyle(.borderless).padding(.horizontal).padding(.vertical, 10)

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Button { choosingPage = true } label: {
                            Label(note.destination?.title ?? "Choose Notion Page", systemImage: "doc.badge.arrow.up")
                                .lineLimit(1)
                        }.disabled(model.client == nil)
                        Spacer()
                        Picker("Sync format", selection: $model.syncFormat) {
                            Text("PDF").tag(ExportFormat.pdf)
                            Text("PNG").tag(ExportFormat.png)
                        }.pickerStyle(.segmented).frame(width: 125)
                        Button { Task { await model.sync() } } label: {
                            Label("Sync to Notion", systemImage: "arrow.up.doc")
                        }.buttonStyle(.borderedProminent)
                    }
                    if !model.progress.isEmpty { Text(model.progress).font(.caption).foregroundStyle(.teal) }
                    Text(model.client == nil ? "Connect Notion in Settings to send a copy. Your notes work offline." : "Notion receives a PDF or image. Your editable handwriting stays on this iPad.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(fingerDrawing ? "Draw with Pencil or one finger. Use two fingers to pan and pinch to zoom." : "Draw with Pencil. Use one finger to scroll and pinch to zoom.")
                        .font(.caption2).foregroundStyle(.secondary)
                }.padding().background(.bar)
            }
            .navigationTitle(note.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Rename Note", systemImage: "pencil") { titleDraft = note.title; renaming = true }
                        Button("Delete Current Page", systemImage: "doc.badge.minus", role: .destructive) { deletingPage = true }
                            .disabled(note.pages.count == 1)
                        if note.sync?.pendingMarker != nil {
                            Button("Resolve uncertain sync", systemImage: "questionmark.circle") { resolvingSync = true }
                        } else if note.sync?.blockID != nil {
                            Button("Reset Notion link", systemImage: "arrow.triangle.2.circlepath") { resettingLink = true }
                        }
                        Button("Delete Note", systemImage: "trash", role: .destructive) { deletingNote = true }
                    } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("Note actions")
                }
            }
            .sheet(isPresented: $choosingPage) { DestinationPicker() }
            .alert("Rename note", isPresented: $renaming) {
                TextField("Title", text: $titleDraft)
                Button("Save") { model.rename(titleDraft) }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog("Delete this note and its local recovery copies? Export an editable backup first if needed. The Notion copy stays in Notion.", isPresented: $deletingNote, titleVisibility: .visible) {
                Button("Delete Note", role: .destructive) { model.deleteSelected() }
            }
            .confirmationDialog("Permanently remove page \(model.pageIndex + 1) from this note?", isPresented: $deletingPage, titleVisibility: .visible) {
                Button("Delete Page", role: .destructive) { model.removePage() }
            }
            .confirmationDialog("First inspect the destination in Notion. Only reset this attempt if its PencilNotes block is absent. A delayed Notion response can otherwise create a duplicate.", isPresented: $resolvingSync, titleVisibility: .visible) {
                Button("I checked: no block exists", role: .destructive) { model.resolveUncertainSync() }
            }
            .confirmationDialog("Use this if the linked Notion block was deleted or moved. Next sync searches the selected page and updates a matching block, or creates one if absent. A block moved to another page stays there.", isPresented: $resettingLink, titleVisibility: .visible) {
                Button("Reset Notion link") { model.resetNotionLink() }
            }
        }
    }
}
