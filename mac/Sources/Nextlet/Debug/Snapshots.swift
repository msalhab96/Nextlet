import AppKit
import Foundation
import NextletCore
import SwiftUI

/// `Nextlet --snapshot <folder> <server> [--dark]`
///
/// Renders the main surfaces of the app with real data into PNG files, using
/// windows placed far off screen, so nothing appears on the display. Used to
/// check the layout without clicking through the app by hand.
@MainActor
enum Snapshots {
    private final class OffscreenWindow: NSWindow {
        override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    }

    private static let origin = CGPoint(x: -40_000, y: -40_000)
    /// Light by default; `--dark` renders everything dark and adds "-dark" to the file names.
    private static var appearance = NSAppearance.Name.aqua
    private static var suffix = ""

    static func run(folder: String, server: String, dark: Bool = false) {
        appearance = dark ? .darkAqua : .aqua
        suffix = dark ? "-dark" : ""
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        NSApp.appearance = NSAppearance(named: appearance)
        FontBook.register()
        let output = URL(fileURLWithPath: folder, isDirectory: true)
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        let suiteName = "nextlet.snapshots.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let settings = AppSettings(defaults: defaults)
        settings.serverAddress = server
        let store = Store(settings: settings)
        let focus = FocusController(defaults: defaults)
        let panelState = PanelState()

        func environment<V: View>(_ view: V) -> some View {
            view
                .environment(store)
                .environment(focus)
                .environment(settings)
                .environment(panelState)
        }

        Task { @MainActor in
            await store.load()
            if store.phase == .locked {
                let main = CGSize(width: 1280, height: 800)
                await render("mac-locked-window", environment(MainWindow()), size: main, titled: true, into: output)
                await render("mac-locked-menu-bar", environment(MenuBarView()), size: nil, titled: false, into: output)
                defaults.removePersistentDomain(forName: suiteName)
                print("Wrote the sign-in snapshots to \(output.path)")
                exit(0)
            }
            guard store.phase == .ready else {
                print("Could not load from \(server): \(store.phase)")
                exit(1)
            }

            let main = CGSize(width: 1280, height: 800)
            store.select(store.nextUp?.id)
            await render("mac-01-today", environment(MainWindow()), size: main, titled: true, into: output)

            store.select(nil)
            store.groupByProject = true
            await render("mac-02-today-by-project", environment(MainWindow()), size: main, titled: true, into: output)
            store.groupByProject = false

            store.route = .upcoming
            await render("mac-03-upcoming-week", environment(MainWindow()), size: main, titled: true, into: output)
            store.upcomingMode = .month
            await render("mac-04-upcoming-month", environment(MainWindow()), size: main, titled: true, into: output)
            store.upcomingMode = .week

            store.route = .inbox
            await render("mac-05-inbox", environment(MainWindow()), size: main, titled: true, into: output)

            if let project = store.projects.first {
                store.route = .project(project.id)
                await render("mac-06-project", environment(MainWindow()), size: main, titled: true, into: output)
            }

            store.route = .focus
            await render("mac-07-focus-picker", environment(MainWindow()), size: main, titled: true, into: output)
            if let next = store.nextUp {
                focus.start(taskID: next.id, minutes: next.estimateMinutes ?? 25)
                await render("mac-08-focus-running", environment(MainWindow()), size: main, titled: true, into: output)
                await render("mac-09-focus-timer-panel", environment(FocusTimerPanel(onHide: {})), size: nil, titled: false, into: output)
                await render("mac-10-menu-bar", environment(MenuBarView()), size: nil, titled: false, into: output)
                focus.finish()
                await render("mac-11-focus-timer-done", environment(FocusTimerPanel(onHide: {})), size: nil, titled: false, into: output)
                focus.end()
            }

            store.route = .today
            store.searchText = "budget"
            await render("mac-12-search", environment(MainWindow()), size: main, titled: true, into: output, wait: 2.0)
            store.searchText = ""

            await render(
                "mac-13-quick-capture",
                environment(QuickCaptureView(onClose: {}, initialText: "Call mom tomorrow #Personal !2")),
                size: nil, titled: false, into: output
            )
            await render("mac-14-settings", environment(SettingsView()), size: nil, titled: false, into: output)
            await render("mac-15-shortcuts", environment(ShortcutsView()), size: nil, titled: false, into: output)
            await render("mac-16-appearance", environment(AppearanceSettings().frame(width: 540)), size: nil, titled: false, into: output)

            defaults.removePersistentDomain(forName: suiteName)
            print("Wrote snapshots to \(output.path)")
            exit(0)
        }
        app.run()
    }

    private static func render<V: View>(_ name: String, _ view: V, size: CGSize?, titled: Bool, into folder: URL, wait: Double = 1.2) async {
        let style: NSWindow.StyleMask = titled ? [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView] : [.borderless]
        let hosting = NSHostingView(rootView: view)
        if titled { hosting.sceneBridgingOptions = [.toolbars, .title] }
        let initial = size ?? CGSize(width: 800, height: 600)
        let window = OffscreenWindow(contentRect: NSRect(origin: origin, size: initial), styleMask: style, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.isReleasedWhenClosed = false
        if !titled {
            window.isOpaque = false
            window.backgroundColor = .clear
        }
        window.contentView = hosting
        window.orderFrontRegardless()
        if size == nil {
            hosting.layoutSubtreeIfNeeded()
            window.setContentSize(hosting.fittingSize)
            window.setFrameOrigin(origin)
        }
        try? await Task.sleep(for: .seconds(wait))
        let target: NSView = titled ? (hosting.superview ?? hosting) : hosting
        target.layoutSubtreeIfNeeded()
        guard let rep = target.bitmapImageRepForCachingDisplay(in: target.bounds) else { return }
        target.cacheDisplay(in: target.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: folder.appendingPathComponent("\(name)\(suffix).png"))
        }
        window.orderOut(nil)
        window.contentView = nil
    }
}
