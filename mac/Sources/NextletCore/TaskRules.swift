import Foundation

/// The rules that decide where tasks show up. Shared with the web app.
public enum TaskRules {
    /// The day a task shows up on. Unfinished tasks from earlier days roll forward to today.
    public static func effectiveDay(_ task: TaskItem, today: Day) -> Day? {
        guard let day = task.day else { return nil }
        return task.isOpen && day < today ? today : day
    }

    /// The earlier day an open task was planned for, when it was carried over or pushed.
    public static func carriedFrom(_ task: TaskItem, today: Day) -> Day? {
        guard task.isOpen, let day = task.day, let shown = effectiveDay(task, today: today) else { return nil }
        let origin = (task.plannedDay.map { $0 < day } ?? false) ? task.plannedDay! : day
        return origin < shown ? origin : nil
    }

    public static func bySortOrder(_ a: TaskItem, _ b: TaskItem) -> Bool {
        if a.sortOrder != b.sortOrder { return a.sortOrder < b.sortOrder }
        return a.createdAt < b.createdAt
    }

    /// Open tasks that show up on `day`, in the user's order.
    public static func openOn(_ tasks: [TaskItem], day: Day, today: Day) -> [TaskItem] {
        tasks.filter { $0.isOpen && effectiveDay($0, today: today) == day }.sorted(by: bySortOrder)
    }

    /// Tasks finished on `day`, oldest first.
    public static func doneOn(_ tasks: [TaskItem], day: Day) -> [TaskItem] {
        tasks.filter { !$0.isOpen && $0.day == day }.sorted { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }
    }

    public static func inbox(_ tasks: [TaskItem]) -> [TaskItem] {
        tasks.filter { $0.isOpen && $0.day == nil }.sorted(by: bySortOrder)
    }

    /// Tasks pushed from today to tomorrow, so Today can offer to bring them back.
    public static func pushedToTomorrow(_ tasks: [TaskItem], today: Day, calendar: Calendar = .current) -> [TaskItem] {
        let tomorrow = today.adding(days: 1)
        return tasks.filter { task in
            guard task.isOpen, task.day == tomorrow, let postponedAt = task.postponedAt else { return false }
            return Day.of(postponedAt, calendar: calendar) == today
        }.sorted(by: bySortOrder)
    }

    public struct Counts: Equatable, Sendable {
        public var inbox = 0
        public var today = 0
        public var upcoming = 0
        public var byProject: [String: Int] = [:]
    }

    public static func counts(_ tasks: [TaskItem], today: Day) -> Counts {
        var counts = Counts()
        for task in tasks where task.isOpen {
            switch effectiveDay(task, today: today) {
            case nil: counts.inbox += 1
            case today?: counts.today += 1
            default: counts.upcoming += 1
            }
            if let projectId = task.projectId { counts.byProject[projectId, default: 0] += 1 }
        }
        return counts
    }

    /// The order after moving `id` to position `index`.
    public static func moveInOrder(_ ids: [String], id: String, to index: Int) -> [String] {
        var without = ids.filter { $0 != id }
        without.insert(id, at: max(0, min(index, without.count)))
        return without
    }

    /// Gives `ordered` the sort positions those tasks already hold, like the API does.
    public static func reorderSlots(_ tasks: [TaskItem], ordered: [String]) -> [String: Double] {
        let byID = Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let known = ordered.compactMap { byID[$0] }
        var slots = known.map(\.sortOrder).sorted()
        for index in slots.indices.dropFirst() where slots[index] <= slots[index - 1] {
            slots[index] = slots[index - 1] + 1e-6
        }
        return Dictionary(uniqueKeysWithValues: zip(known.map(\.id), slots))
    }
}

public enum Format {
    public static let priorityLabels = ["No priority", "P1 · High", "P2 · Medium", "P3 · Low"]
    public static let estimateChoices = [5, 10, 15, 20, 25, 30, 45, 60, 90, 120, 180]

    public static func estimate(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }

    public static func clock(_ totalSeconds: Int) -> String {
        let seconds = max(0, totalSeconds)
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let rest = seconds % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, rest) }
        return String(format: "%02d:%02d", minutes, rest)
    }

    public static func plural(_ count: Int, _ one: String, _ many: String? = nil) -> String {
        "\(count) \(count == 1 ? one : (many ?? one + "s"))"
    }

    /// Shortens long titles inside messages.
    public static func quoted(_ title: String) -> String {
        "“\(title.count > 48 ? String(title.prefix(47)) + "…" : title)”"
    }
}
