import SwiftUI

@main
struct PencilNotesApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            NotebookView()
                .environmentObject(model)
                .tint(NotebookTheme.ink)
                .onChange(of: scenePhase) { _, phase in
                    model.setSceneActive(phase == .active)
                }
        }
    }
}
