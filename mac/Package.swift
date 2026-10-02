// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Nextlet",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Nextlet", targets: ["Nextlet"]),
    ],
    targets: [
        // Days, models, quick add and task rules. No UI, fully unit tested.
        .target(name: "NextletCore"),
        // The Mac app: main window, menu bar extra, quick capture and focus timer.
        .executableTarget(name: "Nextlet", dependencies: ["NextletCore"]),
        .testTarget(name: "NextletCoreTests", dependencies: ["NextletCore"]),
    ],
    swiftLanguageModes: [.v5]
)
