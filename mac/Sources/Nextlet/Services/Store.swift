import Foundation
import NextletCore
import Observation

enum Route: Hashable {
    case inbox
    case today
    case upcoming
    case focus
    case project(String)
}

enum UpcomingMode: String, CaseIterable, Identifiable {
    case week = "Week"
    case month = "Month"

    var id: String { rawValue }
}

/// All app state, shared by the main window, the menu bar, quick capture and the focus
/// timer. Every change is applied locally first and then confirmed by the API; if the
/// API refuses, the change is rolled back and a toast says what happened.
/// A port of web/src/store/store.ts.
@MainActor @Observable
final class Store {
    enum Phase: Equatable {
        case idle
        case loading
        case ready
        /// The server is password protected and we are not signed in.
        case locked
        case failed(String)
    }

    struct Toast: Identifiable {
        enum Icon {
            case push
            case check
            case info
            case error
        }

        let id: Int
        let message: String
        let icon: Icon
        let actionLabel: String?
        let action: (() -> Void)?
    }

    // MARK: State

    var phase: Phase = .idle
    var tasks: [String: TaskItem] = [:]
    var projects: [Project] = []
    var authRequired = false
    var pending = 0
    var syncError: String?
    var selectedTaskID: String?
    var toasts: [Toast] = []
    var today = Day.today()

    // Main window navigation and view options.
    var route: Route = .today
    var searchText = ""
    var inspectorVisible = true
    var groupByProject = false
    var showDone = true
    /// Show only one project's tasks in Today, Inbox and Upcoming. Nil means all.
    var projectFilter: String?
    var upcomingMode: UpcomingMode = .week
    var upcomingAnchor = Day.today()
    /// Bumped to focus the search field (⌘K).
    var searchRequest = 0

    @ObservationIgnored let settings: AppSettings
    /// Task ids in the order the current list shows them, for ↑/↓ selection.
    @ObservationIgnored var visibleOrder: [String] = []
    @ObservationIgnored private(set) var doneLoadedFrom: Day?
    @ObservationIgnored private var localVersion = 0
    @ObservationIgnored private var tempCounter = 0
    @ObservationIgnored private var toastCounter = 0
    @ObservationIgnored private var pendingCreates: [String: Task<String, Error>] = [:]
    @ObservationIgnored private var resolvedIDs: [String: String] = [:]

    private static let initialDoneWindow = 42

    init(settings: AppSettings) {
        self.settings = settings
    }

    // MARK: Derived

    var taskList: [TaskItem] { Array(tasks.values) }
    var counts: TaskRules.Counts { TaskRules.counts(taskList, today: today) }
    var selectedTask: TaskItem? { selectedTaskID.flatMap { tasks[$0] } }
    var todayOpen: [TaskItem] { TaskRules.openOn(taskList, day: today, today: today) }
    var nextUp: TaskItem? { todayOpen.first }

    func project(_ id: String?) -> Project? {
        guard let id else { return nil }
        return projects.first { $0.id == id }
    }

    func matchesFilter(_ task: TaskItem) -> Bool {
        projectFilter == nil || task.projectId == projectFilter
    }

    // MARK: Plumbing

    private var api: APIClient {
        get throws {
            guard let url = settings.serverURL else {
                throw APIError(kind: .network, status: 0, code: "invalid_address", message: "Set your Nextlet server address in Settings")
            }
            return APIClient(baseURL: url, token: settings.sessionToken)
        }
    }

    private func currentID(_ id: String) -> String { resolvedIDs[id] ?? id }

    private func resolveID(_ id: String) async throws -> String {
        if let known = resolvedIDs[id] { return known }
        if let creation = pendingCreates[id] { return try await creation.value }
        return id
    }

    private func message(_ error: Error) -> String {
        (error as? APIError)?.message ?? error.localizedDescription
    }

    private func isUnauthorized(_ error: Error) -> Bool {
        (error as? APIError)?.isUnauthorized == true
    }

