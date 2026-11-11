// swift-tools-version: 5.9
import PackageDescription

// Portable domain, storage, and network tests. Open PencilNotes.swiftpm on iPad.
let package = Package(
    name: "PencilNotesCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "PencilNotesCore", targets: ["PencilNotesCore"])],
    targets: [
        .target(name: "PencilNotesCore", path: "PencilNotes.swiftpm/Core"),
        .testTarget(name: "PencilNotesCoreTests", dependencies: ["PencilNotesCore"], path: "Tests/PencilNotesCoreTests")
    ]
)
