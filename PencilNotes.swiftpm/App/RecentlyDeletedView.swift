import SwiftUI

struct RecentlyDeletedView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var deleting: Note?
    @State private var deletingAll = false
    @State private var notesToDelete: [UUID] = []
    var body: some View {
        NavigationStack {
            List {
                if !model.deletedNotes.isEmpty {
                    Section {
                        HStack {
                            Button("Restore All", systemImage: "arrow.uturn.backward") {
                                let ids = model.deletedNotes.map(\.id)
                                for id in ids { model.restoreDeleted(id) }
                            }
                            Spacer()
                            Button("Delete All Permanently", systemImage: "trash", role: .destructive) {
                                notesToDelete = model.deletedNotes.map(\.id)
                                deletingAll = true
                            }.tint(.red)
                        }
                        .notebookGlassButtons()
                        .disabled(model.isBusy)
                    }
                }
                Section {
                    ForEach(model.deletedNotes) { note in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(note.title).font(.headline)
                            HStack {
                                Button("Restore", systemImage: "arrow.uturn.backward") { model.restoreDeleted(note.id) }
                                Spacer()
                                Button("Delete permanently", systemImage: "trash", role: .destructive) { deleting = note }
                                    .tint(.red)
                            }.notebookGlassButtons()
                        }.padding(.vertical, 6)
                    }
                } footer: { Text("Notes remain here until you restore or permanently delete them. Notion images are unchanged.") }
            }.overlay { if model.deletedNotes.isEmpty { ContentUnavailableView("🌿 No deleted notes", systemImage: "trash") } }
                .disabled(model.isBusy)
                .safeAreaInset(edge: .top, spacing: 0) {
                    if let message = model.errorMessage {
                        ErrorBanner(message: message) { model.errorMessage = nil }
                    }
                }
                .navigationTitle("🗑️ Recently Deleted")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }.notebookGlassButtons()
                    }
                }
                .alert("Permanently delete this note?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                    Button("Delete permanently", role: .destructive) { if let note = deleting { model.permanentlyDelete(note.id) }; deleting = nil }
                    Button("Cancel", role: .cancel) { deleting = nil }
                } message: { Text("This removes the local note and its recovery copies. It cannot be undone.") }
                .confirmationDialog("Permanently delete all \(notesToDelete.count) notes?",
                                    isPresented: $deletingAll, titleVisibility: .visible) {
                    Button("Delete All Permanently", role: .destructive) {
                        for id in notesToDelete { model.permanentlyDelete(id) }
                        notesToDelete.removeAll()
                    }
                    Button("Cancel", role: .cancel) { notesToDelete.removeAll() }
                } message: {
                    Text("This removes these local notes and their recovery copies. It cannot be undone. Notion images are unchanged.")
                }
        }
    }
}