    private func track<T>(_ work: () async throws -> T) async throws -> T {
        pending += 1
        do {
            let result = try await work()
            pending -= 1
            syncError = nil
            return result
        } catch {
            pending -= 1
            syncError = message(error)
            if isUnauthorized(error) { lock() }
            throw error
        }
    }

    /// The session ran out or the password changed: back to signing in.
    private func lock() {
        settings.sessionToken = nil
        authRequired = true
        phase = .locked
        tasks = [:]
        projects = []
        selectedTaskID = nil
        doneLoadedFrom = nil
        toasts = []
    }

    private func failed(_ error: Error, _ fallback: String) {
        if isUnauthorized(error) { return }
        let detail = message(error)
        toast((error as? APIError)?.kind == .network ? detail : "\(fallback): \(detail)", icon: .error)
    }

    private func put(_ list: [TaskItem]) {
        for task in list { tasks[task.id] = task }
    }

    private func patch(_ id: String, _ change: (inout TaskItem) -> Void) {
        guard var task = tasks[id] else { return }
        change(&task)
        tasks[id] = task
    }

    private func remove(_ id: String) {
        tasks[id] = nil
        if selectedTaskID == id { selectedTaskID = nil }
    }

    private func movedPhrase(_ day: Day) -> String {
        let relative = DayFormat.relative(day, today: today)
        if relative == "Today" || relative == "Tomorrow" { return "moved to \(relative.lowercased())" }
        return "moved to \(DayFormat.short(day, today: today))"
    }

    // MARK: Loading

    /// `quietly` keeps whatever is on screen until it works (used for retries).
    func load(quietly: Bool = false) async {
        if !quietly { phase = .loading }
        do {
            let api = try self.api
            let auth = try await api.authStatus()
            authRequired = auth.required
            if auth.required && !auth.authenticated {
                settings.sessionToken = nil
                phase = .locked
                return
            }
            let doneFrom = today.adding(days: -Store.initialDoneWindow)
            async let projectsRequest = api.projects()
            async let openRequest = api.openTasks()
            async let doneRequest = api.doneTasks(from: doneFrom, to: today)
            let (projects, open, done) = try await (projectsRequest, openRequest, doneRequest)
            var map: [String: TaskItem] = [:]
            for task in open + done { map[task.id] = task }
            self.projects = projects
            tasks = map
            doneLoadedFrom = doneFrom
            if let id = selectedTaskID, map[id] == nil { selectedTaskID = nil }
            phase = .ready
        } catch {
            if isUnauthorized(error) { lock() } else { phase = .failed(message(error)) }
        }
    }

    /// Picks up changes made elsewhere. Quietly skips while edits are in flight.
    func refresh() async {
        guard phase == .ready, pending == 0, let api = try? self.api else { return }
        let version = localVersion
        do {
            let doneFrom = doneLoadedFrom ?? today.adding(days: -Store.initialDoneWindow)
            async let projectsRequest = api.projects()
            async let openRequest = api.openTasks()
            async let doneRequest = api.doneTasks(from: doneFrom, to: today)
            let (projects, open, done) = try await (projectsRequest, openRequest, doneRequest)
            guard version == localVersion, pending == 0 else { return }
            var map: [String: TaskItem] = [:]
            for task in open + done { map[task.id] = task }
            // A done task opened from search can be older than the loaded window; keep it.
            if let selected = selectedTask, selected.completedAt != nil, map[selected.id] == nil { map[selected.id] = selected }
            self.projects = projects
            tasks = map
            syncError = nil
            if let id = selectedTaskID, map[id] == nil { selectedTaskID = nil }
        } catch {
            if isUnauthorized(error) { lock() }
        }
    }

    /// Keeps "today" right across midnight and after waking up.
    func updateToday() {
        let now = Day.today()
        guard now != today else { return }
        if upcomingAnchor == today { upcomingAnchor = now }
        today = now
        Task { await refresh() }
    }

