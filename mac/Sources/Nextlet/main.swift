import AppKit
import Foundation

// `Nextlet --self-test <server>` drives the store against a running API and reports.
// `Nextlet --ui-test <server>` clicks and types through the real main window and checks the results.
// `Nextlet --snapshot <folder> <server> [--dark]` renders the main screens to PNG files.
// All of them run without showing anything and exit when done.
let arguments = CommandLine.arguments

MainActor.assumeIsolated {
    if let index = arguments.firstIndex(of: "--self-test") {
        let server = arguments.indices.contains(index + 1) ? arguments[index + 1] : "http://localhost:8080"
        let password = arguments.firstIndex(of: "--password").flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
        SelfTest.run(server: server, password: password)
    } else if let index = arguments.firstIndex(of: "--ui-test") {
        let server = arguments.indices.contains(index + 1) ? arguments[index + 1] : "http://localhost:8080"
        UITest.run(server: server)
    } else if let index = arguments.firstIndex(of: "--snapshot") {
        let folder = arguments.indices.contains(index + 1) ? arguments[index + 1] : FileManager.default.currentDirectoryPath
        let server = arguments.indices.contains(index + 2) ? arguments[index + 2] : "http://localhost:8080"
        Snapshots.run(folder: folder, server: server, dark: arguments.contains("--dark"))
    } else {
        NextletApp.main()
    }
}
