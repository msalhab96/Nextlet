import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppEnvironment.shared.start()
    }

    /// Closing the window leaves Nextlet in the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { AppEnvironment.shared.showMainWindow() }
        return true
    }
}

struct NextletApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let env = AppEnvironment.shared

    var body: some Scene {
        Window("Nextlet", id: "main") {
            MainWindow()
                .environment(env.store)
                .environment(env.focus)
                .environment(env.settings)
                .environment(env.panelState)
        }
        .defaultSize(width: 1280, height: 800)
        .windowToolbarStyle(.unified)
        .commands { NextletCommands(env: env) }

        MenuBarExtra {
            MenuBarView()
                .environment(env.store)
                .environment(env.focus)
                .environment(env.settings)
                .environment(env.panelState)
        } label: {
            MenuBarLabel()
                .environment(env.store)
                .environment(env.focus)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(env.store)
                .environment(env.settings)
                .environment(env.panelState)
        }

        Window("Keyboard Shortcuts", id: "shortcuts") {
            ShortcutsView()
                .environment(env.settings)
        }
        .windowResizability(.contentSize)
    }
}

struct NextletCommands: Commands {
    let env: AppEnvironment
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Task") { env.newTask() }
                .keyboardShortcut("n")
            Button("Quick Capture…") { env.panels.showCapture() }
        }

        CommandMenu("Go") {
            Button("Inbox") { env.go(to: .inbox) }.keyboardShortcut("1")
            Button("Today") { env.go(to: .today) }.keyboardShortcut("2")
            Button("Upcoming") { env.go(to: .upcoming) }.keyboardShortcut("3")
            Button("Focus") { env.go(to: .focus) }.keyboardShortcut("4")
            Divider()
            Button("Search Tasks") { env.focusSearch() }.keyboardShortcut("k")
            Button("Refresh") { Task { await env.store.refresh() } }.keyboardShortcut("r")
        }

        CommandMenu("Task") {
            Button("Complete") { withSelection { id in Task { await env.store.toggleComplete(id) } } }
            Button("Move to Next Day") { withSelection { id in Task { await env.store.pushToNextDay([id]) } } }
            Button("Back to Today") { withSelection { id in Task { await env.store.bringBackToToday(id) } } }
            Button("Make Next Up") { withSelection { id in Task { await env.store.makeNextUp(id) } } }
            Divider()
            Button("Start Focus") { env.startFocusOnSelectionOrNext() }.keyboardShortcut("f")
            Button("Move Unfinished to Tomorrow") { Task { await env.store.moveUnfinishedToTomorrow() } }
            Divider()
            Button("Delete") { withSelection { id in Task { await env.store.deleteTask(id) } } }
        }

        CommandGroup(after: .sidebar) {
            Button("Toggle Inspector") { env.store.inspectorVisible.toggle() }
                .keyboardShortcut("i", modifiers: [.command, .option])
            Picker("Appearance", selection: Binding(get: { env.settings.appearance }, set: { env.settings.appearance = $0 })) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
        }

        CommandGroup(replacing: .help) {
            Button("Nextlet Keyboard Shortcuts") { openWindow(id: "shortcuts") }
                .keyboardShortcut("/", modifiers: .command)
        }
    }

    private func withSelection(_ action: (String) -> Void) {
        if let id = env.store.selectedTaskID { action(id) }
    }
}