    func ensureDoneFrom(_ from: Day) async {
        guard let loaded = doneLoadedFrom, from < loaded, let api = try? self.api else { return }
        doneLoadedFrom = from
        do {
            put(try await api.doneTasks(from: from, to: loaded.adding(days: -1)))
        } catch {
            doneLoadedFrom = loaded
            failed(error, "Couldn’t load older tasks")
        }
    }

    /// Adds tasks fetched outside the normal lists, such as search results.
    func remember(_ list: [TaskItem]) {
        put(list.filter { tasks[$0.id] == nil })
    }

    // MARK: Session

    /// Returns an error message, or nil once signed in and loaded.
    func signIn(password: String) async -> String? {
        do {
            let response = try await (try api).login(password: password)
            settings.sessionToken = response.token
        } catch {
            return message(error)
        }
        await load()
        switch phase {
        case .ready: return nil
        case .failed(let text): return text
        default: return "That didn’t work. Check the password and try again."
        }
    }

    func signOut() async {
        if let api = try? self.api { try? await api.logout() }
        lock()
    }

    /// Connects to the server address in Settings from scratch.
    func reconnect() async {
        tasks = [:]
        projects = []
        selectedTaskID = nil
        doneLoadedFrom = nil
        await load()
    }

    // MARK: Selection and toasts

    func select(_ id: String?) {
        selectedTaskID = id.map(currentID)
        if id != nil { inspectorVisible = true }
    }

    /// Moves the selection up or down the list on screen.
    func selectNeighbour(_ offset: Int) {
        guard !visibleOrder.isEmpty else { return }
        guard let current = selectedTaskID, let index = visibleOrder.firstIndex(of: current) else {
            select(offset > 0 ? visibleOrder.first : visibleOrder.last)
            return
        }
        let next = min(max(index + offset, 0), visibleOrder.count - 1)
        select(visibleOrder[next])
    }

