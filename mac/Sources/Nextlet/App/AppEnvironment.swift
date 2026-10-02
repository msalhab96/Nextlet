import AppKit
import Carbon.HIToolbox
import NextletCore
import SwiftUI

/// Owns the shared objects: settings, store, focus timer and panels.
@MainActor
final class AppEnvironment {
    static private(set) var shared = AppEnvironment()

    /// A fresh environment with its own preferences, so the UI test never touches the app's.
    static func isolated(defaults: UserDefaults) -> AppEnvironment {
        shared = AppEnvironment(defaults: defaults)
        return shared
    }

    let settings: AppSettings
    let store: Store
    let focus: FocusController
    let panelState = PanelState()
    private(set) lazy var panels = PanelManager(env: self)

    /// The main window, so keyboard shortcuts only act there.
    weak var mainWindow: NSWindow?
    /// SwiftUI's openWindow, captured from a view, for reopening the main window.
    var openMainWindowAction: (() -> Void)?

    private var keyMonitor: Any?
    private var refreshTimer: Timer?
    private var retryTimer: Timer?
    private var started = false

    private init(defaults: UserDefaults = .standard) {
        settings = AppSettings(defaults: defaults)
        store = Store(settings: settings)
        focus = FocusController(defaults: defaults)
        focus.onTimeUp = { [weak self] in self?.timeUp() }
    }

    func start() {
        guard !started else { return }
        started = true
        settings.applyAppearance()
        FontBook.register()
        registerHotKey()
        installKeyMonitor()

        let center = NotificationCenter.default
        center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                self.store.updateToday()
                if !self.retryIfDisconnected() { Task { await self.store.refresh() } }
            }
        }
        center.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { self.store.updateToday() }
        }
        let timer = Timer(timeInterval: 60, repeats: true) { _ in
            MainActor.assumeIsolated {
                self.store.updateToday()
                Task { await self.store.refresh() }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
        // Until the server answers (after a reboot Docker can take a minute), try again every few seconds.
        let retry = Timer(timeInterval: 5, repeats: true) { _ in
            MainActor.assumeIsolated { _ = self.retryIfDisconnected() }
        }
        RunLoop.main.add(retry, forMode: .common)
        retryTimer = retry
        if !settings.loginItemConfigured {
            settings.loginItemConfigured = true
            LoginItem.set(true)
        }

        Task { await store.load() }
        if focus.session != nil, settings.showFloatingTimer { panels.showFocusTimer() }
    }

    /// Reconnects quietly when the server couldn't be reached. Returns whether it tried.
    @discardableResult
    func retryIfDisconnected() -> Bool {
        guard case .failed = store.phase else { return false }
        Task { await store.load(quietly: true) }
        return true
    }

    func registerHotKey() {
        GlobalHotKey.shared.onPress = { [weak self] in self?.panels.toggleCapture() }
        panelState.hotKeyRegistered = GlobalHotKey.shared.register(settings.hotKey)
    }

    func showMainWindow() {
        NSApp.activate()
        if let window = mainWindow {
            window.makeKeyAndOrderFront(nil)
        } else {
            openMainWindowAction?()
        }
    }

    func go(to route: Route) {
        store.searchText = ""
        store.route = route
        showMainWindow()
    }

    /// ⌘N and the + button: quick capture, filed under the screen you're on.
    func newTask() {
        panels.showCapture()
    }

    func focusSearch() {
        store.searchRequest += 1
        showMainWindow()
    }

    func startFocus(on taskID: String) {
        guard let task = store.tasks[taskID] else { return }
        focus.start(taskID: task.id, minutes: task.estimateMinutes ?? settings.focusMinutes)
        if settings.showFloatingTimer { panels.showFocusTimer() }
    }

    /// F / ⌘F: focus the selected task, or the next one up.
    func startFocusOnSelectionOrNext() {
        if let task = store.selectedTask, task.isOpen {
            startFocus(on: task.id)
        } else if let next = store.nextUp {
            startFocus(on: next.id)
        }
        store.route = .focus
    }

    func completeFocusTask() {
        if let id = focus.session?.taskID { Task { await store.toggleComplete(id) } }
        focus.finish()
    }

    func startNextFocus() {
        let current = focus.session?.taskID
        if let next = store.todayOpen.first(where: { $0.id != current }) { startFocus(on: next.id) }
    }

    private func timeUp() {
        if settings.playSound { NSSound(named: "Glass")?.play() }
        panels.showFocusTimer()
    }

    // MARK: Keyboard

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated { self.handleKey(event) } ? nil : event
        }
    }

    /// Shortcuts for the main window. Never while typing, so text fields keep ⌘→, ⌘Z and friends.
    private func handleKey(_ event: NSEvent) -> Bool {
        guard let window = event.window, window === mainWindow, store.phase == .ready else { return false }
        if window.firstResponder is NSTextView { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let command = flags == .command
        let plain = flags.subtracting([.numericPad, .function]).isEmpty
        let selected = store.selectedTask

        switch Int(event.keyCode) {
        case kVK_RightArrow where command:
            guard let selected, selected.isOpen else { return false }
            Task { await store.pushToNextDay([selected.id]) }
            return true
        case kVK_Return where command, kVK_ANSI_KeypadEnter where command:
            guard let selected else { return false }
            Task { await store.toggleComplete(selected.id) }
            return true
        case kVK_Delete where command:
            guard let selected else { return false }
            Task { await store.deleteTask(selected.id) }
            return true
        case kVK_ANSI_Z where command:
            return store.undoLatest()
        case kVK_UpArrow where plain:
            store.selectNeighbour(-1)
            return true
        case kVK_DownArrow where plain:
            store.selectNeighbour(1)
            return true
        case kVK_Escape where plain:
            guard store.selectedTaskID != nil else { return false }
            store.select(nil)
            return true
        default:
            return false
        }
    }
}
