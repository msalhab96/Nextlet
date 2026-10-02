import AppKit
import Foundation
import NextletCore

/// `Nextlet --self-test <server> [--password <password>]`
///
/// Exercises every store action the app's buttons call, against a running Nextlet
/// API, and prints PASS/FAIL lines. It uses its own throwaway settings and only
/// touches tasks and projects it creates, removing them again at the end.
@MainActor
enum SelfTest {
    static func run(server: String, password: String?) {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let suiteName = "nextlet.self-test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let settings = AppSettings(defaults: defaults)
        settings.serverAddress = server
        let store = Store(settings: settings)
        let focus = FocusController(defaults: defaults)

        Task { @MainActor in
            let failures = await execute(store: store, focus: focus, password: password)
            defaults.removePersistentDomain(forName: suiteName)
            print("\nOpen at login: \(LoginItem.isEnabled ? "on" : (LoginItem.needsApproval ? "waiting for approval in Login Items" : "off"))")
            print(failures == 0 ? "\nAll checks passed." : "\n\(failures) check(s) failed.")
            exit(failures == 0 ? 0 : 1)
        }
        app.run()
    }

    private static func execute(store: Store, focus: FocusController, password: String?) async -> Int {
        var failures = 0
        func check(_ label: String, _ ok: Bool, _ detail: String = "") {
            print("\(ok ? "PASS" : "FAIL")  \(label)\(detail.isEmpty ? "" : "  (\(detail))")")
            if !ok { failures += 1 }
        }
        func settle() async { try? await Task.sleep(for: .milliseconds(500)) }

        await store.load()
        if store.phase == .locked {
            check("the server asks for a password", password != nil)
            guard let password else { return failures }
            let refused = await store.signIn(password: password + "-wrong")
            check("a wrong password is refused", refused != nil, refused ?? "")
            let message = await store.signIn(password: password)
            check("signing in loads the app", message == nil && store.phase == .ready, message ?? "")
        }
        check("loads projects and tasks", store.phase == .ready, "\(store.projects.count) projects, \(store.tasks.count) tasks")
        guard store.phase == .ready else { return failures }

        let today = store.today
        let stamp = Int(Date().timeIntervalSince1970)
        let title = "Self-test task \(stamp)"

        // Quick add, with a brand-new project.
        let parsed = QuickAdd.parse("\(title) tomorrow #selftest-\(stamp) !2", today: today, projects: store.projects)
        let id = await store.createFromQuickAdd(parsed, defaultDay: today)
        let created = id.flatMap { store.tasks[$0] }
        let project = store.project(created?.projectId)
        check("quick add creates the task", created?.title == title)
        check("…for tomorrow", created?.day == today.adding(days: 1))
        check("…in a new project", project?.name == "selftest \(stamp)", project?.name ?? "none")
        check("…with priority 2", created?.priority == 2)
        guard let id else { return failures }

        // Move to the next day, then undo.
        await store.pushToNextDay([id])
        check("move to next day", store.tasks[id]?.day == today.adding(days: 2))
        check("…keeps the planned day", store.tasks[id]?.plannedDay == today.adding(days: 1))
        check("…offers undo", store.latestUndoable?.message.contains("moved to") == true)
        store.undoLatest()
        await settle()
        check("undo puts it back", store.tasks[id]?.day == today.adding(days: 1))

        await store.bringBackToToday(id)
        check("back to today", store.tasks[id]?.day == today && store.todayOpen.contains { $0.id == id })

        await store.makeNextUp(id)
        check("make next up", store.nextUp?.id == id)

        // A second task, to move several at once.
        let otherID = await store.createTask(TaskDraft(title: "Self-test helper \(stamp)", day: today))
        if let otherID {
            await store.pushToNextDay([id, otherID])
            check("move several to tomorrow", store.tasks[id]?.day == today.adding(days: 1) && store.tasks[otherID]?.day == today.adding(days: 1))
            check("…lists them under Moved to tomorrow", TaskRules.pushedToTomorrow(store.taskList, today: today).count >= 2)
            store.undoLatest()
            await settle()
            check("…and undo brings both back", store.tasks[id]?.day == today && store.tasks[otherID]?.day == today)
            await store.deleteTask(otherID)
        }

        // Fields.
        await store.updateTask(id, [.estimateMinutes(30), .notes("Written by the self-test"), .repeatRule(.weekly(days: [1, 3])), .priority(1)])
        let updated = store.tasks[id]
        check(
            "estimate, notes, repeat and priority save",
            updated?.estimateMinutes == 30 && updated?.notes == "Written by the self-test"
                && updated?.repeat == .weekly(days: [1, 3]) && updated?.priority == 1
        )
        await store.updateTask(id, [.title("\(title) renamed")])
        check("rename", store.tasks[id]?.title == "\(title) renamed")

        // Subtasks.
        await store.addSubtask(id, title: "First step")
        let subtaskID = store.tasks[id]?.subtasks.first?.id
        check("add subtask", subtaskID.map { !$0.hasPrefix("tmp") } == true)
        if let subtaskID {
            await store.updateSubtask(id, subtaskID, done: true)
            check("check subtask", store.tasks[id]?.subtasks.first?.done == true)
            await store.updateSubtask(id, subtaskID, title: "Renamed step")
            check("rename subtask", store.tasks[id]?.subtasks.first?.title == "Renamed step")
            await store.deleteSubtask(id, subtaskID)
            check("delete subtask", store.tasks[id]?.subtasks.isEmpty == true)
        }

        // Pick a day, Inbox, back again.
        let picked = today.adding(days: 5)
        await store.rescheduleTask(id, to: picked)
        check("pick a day", store.tasks[id]?.day == picked && store.tasks[id]?.plannedDay == picked)
        await store.rescheduleTask(id, to: nil)
        check("remove day sends it to the Inbox", store.tasks[id]?.day == nil && TaskRules.inbox(store.taskList).contains { $0.id == id })
        await store.rescheduleTask(id, to: today)

        // Complete a repeating task.
        await store.toggleComplete(id)
        let done = store.tasks[id]
        check("complete", done?.completedAt != nil && done?.day == today)
        let nextID = done?.nextOccurrenceId
        check("…schedules the next occurrence", nextID.flatMap { store.tasks[$0] }?.isOpen == true)
        await store.toggleComplete(id)
        check("reopen", store.tasks[id]?.isOpen == true)
        check("…removes that occurrence", nextID.map { store.tasks[$0] == nil } ?? false)
        await store.updateTask(id, [.repeatRule(nil)])

        // Focus timer.
        focus.start(taskID: id, minutes: 25)
        check("focus starts", focus.isRunning && focus.remaining > 24 * 60)
        focus.pause()
        check("focus pauses", !focus.isRunning && (focus.session?.remainingSeconds ?? 0) > 0)
        focus.resume()
        check("focus resumes", focus.isRunning)
        focus.addMinutes(5)
        check("+5 min", focus.remaining > 29 * 60)
        focus.finish()
        check("finish", focus.session?.finished == true)
        focus.startBreak(minutes: 5)
        check("5-min break", focus.session?.kind == .rest && focus.isRunning)
        focus.end()
        check("end session", focus.session == nil)

        // Search.
        let found = await store.search("\(title) renamed")
        check("search", found?.contains { $0.id == id } == true)

        // Projects.
        if let project {
            await store.updateProject(project.id, name: "selftest \(stamp) renamed", color: "#7C3AED")
            let saved = store.project(project.id)
            check("rename and recolour a project", saved?.name == "selftest \(stamp) renamed" && saved?.color.uppercased() == "#7C3AED")
            let deleted = await store.deleteProject(project.id)
            check("delete a project, keeping its tasks", deleted && store.tasks[id]?.projectId == nil)
        }

        // Delete with undo, then clean up for good.
        await store.deleteTask(id)
        check("delete", store.tasks[id] == nil)
        store.undoLatest()
        try? await Task.sleep(for: .seconds(1))
        let restored = store.taskList.first { $0.title == "\(title) renamed" }
        check("undo delete", restored != nil)
        if let restored { await store.deleteTask(restored.id) }

        await store.refresh()
        check("refresh", store.phase == .ready && !store.taskList.contains { $0.title.contains("\(stamp)") })

        // The global quick capture shortcut registers with the system.
        let registered = GlobalHotKey.shared.register(.optionSpace) || GlobalHotKey.shared.register(.controlOptionSpace)
        check("quick capture shortcut registers", registered, GlobalHotKey.shared.registeredPreset?.label ?? "taken by another app")
        GlobalHotKey.shared.unregister()
        return failures
    }
}