    @discardableResult
    func toast(_ message: String, icon: Toast.Icon = .info, actionLabel: String? = nil, action: (() -> Void)? = nil) -> Int {
        toastCounter += 1
        let id = toastCounter
        toasts = Array(toasts.suffix(2)) + [Toast(id: id, message: message, icon: icon, actionLabel: actionLabel, action: action)]
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            self?.dismissToast(id)
        }
        return id
    }

    func dismissToast(_ id: Int) {
        toasts.removeAll { $0.id == id }
    }

    var latestUndoable: Toast? { toasts.last { $0.action != nil } }

    /// Runs the undo of the most recent toast that offers one (⌘Z).
    @discardableResult
    func undoLatest() -> Bool {
        guard let toast = latestUndoable, let action = toast.action else { return false }
        action()
        dismissToast(toast.id)
        return true
    }

    // MARK: Tasks

    @discardableResult
    func createTask(_ draft: TaskDraft, select shouldSelect: Bool = false) async -> String? {
        tempCounter += 1
        let tempID = "tmp-\(tempCounter)"
        let now = Date()
        let nextSort = (tasks.values.map(\.sortOrder).max() ?? 0) + 1
        let optimistic = TaskItem(
            id: tempID, title: draft.title, notes: draft.notes, projectId: draft.projectId, day: draft.day,
            plannedDay: draft.plannedDay ?? draft.day, estimateMinutes: draft.estimateMinutes, priority: draft.priority,
            repeat: draft.repeat, sortOrder: draft.sortOrder ?? nextSort, createdAt: now, updatedAt: now,
            subtasks: draft.subtasks.enumerated().map {
                Subtask(id: "\(tempID)-\($0.offset)", title: $0.element.title, done: $0.element.done, sortOrder: Double($0.offset + 1))
            }
        )
        localVersion += 1
        tasks[tempID] = optimistic
        if shouldSelect { select(tempID) }

        let creation = Task<String, Error> {
            let api = try self.api
            let task = try await self.track { try await api.createTask(draft) }
            self.resolvedIDs[tempID] = task.id
            self.tasks[tempID] = nil
            self.tasks[task.id] = task
            if self.selectedTaskID == tempID { self.selectedTaskID = task.id }
            return task.id
        }
        pendingCreates[tempID] = creation
        defer { pendingCreates[tempID] = nil }
        do {
            return try await creation.value
        } catch {
            remove(tempID)
            failed(error, "Couldn’t add the task")
            return nil
        }
    }

    func updateTask(_ id: String, _ fields: [TaskField]) async {
        let key = currentID(id)
        guard let before = tasks[key] else { return }
        localVersion += 1
        patch(key) { TaskField.apply(fields, to: &$0) }
        do {
            let api = try self.api
            let realID = try await resolveID(key)
            let task = try await track { try await api.updateTask(id: realID, fields: fields) }
            put([task])
        } catch {
            if tasks[currentID(key)] != nil { put([before]) }
            failed(error, "Couldn’t save that change")
        }
    }

    /// Schedules a task for a chosen day (drag and drop, Pick a day…), with undo.
    func rescheduleTask(_ id: String, to day: Day?) async {
        guard let before = tasks[currentID(id)], before.day != day else { return }
        let phrase = day.map(movedPhrase) ?? "moved to the Inbox"
        toast("\(Format.quoted(before.title)) \(phrase)", icon: .push, actionLabel: "Undo") { [weak self] in
            Task { await self?.updateTask(before.id, [.day(before.day), .plannedDay(before.plannedDay)]) }
        }
        await updateTask(id, [.day(day)])
    }

    func deleteTask(_ id: String) async {
        let key = currentID(id)
        guard let before = tasks[key] else { return }
        localVersion += 1
        remove(key)
        do {
            let api = try self.api
            let realID = try await resolveID(key)
            try await track { try await api.deleteTask(id: realID) }
            toast("Deleted \(Format.quoted(before.title))", icon: .info, actionLabel: "Undo") { [weak self] in
                Task { await self?.restoreDeleted(before) }
            }
        } catch {
            put([before])
            failed(error, "Couldn’t delete the task")
        }
    }

    func restoreDeleted(_ task: TaskItem) async {
        let projectID = task.projectId.flatMap { id in projects.contains { $0.id == id } ? id : nil }
        var draft = TaskDraft(
            title: task.title, projectId: projectID,
            day: task.completedAt != nil ? task.completedFromDay : task.day, priority: task.priority
        )
        draft.notes = task.notes
        draft.plannedDay = task.plannedDay
        draft.estimateMinutes = task.estimateMinutes
        draft.repeat = task.repeat
        draft.sortOrder = task.sortOrder
        draft.subtasks = task.subtasks.map { (title: $0.title, done: $0.done) }
        guard let id = await createTask(draft), task.completedAt != nil, let doneDay = task.day else { return }
        do {
            let api = try self.api
            let response = try await track { try await api.completeTask(id: id, today: doneDay) }
            put([response.task])
        } catch {
            failed(error, "Couldn’t restore the task as done")
        }
    }

    func toggleComplete(_ id: String) async {
        let key = currentID(id)
        guard let before = tasks[key] else { return }
        localVersion += 1
        let today = self.today

        if before.completedAt != nil {
            let follower = before.nextOccurrenceId.flatMap { tasks[$0] }
            patch(key) {
                $0.completedAt = nil
                $0.day = before.completedFromDay
                $0.completedFromDay = nil
                $0.nextOccurrenceId = nil
            }
            if let follower, follower.isOpen { remove(follower.id) }
            do {
                let api = try self.api
                let realID = try await resolveID(key)
                let response = try await track { try await api.uncompleteTask(id: realID) }
                put([response.task])
                if let removed = response.removedTaskId { remove(removed) }
            } catch {
                put([before] + (follower.map { [$0] } ?? []))
                failed(error, "Couldn’t reopen the task")
            }
            return
        }

        patch(key) {
            $0.completedAt = Date()
            $0.completedFromDay = before.day
            $0.day = today
            $0.postponedAt = nil
        }
        toast("Done: \(Format.quoted(before.title))", icon: .check, actionLabel: "Undo") { [weak self] in
            Task { await self?.toggleComplete(key) }
        }
        do {
            let api = try self.api
            let realID = try await resolveID(key)
            let response = try await track { try await api.completeTask(id: realID, today: today) }
            put([response.task] + (response.nextOccurrence.map { [$0] } ?? []))
            if let day = response.nextOccurrence?.day {
                toast("Repeats: next one is \(DayFormat.withDate(day, today: today))")
            }
        } catch {
            put([before])
            failed(error, "Couldn’t complete the task")
        }
    }

    /// Moves tasks to other days while remembering where they were planned.
    /// `postponed` marks a push forward; bringing a task back clears it.
    func moveTasks(_ moves: [(id: String, day: Day)], postponed: Bool, message: String? = nil, undoable: Bool = true) async {
        let befores = moves.compactMap { tasks[currentID($0.id)] }.filter(\.isOpen)
        guard !befores.isEmpty else { return }
        localVersion += 1
        let now = Date()
        for move in moves {
            let key = currentID(move.id)
            guard tasks[key]?.isOpen == true else { continue }
            patch(key) {
                $0.day = move.day
                $0.postponedAt = postponed ? now : nil
            }
        }
        if let message {
            if undoable {
                toast(message, icon: .push, actionLabel: "Undo") { [weak self] in
                    Task { await self?.restorePlacement(befores) }
                }
            } else {
                toast(message, icon: .push)
            }
        }
        do {
            let api = try self.api
            var resolved: [(id: String, day: Day)] = []
            for move in moves { resolved.append((id: try await resolveID(move.id), day: move.day)) }
            let updated = try await track { try await api.moveTasks(resolved, postponed: postponed) }
            put(updated)
        } catch {
            put(befores)
            failed(error, "Couldn’t move that")
        }
    }

    /// Puts tasks back on the days they were on before a move.
    func restorePlacement(_ befores: [TaskItem]) async {
        let pushed = befores.filter { $0.day != nil && $0.postponedAt != nil }
        let placed = befores.filter { $0.day != nil && $0.postponedAt == nil }
        if !pushed.isEmpty { await moveTasks(pushed.map { (id: $0.id, day: $0.day!) }, postponed: true) }
        if !placed.isEmpty { await moveTasks(placed.map { (id: $0.id, day: $0.day!) }, postponed: false) }
        for task in befores where task.day == nil {
            await updateTask(task.id, [.day(nil), .plannedDay(task.plannedDay)])
        }
    }

    /// "Move to tomorrow": each task goes to the day after the one it shows up on.
    func pushToNextDay(_ ids: [String]) async {
        let list = ids.compactMap { tasks[currentID($0)] }.filter(\.isOpen)
        guard let first = list.first else { return }
        let moves = list.map { (id: $0.id, day: (TaskRules.effectiveDay($0, today: today) ?? today).adding(days: 1)) }
        let sameDay = moves.allSatisfy { $0.day == moves[0].day }
        let message = list.count == 1
            ? "\(Format.quoted(first.title)) \(movedPhrase(moves[0].day))"
            : "\(list.count) tasks \(sameDay ? movedPhrase(moves[0].day) : "moved to their next day")"
        await moveTasks(moves, postponed: true, message: message)
    }

    func moveUnfinishedToTomorrow() async {
        await pushToNextDay(todayOpen.map(\.id))
    }

    func bringBackToToday(_ id: String) async {
        guard let task = tasks[currentID(id)] else { return }
        await moveTasks([(id: task.id, day: today)], postponed: false, message: "\(Format.quoted(task.title)) is back on today")
    }

    func reorder(_ ids: [String]) async {
        let keys = ids.map(currentID)
        let local = TaskRules.reorderSlots(taskList, ordered: keys)
        let befores = local.keys.compactMap { tasks[$0] }
        localVersion += 1
        for (id, sortOrder) in local { patch(id) { $0.sortOrder = sortOrder } }
        do {
            let api = try self.api
            var realIDs: [String] = []
            for id in keys { realIDs.append(try await resolveID(id)) }
            let sortOrders = try await track { try await api.reorder(ids: realIDs) }
            for (id, sortOrder) in sortOrders { patch(id) { $0.sortOrder = sortOrder } }
        } catch {
            put(befores)
            failed(error, "Couldn’t reorder")
        }
    }

    /// Moves a task to the top of today's list.
    func makeNextUp(_ id: String) async {
        let key = currentID(id)
        let order = todayOpen.map(\.id)
        guard let task = tasks[key], order.contains(key), order.first != key else { return }
        await reorder([key] + order.filter { $0 != key })
        toast("\(Format.quoted(task.title)) is next up")
    }

    // MARK: Quick add

    /// Creates the task described by quick-add text. Returns the new task's id.
    @discardableResult
    func createFromQuickAdd(_ parsed: QuickAdd.Result, defaultDay: Day?, defaultProjectID: String? = nil, subtasks: [String] = []) async -> String? {
        guard !parsed.title.isEmpty else { return nil }
        var projectID = defaultProjectID
        switch parsed.project {
        case .existing(let project)?:
            projectID = project.id
        case .new(let name)?:
            guard let created = await createProject(name: name) else { return nil }
            projectID = created.id
        case nil:
            break
        }
        let day: Day? = parsed.day.map { $0.day } ?? defaultDay
        var draft = TaskDraft(title: parsed.title, projectId: projectID, day: day, priority: parsed.priority ?? 0)
        draft.subtasks = subtasks.map { (title: $0, done: false) }
        return await createTask(draft)
    }

    /// Where a quick-added task will land: "Personal · Tomorrow", "Inbox".
    func destination(of parsed: QuickAdd.Result, defaultDay: Day?, defaultProjectID: String? = nil) -> String {
        let day: Day? = parsed.day.map { $0.day } ?? defaultDay
        let name = parsed.project?.name ?? project(defaultProjectID)?.name
        guard let day else { return name ?? "Inbox" }
        let place = DayFormat.relative(day, today: today)
        return name.map { "\($0) · \(place)" } ?? place
    }

    /// Where a new task goes unless you say otherwise: the screen you're looking at.
    var newTaskDefaults: (day: Day?, projectID: String?) {
        switch route {
        case .today: return (today, projectFilter)
        case .inbox: return (nil, projectFilter)
        case .upcoming, .focus: return (today, nil)
        case .project(let id): return (nil, id)
        }
    }

    // MARK: Subtasks

    func addSubtask(_ taskID: String, title: String) async {
        let key = currentID(taskID)
        guard let task = tasks[key] else { return }
        tempCounter += 1
        let tempID = "tmp-sub-\(tempCounter)"
        let sortOrder = (task.subtasks.map(\.sortOrder).max() ?? 0) + 1
        localVersion += 1
        patch(key) { $0.subtasks.append(Subtask(id: tempID, title: title, done: false, sortOrder: sortOrder)) }
        let creation = Task<String, Error> {
            let api = try self.api
            let parentID = try await self.resolveID(key)
            let subtask = try await self.track { try await api.addSubtask(taskID: parentID, title: title) }
            self.resolvedIDs[tempID] = subtask.id
            self.patch(self.currentID(key)) { item in
                item.subtasks = item.subtasks.map { $0.id == tempID ? subtask : $0 }
            }
            return subtask.id
        }
        pendingCreates[tempID] = creation
        defer { pendingCreates[tempID] = nil }
        do {
            _ = try await creation.value
        } catch {
            patch(currentID(key)) { item in item.subtasks.removeAll { $0.id == tempID } }
            failed(error, "Couldn’t add the subtask")
        }
    }

    func updateSubtask(_ taskID: String, _ subtaskID: String, title: String? = nil, done: Bool? = nil) async {
        let key = currentID(taskID)
        let subID = currentID(subtaskID)
        guard let before = tasks[key]?.subtasks.first(where: { $0.id == subID }) else { return }
        localVersion += 1
        patch(key) { item in
            item.subtasks = item.subtasks.map { subtask in
                guard subtask.id == subID else { return subtask }
                var changed = subtask
                if let title { changed.title = title }
                if let done { changed.done = done }
                return changed
            }
        }
        do {
            let api = try self.api
            let realID = try await resolveID(subID)
            let saved = try await track { try await api.updateSubtask(id: realID, title: title, done: done) }
            patch(currentID(key)) { item in item.subtasks = item.subtasks.map { $0.id == subID ? saved : $0 } }
        } catch {
            patch(currentID(key)) { item in item.subtasks = item.subtasks.map { $0.id == subID ? before : $0 } }
            failed(error, "Couldn’t update the subtask")
        }
    }

    func deleteSubtask(_ taskID: String, _ subtaskID: String) async {
        let key = currentID(taskID)
        let subID = currentID(subtaskID)
        guard let before = tasks[key]?.subtasks else { return }
        localVersion += 1
        patch(key) { item in item.subtasks.removeAll { $0.id == subID } }
        do {
            let api = try self.api
            let realID = try await resolveID(subID)
            try await track { try await api.deleteSubtask(id: realID) }
        } catch {
            patch(currentID(key)) { $0.subtasks = before }
            failed(error, "Couldn’t delete the subtask")
        }
    }

    // MARK: Projects

    @discardableResult
    func createProject(name: String) async -> Project? {
        do {
            let api = try self.api
            let project = try await track { try await api.createProject(name: name) }
            localVersion += 1
            projects.append(project)
            return project
        } catch {
            failed(error, "Couldn’t create the project")
            return nil
        }
    }

    func updateProject(_ id: String, name: String? = nil, color: String? = nil) async {
        guard let index = projects.firstIndex(where: { $0.id == id }) else { return }
        let before = projects[index]
        localVersion += 1
        if let name { projects[index].name = name }
        if let color { projects[index].color = color }
        do {
            let api = try self.api
            let saved = try await track { try await api.updateProject(id: id, name: name, color: color) }
            if let current = projects.firstIndex(where: { $0.id == id }) { projects[current] = saved }
        } catch {
            if let current = projects.firstIndex(where: { $0.id == id }) { projects[current] = before }
            failed(error, "Couldn’t update the project")
        }
    }

    @discardableResult
    func deleteProject(_ id: String) async -> Bool {
        let beforeProjects = projects
        let affected = tasks.values.filter { $0.projectId == id }
        localVersion += 1
        projects.removeAll { $0.id == id }
        for task in affected { patch(task.id) { $0.projectId = nil } }
        if projectFilter == id { projectFilter = nil }
        if route == .project(id) { route = .today }
        do {
            let api = try self.api
            try await track { try await api.deleteProject(id: id) }
            return true
        } catch {
            projects = beforeProjects
            put(affected)
            failed(error, "Couldn’t delete the project")
            return false
        }
    }

    // MARK: Search

    func search(_ query: String) async -> [TaskItem]? {
        guard let api = try? self.api else { return nil }
        return try? await api.search(query)
    }

    /// Shows a task where it lives and selects it.
    func open(_ task: TaskItem) {
        remember([task])
        searchText = ""
        switch TaskRules.effectiveDay(task, today: today) {
        case nil:
            route = .inbox
        case today?:
            route = .today
        case let day?:
            upcomingMode = .week
            upcomingAnchor = day
            route = .upcoming
        }
        select(task.id)
    }
}
