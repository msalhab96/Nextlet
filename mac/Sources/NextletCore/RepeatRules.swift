import Foundation

extension RepeatRule {
    /// "Daily", "Mon, Wed, Fri", "Every 3 days" …
    public var label: String {
        switch self {
        case .daily: return "Daily"
        case .weekdays: return "Weekdays"
        case .interval(let every): return "Every \(every) days"
        case .monthly: return "Monthly"
        case .weekly(let days):
            let sorted = Array(Set(days)).sorted()
            if sorted.count == 7 { return "Daily" }
            if sorted.count == 1 { return "Every \(DayFormat.weekdayShort[sorted[0] - 1])" }
            return sorted.map { DayFormat.weekdayShort[$0 - 1] }.joined(separator: ", ")
        }
    }
}

/// The choices offered in the Repeat menu.
public enum RepeatChoice: Hashable, Sendable {
    case never
    case daily
    case weekdays
    case weekly
    case every(Int)
    case monthly
    case custom

    public static func of(_ rule: RepeatRule?, day: Day) -> RepeatChoice {
        guard let rule else { return .never }
        switch rule {
        case .daily: return .daily
        case .weekdays: return .weekdays
        case .monthly: return .monthly
        case .interval(let every): return .every(every)
        case .weekly(let days): return days == [day.isoWeekday] ? .weekly : .custom
        }
    }

    public static func options(day: Day, rule: RepeatRule?) -> [(choice: RepeatChoice, label: String)] {
        var options: [(RepeatChoice, String)] = [
            (.never, "Never"),
            (.daily, "Daily"),
            (.weekdays, "Weekdays"),
            (.weekly, "Weekly on \(DayFormat.weekdayLong[day.isoWeekday - 1])"),
            (.every(2), "Every 2 days"),
            (.every(3), "Every 3 days"),
            (.monthly, "Monthly on the \(DayFormat.ordinal(day.day))"),
            (.custom, "Pick weekdays…"),
        ]
        if case .interval(let every)? = rule, every != 2, every != 3 {
            options.insert((.every(every), "Every \(every) days"), at: 6)
        }
        return options
    }

    public func rule(day: Day, current: RepeatRule?) -> RepeatRule? {
        switch self {
        case .never: return nil
        case .daily: return .daily
        case .weekdays: return .weekdays
        case .weekly: return .weekly(days: [day.isoWeekday])
        case .every(let every): return .interval(every: every)
        case .monthly: return .monthly
        case .custom:
            if case .weekly? = current { return current }
            return .weekly(days: [day.isoWeekday])
        }
    }
}
