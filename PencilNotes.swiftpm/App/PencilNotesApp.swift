import SwiftUI

@main
struct PencilNotesApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            NotebookView()
                .environmentObject(model)
                .tint(.teal)
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active { model.saveNow() }
                }
        }
    }
}
