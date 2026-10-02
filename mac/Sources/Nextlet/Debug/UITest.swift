import AppKit
import ApplicationServices
import Foundation
import NextletCore
import SwiftUI

/// `Nextlet --ui-test <server>`
///
/// Uses the real main window the way a person does, with mouse clicks and typing, and checks that
/// every change reaches the server. It works on tasks it creates and deletes again. The window sits
/// far off screen, so it never gets in the way.
@MainActor
enum UITest {
    final class TestWindow: NSWindow {
        override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
        override var canBecomeKey: Bool { true }
        override var isKeyWindow: Bool { true }
    }

    private static var passed = 0
    private static var failures: [String] = []

    private static func check(_ label: String, _ condition: Bool, _ detail: String = "") {
        if condition { passed += 1 } else { failures.append(label) }
        print("\(condition ? "PASS" : "FAIL")  \(label)\(detail.isEmpty ? "" : "  (\(detail))")")
    }

    static func run(server: String) {
        setvbuf(stdout, nil, _IOLBF, 0)
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        NSApp.appearance = NSAppearance(named: .aqua)
        FontBook.register()
        let suiteName = "nextlet.ui-test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        // The app's own objects (quick capture uses them), with preferences of their own.
        let env = AppEnvironment.isolated(defaults: defaults)
        let settings = env.settings
        settings.serverAddress = server
        let store = env.store
        let focus = env.focus
        let panelState = env.panelState

        Task { @MainActor in
            await store.load()
            guard store.phase == .ready else {
                print("Could not load from \(server): \(store.phase)")
                exit(1)
            }
            let title = "UI test \(Int(Date().timeIntervalSince1970))"
            guard let id = await store.createTask(TaskDraft(title: title, day: store.today)) else {
                print("Could not create a test task")
                exit(1)
            }
            store.route = .today
            store.select(id)
            store.inspectorVisible = true

            let window = TestWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
                styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                backing: .buffered, defer: false
            )
            let hosting = NSHostingView(rootView: MainWindow()
                .environment(store)
                .environment(focus)
                .environment(settings)
                .environment(panelState))
            hosting.sceneBridgingOptions = [.toolbars, .title]
            window.isReleasedWhenClosed = false
            window.contentView = hosting
            present(window)
            await pause(1.5)
            await wakeAccessibility()

            var created: [String] = []
            await exercise(window, store: store, settings: settings, id: id, title: title, created: &created)

            window.orderOut(nil)
            for leftover in created + [id] where store.tasks[leftover] != nil {
                await store.deleteTask(leftover)
            }
            defaults.removePersistentDomain(forName: suiteName)
            print(failures.isEmpty
                  ? "\nAll \(passed) checks passed."
                  : "\n\(failures.count) of \(passed + failures.count) checks failed:\n" + failures.map { "  • \($0)" }.joined(separator: "\n"))
            exit(failures.isEmpty ? 0 : 1)
        }
        app.run()
    }

    // MARK: What is checked

    private static func exercise(_ window: NSWindow, store: Store, settings: AppSettings, id: String, title: String, created: inout [String]) async {
        let today = store.today
        var task: TaskItem? { store.tasks[id] }

        print("Every dropdown and text field responds to a click (Today, details open)")
        await auditControls(window)

        print("\nEditing a task from its details, with clicks and typing")
        await pickFromDropdown(window, offering: Format.estimate(60), check: "Estimate dropdown sets 1 h") { task?.estimateMinutes == 60 }
        await pickFromDropdown(window, offering: Format.priorityLabels[1], check: "Priority dropdown sets P1 · High") { task?.priority == 1 }
        await pickFromDropdown(window, offering: "Daily", check: "Repeat dropdown sets Daily") { task?.repeat == .daily }

        if let project = store.projects.first {
            let point = pressable(window, "Project")
            check("Project menu can be found", point != nil)
            if let point {
                let picked = await clickAndPick(window, at: point, item: project.name)
                let applied = await waitFor { task?.projectId == project.id }
                check("Project menu moves the task to “\(project.name)”", picked && applied)
            }
        }

        if let field = textField(window, value: title) {
            let focused = await clickToEdit(window, field)
            check("Clicking the title lets you edit it", focused)
            if focused {
                window.firstResponder?.tryToPerform(#selector(NSText.selectAll(_:)), with: nil)
                typeText("Renamed by the UI test", in: window)
                press(.return, in: window)
                check("Typing a new title and pressing Return saves it", await waitFor { task?.title == "Renamed by the UI test" }, task?.title ?? "-")
            }
        } else {
            check("Title field can be found", false)
        }

        if let field = textField(window, placeholder: "Add subtask") {
            let focused = await clickToEdit(window, field)
            check("Clicking “Add subtask” lets you type", focused)
            if focused {
                typeText("First step", in: window)
                press(.return, in: window)
                check("Typing a subtask and pressing Return adds it", await waitFor { task?.subtasks.map(\.title) == ["First step"] })
            }
        } else {
            check("“Add subtask” field can be found", false)
        }
        await pause(0.3)
        if let point = pressable(window, "Check First step") {
            click(window, at: point)
            check("Clicking a subtask’s box checks it off", await waitFor { task?.subtasks.first?.done == true })
        } else {
            check("Subtask check box can be found", false)
        }

        if let notes = textViews(window).last {
            check("Nothing covers the notes box, so clicks reach it", receivesClicks(notes, in: window))
            window.makeFirstResponder(notes)
            typeText("Notes typed by the UI test", in: window)
            check("Typing in the notes box saves the notes", await waitFor(4) { task?.notes == "Notes typed by the UI test" }, task?.notes ?? "-")
        } else {
            check("Notes box can be found", false)
        }
        window.makeFirstResponder(nil)
        await pause(0.3)

        await pressButton(window, "Move to tomorrow", prefix: true, check: "“Move to tomorrow” moves it to tomorrow") { task?.day == today.adding(days: 1) }
        reselect(store, id)
        await pressButton(window, "Back to today", check: "“Back to today” brings it back") { task?.day == today }
        reselect(store, id)

        if let point = pressable(window, "Pick a day…") {
            click(window, at: point)
            let popover = await waitForWindow { NSStringFromClass(type(of: $0)).contains("Popover") }
            check("“Pick a day…” opens the calendar", popover != nil)
            if let popover {
                popover.alphaValue = 0
                let target = today.adding(days: 3)
                if let picker = descendants(popover.contentView?.superview ?? NSView()).compactMap({ $0 as? NSDatePicker }).first {
                    picker.dateValue = target.date()
                    picker.sendAction(picker.action, to: picker.target)
                }
                await pause(0.3)
                if let move = pressable(popover, "Move") {
                    click(popover, at: move)
                    check("Choosing a day and pressing Move reschedules it", await waitFor { task?.day == target }, task?.day.map { "\($0)" } ?? "no day")
                } else {
                    check("The calendar’s Move button can be found", false)
                }
            }
        } else {
            check("“Pick a day…” can be found", false)
        }
        reselect(store, id)
        await pressButton(window, "Back to today", check: "“Back to today” works after picking a day") { task?.day == today }
        reselect(store, id)

        if let point = pressable(window, "More actions") {
            let picked = await clickAndPick(window, at: point, item: "Complete")
            let completed = await waitFor { task?.isOpen == false }
            check("The ••• menu completes the task", picked && completed)
            reselect(store, id)
            await pause(0.3)
            if let point = pressable(window, "More actions") {
                let reopened = await clickAndPick(window, at: point, item: "Mark as Not Done")
                let open = await waitFor { task?.isOpen == true }
                check("…and marks it as not done again", reopened && open)
            }
        } else {
            check("The ••• menu can be found", false)
        }
        reselect(store, id)
        await pause(0.3)

        await pressButton(window, "Hide details", check: "“Hide details” closes the details") { !store.inspectorVisible }
        await pause(0.3)
        check("…and the details column is gone", popUp(window, offering: Format.estimate(60)) == nil)
        if let point = pressable(window, "Inspector") ?? pressable(window, "Show details") {
            click(window, at: point)
            check("The toolbar button opens the details again", await waitFor { store.inspectorVisible && popUp(window, offering: Format.estimate(60)) != nil })
        } else {
            check("The toolbar’s details button can be found", false)
        }

        print("\nWhat the server has for the task")
        let fresh = Store(settings: settings)
        await fresh.load()
        let saved = fresh.tasks[id]
        check("Title", saved?.title == "Renamed by the UI test", saved?.title ?? "-")
        check("Estimate", saved?.estimateMinutes == 60)
        check("Priority", saved?.priority == 1)
        check("Repeat", saved?.repeat == .daily)
        check("Project", saved?.projectId != nil && saved?.projectId == store.projects.first?.id)
        check("Subtask, checked off", saved?.subtasks.map(\.title) == ["First step"] && saved?.subtasks.first?.done == true)
        check("Notes", saved?.notes == "Notes typed by the UI test")
        check("Day and status", saved?.day == today && saved?.isOpen == true)

        print("\nAdding and searching")
        // Toasts float over the bottom of the list; let them go and bring the field into view first.
        for toast in store.toasts { store.dismissToast(toast.id) }
        await pause(0.4)
        if let field = textField(window, placeholderPrefix: "New task") {
            field.scrollToVisible(field.bounds)
            await pause(0.4)
            let focused = await clickToEdit(window, field)
            check("Clicking “New task” lets you type", focused)
            if focused {
                let quick = "UI test quick add \(Int(Date().timeIntervalSince1970))"
                typeText(quick, in: window)
                press(.return, in: window)
                let added = await waitFor { store.tasks.values.contains { $0.title == quick && $0.day == today } }
                check("Typing a task and pressing Return adds it to Today", added)
                created += store.tasks.values.filter { $0.title == quick }.map(\.id)
            }
        } else {
            check("“New task” field can be found", false)
        }
        window.makeFirstResponder(nil)
        await pause(0.3)
        if let field = textField(window, placeholder: "Search") {
            let focused = await clickToEdit(window, field)
            check("Clicking Search lets you type", focused)
            if focused {
                typeText("Renamed by", in: window)
                check("Typing searches", await waitFor { store.searchText == "Renamed by" }, store.searchText)
                press(.escape, in: window)
                check("Esc clears the search", await waitFor { store.searchText.isEmpty })
            }
        } else {
            check("Search field can be found", false)
        }
        window.makeFirstResponder(nil)
        await pause(0.3)

        print("\nEvery screen in the sidebar")
        var destinations: [(String, Route)] = [("Inbox", .inbox), ("Upcoming", .upcoming), ("Focus", .focus)]
        if let project = store.projects.first { destinations.append((project.name, .project(project.id))) }
        destinations.append(("Today", .today))
        for (name, route) in destinations {
            if let point = pressable(window, name, prefix: true) {
                click(window, at: point)
                let arrived = await waitFor { store.route == route }
                check("Sidebar “\(name)” opens it", arrived)
                await pause(0.8)
                if arrived, route != .today { await auditControls(window, indent: "    ") }
            } else {
                check("Sidebar “\(name)” can be found", false)
            }
        }

        print("\nQuick capture")
        var places: [(String, Route)] = [("Today", .today)]
        if let project = store.projects.first { places.append((project.name, .project(project.id))) }
        for (place, route) in places {
            store.route = route
            await pause(0.8)
            guard let plus = pressable(window, "New Task") else {
                check("The + button is there on \(place)", false)
                continue
            }
            click(window, at: plus)
            let panel = await waitForWindow { $0 is FloatingPanel }
            let ready = await waitFor(2) { panel?.isKeyWindow == true && (panel?.firstResponder as? NSTextView)?.delegate is NSTextField }
            check("On \(place), + opens quick capture ready to type", panel != nil && ready)
            guard let panel, ready else {
                AppEnvironment.shared.panels.hideCapture()
                continue
            }
            // No day or project words in the title: quick add would read them as such.
            let title = "UI test capture \(Int(Date().timeIntervalSince1970)) number \(places.firstIndex { $0.0 == place } ?? 0)"
            typeText(title, in: panel)
            let typed = (panel.firstResponder as? NSTextView)?.string ?? "?"
            press(.return, in: panel)
            let added = await waitFor { store.tasks.values.contains { $0.title == title } }
            let task = store.tasks.values.first { $0.title == title }
            if case .project(let id) = route {
                check("…and the task lands in \(place)", added && task?.projectId == id, task.map { "project \($0.projectId ?? "none"), day \($0.day.map { "\($0)" } ?? "none")" } ?? "not added")
            } else {
                check("…and the task lands on Today", added && task?.day == today, task.map { "day \($0.day.map { "\($0)" } ?? "none")" } ?? "not added; the field held “\(typed)”")
            }
            created += store.tasks.values.filter { $0.title == title }.map(\.id)
            AppEnvironment.shared.panels.hideCapture()
            await pause(0.4)
        }
        store.route = .today
        await pause(0.6)

        print("\nTags")
        reselect(store, id)
        await pause(0.6)
        if let field = textField(window, placeholder: "Add a tag") {
            let focused = await clickToEdit(window, field)
            check("Clicking “Add a tag” lets you type", focused)
            if focused {
                typeText("ui-check, Second tag", in: window)
                press(.return, in: window)
                check("Typing tags and pressing Return adds them", await waitFor { task?.tags == ["ui-check", "Second tag"] }, task?.tags.joined(separator: ", ") ?? "-")
            }
        } else {
            check("“Add a tag” field can be found", false)
        }
        await pause(0.5)
        await pressButton(window, "Remove tag Second tag", check: "A tag’s × takes it off") { task?.tags == ["ui-check"] }
        await pause(0.5)
        if let point = pressable(window, "ui-check", prefix: true) {
            click(window, at: point)
            check("The tag is in the sidebar and opens its tasks", await waitFor { store.route == .tag("ui-check") })
        } else {
            check("The tag is in the sidebar", false)
        }
        await pause(0.8)
        if store.route == .tag("ui-check"), let plus = pressable(window, "New Task") {
            click(window, at: plus)
            if let panel = await waitForWindow({ $0 is FloatingPanel }), await waitFor(2, until: { panel.isKeyWindow }) {
                let title = "UI test tagged capture \(Int(Date().timeIntervalSince1970))"
                typeText(title, in: panel)
                press(.return, in: panel)
                let added = await waitFor { store.tasks.values.contains { $0.title == title } }
                let made = store.tasks.values.first { $0.title == title }
                check("Inside a tag, + adds a task with that tag", added && made?.tags == ["ui-check"], made?.tags.joined(separator: ", ") ?? "not added")
                created += store.tasks.values.filter { $0.title == title }.map(\.id)
            } else {
                check("Inside a tag, + opens quick capture", false)
            }
            AppEnvironment.shared.panels.hideCapture()
            await pause(0.4)
        }
        store.route = .today
        await pause(0.6)
        if let plus = pressable(window, "New Task") {
            click(window, at: plus)
            if let panel = await waitForWindow({ $0 is FloatingPanel }), await waitFor(2, until: { panel.isKeyWindow }) {
                let title = "UI test at-tag capture \(Int(Date().timeIntervalSince1970))"
                typeText(title + " @ui-quick", in: panel)
                press(.return, in: panel)
                let added = await waitFor { store.tasks.values.contains { $0.title == title } }
                let made = store.tasks.values.first { $0.title == title }
                check("Typing @tag in quick capture tags the task", added && made?.tags == ["ui-quick"], made?.tags.joined(separator: ", ") ?? "not added")
                created += store.tasks.values.filter { $0.title == title }.map(\.id)
            }
            AppEnvironment.shared.panels.hideCapture()
            await pause(0.4)
        }
        let renamed = await store.renameTag("ui-check", to: "ui-checked")
        check("Renaming a tag renames it on its tasks", renamed && task?.tags == ["ui-checked"])
        let afterTags = Store(settings: settings)
        await afterTags.load()
        check("The server has the tags", afterTags.tasks[id]?.tags == ["ui-checked"], afterTags.tasks[id]?.tags.joined(separator: ", ") ?? "-")
        store.route = .today
        await pause(0.6)

        print("\nDeleting")
        reselect(store, id)
        await pause(0.5)
        // The Delete button is at the end of the details; scroll down to it first, as a person would.
        if let document = textField(window, placeholder: "Add subtask")?.enclosingScrollView?.documentView {
            let end = document.isFlipped ? document.bounds.maxY - 1 : document.bounds.minY
            document.scrollToVisible(NSRect(x: 0, y: end, width: 1, height: 1))
        }
        await pause(0.5)
        await pressButton(window, "Make next up", check: "“Make next up” puts it first") { store.nextUp?.id == id }
        await pause(0.5)
        await pressButton(window, "Delete", check: "The Delete button deletes the task") { store.tasks[id] == nil }
        let after = Store(settings: settings)
        await after.load()
        check("…on the server too", after.phase == .ready && after.tasks[id] == nil)
    }

    private static func reselect(_ store: Store, _ id: String) {
        store.inspectorVisible = true
        if store.selectedTaskID != id { store.select(id) }
    }

    // MARK: Building blocks

    private static func pickFromDropdown(_ window: NSWindow, offering item: String, check label: String, until applied: @escaping () -> Bool) async {
        guard let popUp = popUp(window, offering: item) else {
            check(label, false, "dropdown not found")
            return
        }
        let picked = await clickAndPick(window, at: center(of: popUp), item: item)
        let saved = await waitFor(until: applied)
        await pause(0.2)
        check(label, picked && saved && popUp.titleOfSelectedItem == item,
              picked ? (saved ? "shows “\(popUp.titleOfSelectedItem ?? "")”" : "the choice wasn’t applied") : "the menu didn’t open")
    }

    private static func pressButton(_ window: NSWindow, _ label: String, prefix: Bool = false, check name: String, until done: @escaping () -> Bool) async {
        guard let point = pressable(window, label, prefix: prefix) else {
            check(name, false, "button not found")
            return
        }
        click(window, at: point)
        let worked = await waitFor(until: done)
        let hit = window.contentView?.superview?.hitTest(point)
        check(name, worked, worked ? "" : "clicked at \(NSStringFromPoint(point)) in a \(NSStringFromSize(window.frame.size)) window, which landed on \(hit.map { String(describing: type(of: $0)).prefix(60) } ?? "nothing")")
        if !worked {
            for (label, frame) in buttons(window) where abs(frame.midY - point.y) < 120 {
                print("        nearby: “\(label)” at \(NSStringFromRect(frame))")
            }
        }
        await pause(0.3)
    }

    /// Clicks every dropdown and text field and checks that the menu opens or the field takes focus.
    static func auditControls(_ window: NSWindow, indent: String = "") async {
        let watcher = MenuWatcher()
        defer { watcher.stop() }
        for control in controls(in: window) {
            window.makeFirstResponder(nil)
            await pause(0.25)
            if let popUp = control as? NSPopUpButton {
                watcher.opened = nil
                click(window, at: center(of: popUp))
                let opened = await waitFor(1) { watcher.opened != nil }
                check("\(indent)Clicking the “\(popUp.titleOfSelectedItem ?? popUp.title)” dropdown opens it", opened)
            } else if control is NSTextView {
                // Synthetic clicks can't focus AppKit text views reliably (they consult the real
                // pointer), so check what a real click would land on instead.
                check("\(indent)Nothing covers the \(describe(control)), so clicks reach it", receivesClicks(control, in: window))
            } else {
                let focused = await clickToEdit(window, control)
                check("\(indent)Clicking the \(describe(control)) lets you type", focused)
            }
        }
        window.makeFirstResponder(nil)
        await pause(0.2)
    }

    /// Watches for menus opening and, when asked, picks an item the way a person would.
    @MainActor private final class MenuWatcher {
        var opened: NSMenu?
        var pick: String?
        var picked = false
        private var observer: NSObjectProtocol?

        init() {
            observer = NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: nil) { [weak self] note in
                guard let menu = note.object as? NSMenu else { return }
                MainActor.assumeIsolated { self?.began(menu) }
            }
        }

        func stop() {
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
        }

        private func began(_ menu: NSMenu) {
            opened = menu
            nonisolated(unsafe) let menu = menu
            RunLoop.main.perform(inModes: [.eventTracking, .default, .modalPanel]) { [weak self] in
                MainActor.assumeIsolated {
                    if let pick = self?.pick, let index = menu.items.firstIndex(where: { $0.title == pick && $0.isEnabled }) {
                        menu.performActionForItem(at: index)
                        self?.picked = true
                    }
                    menu.cancelTrackingWithoutAnimation()
                }
            }
        }
    }

    private static func clickAndPick(_ window: NSWindow, at point: NSPoint, item: String) async -> Bool {
        let watcher = MenuWatcher()
        defer { watcher.stop() }
        watcher.pick = item
        click(window, at: point)
        return await waitFor(1.5) { watcher.picked }
    }

    private static func clickToEdit(_ window: NSWindow, _ control: NSView) async -> Bool {
        click(window, at: center(of: control))
        // Text views take focus only once the double-click interval has passed.
        return await waitFor(NSEvent.doubleClickInterval + 0.8) { isEditing(control, in: window) }
    }

    /// Whether a click in the middle of the view would be delivered to it.
    private static func receivesClicks(_ view: NSView, in window: NSWindow) -> Bool {
        guard let hit = window.contentView?.superview?.hitTest(center(of: view)) else { return false }
        return hit === view || hit.isDescendant(of: view)
    }

    private static func isEditing(_ control: NSView, in window: NSWindow) -> Bool {
        window.firstResponder === control || (control is NSTextField && (window.firstResponder as? NSTextView)?.delegate === control)
    }

    // MARK: Finding things

    private static func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }

    /// The part of the view that is on screen. `visibleRect` alone isn’t clipped to the view’s own bounds.
    private static func visibleBounds(_ view: NSView) -> NSRect {
        view.visibleRect.intersection(view.bounds)
    }

    private static func center(of view: NSView) -> NSPoint {
        let visible = visibleBounds(view)
        return view.convert(NSPoint(x: visible.midX, y: visible.midY), to: nil)
    }

    /// Every visible dropdown, text field and text view, including the toolbar.
    private static func controls(in window: NSWindow) -> [NSView] {
        guard let root = window.contentView?.superview else { return [] }
        return descendants(root).filter { view in
            (view is NSPopUpButton || view is NSTextField || view is NSTextView)
                && !view.isHiddenOrHasHiddenAncestor
                && visibleBounds(view).width > 4 && visibleBounds(view).height > 4
                && ((view as? NSTextField)?.isEditable ?? true)
                && (view as? NSTextView)?.isFieldEditor != true
        }
    }

    private static func popUp(_ window: NSWindow, offering item: String) -> NSPopUpButton? {
        controls(in: window).compactMap { $0 as? NSPopUpButton }.first { $0.itemTitles.contains(item) }
    }

    private static func textField(_ window: NSWindow, value: String? = nil, placeholder: String? = nil, placeholderPrefix: String? = nil) -> NSTextField? {
        controls(in: window).compactMap { $0 as? NSTextField }.first { field in
            if let value { return field.stringValue == value }
            if let placeholder { return field.placeholderString == placeholder }
            if let placeholderPrefix { return field.placeholderString?.hasPrefix(placeholderPrefix) == true }
            return false
        }
    }

    private static func textViews(_ window: NSWindow) -> [NSTextView] {
        controls(in: window).compactMap { $0 as? NSTextView }
    }

    private static func describe(_ view: NSView) -> String {
        if let field = view as? NSTextField {
            let text = field.stringValue.isEmpty ? (field.placeholderString ?? "") : field.stringValue
            return "“\(text.count > 40 ? String(text.prefix(40)) + "…" : text)” field"
        }
        if view is NSTextView { return "notes box" }
        return String(describing: type(of: view))
    }

    private static let pressableRoles: Set<String> = ["AXButton", "AXMenuButton", "AXPopUpButton", "AXCheckBox", "AXRadioButton"]

    /// SwiftUI draws most buttons itself, so they are found the way VoiceOver finds them.
    /// (SwiftUI’s accessibility nodes answer through key-value coding, not the Swift protocol.)
    private static func pressable(_ window: NSWindow, _ label: String, prefix: Bool = false) -> NSPoint? {
        guard let root = window.contentView?.superview else { return nil }
        var stack: [Any] = [root]
        var visited = 0
        while let next = stack.popLast(), visited < 50_000 {
            visited += 1
            guard let node = next as? NSObject else { continue }
            func attribute(_ key: String) -> Any? { node.responds(to: NSSelectorFromString(key)) ? node.value(forKey: key) : nil }
            if let role = (attribute("accessibilityRole") as? NSAccessibility.Role)?.rawValue ?? attribute("accessibilityRole") as? String,
               pressableRoles.contains(role) {
                let names = ["accessibilityLabel", "accessibilityTitle", "accessibilityHelp"].compactMap { attribute($0) as? String }
                if names.contains(where: { prefix ? $0.hasPrefix(label) : $0 == label }),
                   let screenFrame = (attribute("accessibilityFrame") as? NSValue)?.rectValue {
                    let frame = window.convertFromScreen(screenFrame)
                    if frame.width > 0, frame.height > 0 { return NSPoint(x: frame.midX, y: frame.midY) }
                }
            }
            stack.append(contentsOf: (attribute("accessibilityChildren") as? [Any]) ?? [])
        }
        return nil
    }

    /// Every pressable element with its label and frame in window coordinates, for diagnostics.
    private static func buttons(_ window: NSWindow) -> [(String, NSRect)] {
        guard let root = window.contentView?.superview else { return [] }
        var result: [(String, NSRect)] = []
        var stack: [Any] = [root]
        while let next = stack.popLast(), result.count < 500 {
            guard let node = next as? NSObject else { continue }
            func attribute(_ key: String) -> Any? { node.responds(to: NSSelectorFromString(key)) ? node.value(forKey: key) : nil }
            if let role = (attribute("accessibilityRole") as? NSAccessibility.Role)?.rawValue, pressableRoles.contains(role),
               let screenFrame = (attribute("accessibilityFrame") as? NSValue)?.rectValue {
                result.append(((attribute("accessibilityLabel") as? String) ?? "?", window.convertFromScreen(screenFrame)))
            }
            stack.append(contentsOf: (attribute("accessibilityChildren") as? [Any]) ?? [])
        }
        return result
    }

    /// SwiftUI builds its accessibility tree only once an assistive client asks, so ask once ourselves.
    private static func wakeAccessibility() async {
        let pid = getpid()
        await Task.detached {
            let app = AXUIElementCreateApplication(pid)
            var windows: CFTypeRef?
            _ = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windows)
        }.value
        await pause(0.3)
    }

    private static func waitForWindow(_ matches: @escaping (NSWindow) -> Bool) async -> NSWindow? {
        var found: NSWindow?
        _ = await waitFor(2) {
            found = NSApp.windows.first { $0.isVisible && matches($0) }
            return found != nil
        }
        return found
    }

    // MARK: Mouse, keyboard and time

    /// Shows the window far off screen (and transparent), where the real pointer can never reach it.
    static func present(_ window: NSWindow) {
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.collectionBehavior = [.transient, .ignoresCycle]
        window.orderFrontRegardless()
        window.setFrameOrigin(NSPoint(x: -40_000, y: -40_000))
    }

    private static var eventNumber = 1000

    /// A mouse click at `point` in window coordinates, through the app’s event queue like a real one.
    static func click(_ window: NSWindow, at point: NSPoint) {
        let time = ProcessInfo.processInfo.systemUptime
        // Every click needs its own event number: AppKit won’t reopen a menu for the click that closed it.
        eventNumber += 2
        guard
            let down = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: time,
                                          windowNumber: window.windowNumber, context: nil, eventNumber: eventNumber, clickCount: 1, pressure: 1),
            let up = NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [], timestamp: time + 0.05,
                                        windowNumber: window.windowNumber, context: nil, eventNumber: eventNumber + 1, clickCount: 1, pressure: 0)
        else { return }
        NSApp.postEvent(down, atStart: false)
        NSApp.postEvent(up, atStart: false)
        while let event = NSApp.nextEvent(matching: [.leftMouseDown, .leftMouseUp, .leftMouseDragged], until: Date(), inMode: .default, dequeue: true) {
            NSApp.sendEvent(event)
        }
    }

    private enum Key {
        case `return`, escape
        var characters: String { self == .return ? "\r" : "\u{1b}" }
        var code: UInt16 { self == .return ? 36 : 53 }
    }

    private static func typeText(_ text: String, in window: NSWindow) {
        for character in text { key(String(character), code: 0, in: window) }
    }

    private static func press(_ key: Key, in window: NSWindow) {
        self.key(key.characters, code: key.code, in: window)
    }

    private static func key(_ characters: String, code: UInt16, in window: NSWindow) {
        let time = ProcessInfo.processInfo.systemUptime
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            if let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: time, windowNumber: window.windowNumber,
                                            context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code) {
                NSApp.postEvent(event, atStart: false)
            }
        }
        // Straight to the window: the app isn’t active, so it has no key window to route keys to.
        while let event = NSApp.nextEvent(matching: [.keyDown, .keyUp], until: Date(), inMode: .default, dequeue: true) {
            window.sendEvent(event)
        }
    }

    private static func pause(_ seconds: Double) async {
        try? await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
    }

    private static func waitFor(_ timeout: Double = 3, until condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return false }
            await pause(0.05)
        }
        return true
    }
}
