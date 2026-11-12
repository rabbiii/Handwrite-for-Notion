// swift-tools-version: 5.9
import PackageDescription
import AppleProductTypes

let package = Package(
    name: "PencilNotes",
    platforms: [.iOS("17.0")],
    products: [
        .iOSApplication(
            name: "PencilNotes",
            targets: ["AppModule"],
            bundleIdentifier: "app.pencilnotes.personal",
            teamIdentifier: "",
            displayVersion: "1.1",
            bundleVersion: "2",
            appIcon: .asset("AppIcon"),
            accentColor: .asset("AccentColor"),
            supportedDeviceFamilies: [.pad],
            supportedInterfaceOrientations: [.portrait, .landscapeLeft, .landscapeRight]
        )
    ],
    targets: [.executableTarget(name: "AppModule", path: ".", resources: [.process("Resources")])]
)
