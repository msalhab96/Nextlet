import AppKit
import NextletCore
import Observation
import SwiftUI

/// UI state for the floating panels, observed by their SwiftUI views.
@MainActor @Observable
final class PanelState {
    /// Bumped every time quick capture opens, so it starts empty and focused.
    var captureToken = 0
    /// Where quick capture files a task unless you say otherwise, set each time it opens.
    var captureDay: Day?
    var captureProjectID: String?
    var focusTimerVisible = false
    var focusTimerPinned = true
    /// False when another app already owns the chosen quick capture shortcut.
    var hotKeyRegistered = true
}

/// A borderless panel that can take keyboard focus without activating Nextlet,
/// like Spotlight. Used for quick capture and the floating focus timer.
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PanelManager: NSObject, NSWindowDelegate {
    private unowned let env: AppEnvironment
    private var capturePanel: FloatingPanel?
    private var focusPanel: FloatingPanel?

    init(env: AppEnvironment) {
        self.env = env
    }

    // MARK: Quick capture

    var isCaptureVisible: Bool { capturePanel?.isVisible == true }

    func toggleCapture() {
        isCaptureVisible ? hideCapture() : showCapture()
    }

    func showCapture() {
        let panel = capturePanel ?? makeCapturePanel()
        capturePanel = panel
        // With the main window open, a new task goes where you're looking (Today, a project…).
        // From anywhere else it goes to the Inbox.
        let window = env.mainWindow
        let defaults = window?.isVisible == true && window?.isMiniaturized == false
            ? env.store.newTaskDefaults : (day: nil, projectID: nil)
        env.panelState.captureDay = defaults.day
        env.panelState.captureProjectID = defaults.projectID
        env.panelState.captureToken += 1
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: visible.maxY - visible.height * 0.22 - size.height))
        }
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()
    }

    func hideCapture() {
        capturePanel?.orderOut(nil)
    }

    private func makeCapturePanel() -> FloatingPanel {
        let panel = makePanel(level: .floating)
        let view = QuickCaptureView(onClose: { [weak self] in self?.hideCapture() })
            .environment(env.store)
            .environment(env.settings)
            .environment(env.panelState)
        panel.contentViewController = hostingController(view)
        panel.delegate = self
        return panel
    }

    func windowDidResignKey(_ notification: Notification) {
        // Like Spotlight: clicking anywhere else closes quick capture.
        if (notification.object as? NSWindow) === capturePanel { hideCapture() }
    }

    // MARK: Focus timer

    func showFocusTimer() {
        let panel = focusPanel ?? makeFocusPanel()
        focusPanel = panel
        panel.level = env.panelState.focusTimerPinned ? .floating : .normal
        panel.orderFrontRegardless()
        panel.invalidateShadow()
        env.panelState.focusTimerVisible = true
    }

    func hideFocusTimer() {
        focusPanel?.orderOut(nil)
        env.panelState.focusTimerVisible = false
    }

    func setFocusTimerPinned(_ pinned: Bool) {
        env.panelState.focusTimerPinned = pinned
        focusPanel?.level = pinned ? .floating : .normal
    }

    private func makeFocusPanel() -> FloatingPanel {
        let panel = makePanel(level: .floating)
        panel.isMovableByWindowBackground = true
        let view = FocusTimerPanel(onHide: { [weak self] in self?.hideFocusTimer() })
            .environment(env.store)
            .environment(env.focus)
            .environment(env.settings)
            .environment(env.panelState)
        panel.contentViewController = hostingController(view)
        if !panel.setFrameUsingName("NextletFocusTimer"), let visible = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: visible.maxX - panel.frame.width - 24, y: visible.maxY - panel.frame.height - 24))
        }
        panel.setFrameAutosaveName("NextletFocusTimer")
        return panel
    }

    // MARK: Helpers

    private func makePanel(level: NSWindow.Level) -> FloatingPanel {
        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.level = level
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        return panel
    }

    private func hostingController<V: View>(_ view: V) -> NSViewController {
        let controller = NSHostingController(rootView: view)
        controller.sizingOptions = [.preferredContentSize]
        return controller
    }
}
