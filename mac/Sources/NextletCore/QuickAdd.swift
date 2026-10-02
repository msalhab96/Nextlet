import Foundation

/// Quick add understands days, #projects, @tags and !priority, e.g. "Call mom tomorrow #Personal @phone !2".
/// Times are deliberately not a thing: tasks belong to a day, never an hour.
/// This is a port of web/src/lib/parse.ts and must stay in step with it.
public enum QuickAdd {
    public enum DaySpec: Equatable, Sendable {
        case day(Day)
        /// "someday": no day, i.e. the Inbox.
        case someday

        public var day: Day? {
            if case .day(let day) = self { return day }
            return nil
        }
    }

    public enum ProjectSpec: Equatable, Sendable {
        case existing(Project)
        case new(String)

        public var name: String {
            switch self {
            case .existing(let project): return project.name
            case .new(let name): return name
            }
        }
    }

    public struct Result: Equatable, Sendable {
        public var title: String
        public var day: DaySpec?
        public var priority: Int?
        public var project: ProjectSpec?
        public var tags: [String]

        public init(title: String, day: DaySpec? = nil, priority: Int? = nil, project: ProjectSpec? = nil, tags: [String] = []) {
            self.title = title
            self.day = day
            self.priority = priority
            self.project = project
            self.tags = tags
        }
    }

    static let weekdays: [String: Int] = [
        "mon": 1, "monday": 1,
        "tue": 2, "tues": 2, "tuesday": 2,
        "wed": 3, "weds": 3, "wednesday": 3,
        "thu": 4, "thur": 4, "thurs": 4, "thursday": 4,
        "fri": 5, "friday": 5,
        "sat": 6, "saturday": 6,
        "sun": 7, "sunday": 7,
    ]

    static let months: [String: Int] = [
        "jan": 1, "january": 1, "feb": 2, "february": 2, "mar": 3, "march": 3, "apr": 4, "april": 4,
        "may": 5, "jun": 6, "june": 6, "jul": 7, "july": 7, "aug": 8, "august": 8,
        "sep": 9, "sept": 9, "september": 9, "oct": 10, "october": 10, "nov": 11, "november": 11,
        "dec": 12, "december": 12,
    ]

    private static func alternation(_ words: [String]) -> String {
        words.sorted { $0.count > $1.count }.joined(separator: "|")
    }

    private static let anyWeekday = alternation(Array(weekdays.keys))
    private static let fullWeekday = alternation(weekdays.keys.filter { $0.count > 4 })
    private static let shortWeekday = alternation(["mon", "tue", "tues", "wed", "weds", "thu", "thur", "fri", "sat", "sun"])
    private static let anyMonth = alternation(Array(months.keys))

    private static func regex(_ pattern: String, caseInsensitive: Bool = true) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : [])
    }

    private static let projectPattern = regex("(^|\\s)#([\\p{L}\\p{N}][\\p{L}\\p{N}_-]*)", caseInsensitive: false)
    private static let priorityPattern = regex("(^|\\s)!([1-3])(?=\\s|$)", caseInsensitive: false)
    /// A whole word starting with @, so "john@acme.com" stays in the title.
    private static let tagPattern = regex("(^|\\s)@([\\p{L}\\p{N}][\\p{L}\\p{N}_-]*)(?=\\s|$)", caseInsensitive: false)

    private struct DayRule {
        let pattern: NSRegularExpression
        /// nil: not a usable match; `.some(nil)` is impossible by construction.
        let resolve: (_ groups: [String?], _ today: Day) -> DaySpec?
    }

    /// The next time `weekday` comes round, never today itself.
    static func upcoming(_ today: Day, weekday: Int) -> Day {
        let ahead = (weekday - today.isoWeekday + 7) % 7
        return today.adding(days: ahead == 0 ? 7 : ahead)
    }

    private static func dateInMonth(_ today: Day, month: Int, date: Int) -> Day? {
        for year in [today.year, today.year + 1] {
            if let candidate = Day(year: year, month: month, day: date), candidate >= today { return candidate }
        }
        return nil
    }

    private static let dayRules: [DayRule] = [
        DayRule(pattern: regex("\\bnext week\\b")) { _, today in .day(today.startOfWeek.adding(days: 7)) },
        DayRule(pattern: regex("\\bnext (\(anyWeekday))\\b")) { groups, today in
            guard let word = groups[1]?.lowercased(), let weekday = weekdays[word] else { return nil }
            return .day(upcoming(today, weekday: weekday).adding(days: 7))
        },
        DayRule(pattern: regex("\\bin (\\d{1,3}) (days?|weeks?)\\b")) { groups, today in
            guard let count = groups[1].flatMap({ Int($0) }), let unit = groups[2]?.lowercased() else { return nil }
            return .day(today.adding(days: count * (unit.hasPrefix("week") ? 7 : 1)))
        },
        DayRule(pattern: regex("\\b(today|tonight)\\b")) { _, today in .day(today) },
        DayRule(pattern: regex("\\b(tomorrow|tmrw|tmr)\\b")) { _, today in .day(today.adding(days: 1)) },
        DayRule(pattern: regex("\\bsomeday\\b")) { _, _ in .someday },
        DayRule(pattern: regex("\\b(?:on )?(\\d{4}-\\d{2}-\\d{2})\\b")) { groups, _ in
            groups[1].flatMap { Day($0) }.map { .day($0) }
        },
        DayRule(pattern: regex("\\b(?:on )?(\\d{1,2})(?:st|nd|rd|th)? (\(anyMonth))\\b")) { groups, today in
            guard let date = groups[1].flatMap({ Int($0) }), let month = groups[2].flatMap({ months[$0.lowercased()] }) else { return nil }
            return dateInMonth(today, month: month, date: date).map { .day($0) }
        },
        DayRule(pattern: regex("\\b(?:on )?(\(anyMonth)) (\\d{1,2})(?:st|nd|rd|th)?\\b")) { groups, today in
            guard let month = groups[1].flatMap({ months[$0.lowercased()] }), let date = groups[2].flatMap({ Int($0) }) else { return nil }
            return dateInMonth(today, month: month, date: date).map { .day($0) }
        },
        // Full weekday names count anywhere. Short ones ("sun", "sat") only after "on" or
        // at the very end, so "Buy sun cream" stays a title.
        DayRule(pattern: regex("\\b(?:on )?(\(fullWeekday))\\b")) { groups, today in
            guard let word = groups[1]?.lowercased(), let weekday = weekdays[word] else { return nil }
            return .day(upcoming(today, weekday: weekday))
        },
        DayRule(pattern: regex("(?:\\bon (\(shortWeekday))\\b|\\b(\(shortWeekday))\\s*$)")) { groups, today in
            guard let word = (groups[1] ?? groups[2])?.lowercased(), let weekday = weekdays[word] else { return nil }
            return .day(upcoming(today, weekday: weekday))
        },
    ]

    public static func normalizeProjectName(_ name: String) -> String {
        name.lowercased()
            .replacingOccurrences(of: "[-_]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    private static func firstMatch(_ pattern: NSRegularExpression, in text: String) -> (range: NSRange, groups: [String?])? {
        let nsText = text as NSString
        guard let match = pattern.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)) else { return nil }
        let groups = (0..<match.numberOfRanges).map { index -> String? in
            let range = match.range(at: index)
            return range.location == NSNotFound ? nil : nsText.substring(with: range)
        }
        return (match.range, groups)
    }

    private static func cut(_ text: String, _ range: NSRange) -> String {
        (text as NSString).replacingCharacters(in: range, with: " ")
    }

    /// `tags` are the ones already in use, so "@Phone" reuses an existing "phone".
    public static func parse(_ input: String, today: Day, projects: [Project], tags known: [String] = []) -> Result {
        var text = input
        var result = Result(title: "")

        // Tags first, so "@today" stays a tag rather than a day.
        var tags: [String] = []
        while let match = firstMatch(tagPattern, in: text), let raw = match.groups[2] {
            tags.append(Tags.existing(raw, in: known))
            text = cut(text, match.range)
        }
        result.tags = Tags.cleaned(tags)

        if let match = firstMatch(projectPattern, in: text), let raw = match.groups[2] {
            let wanted = normalizeProjectName(raw)
            if let existing = projects.first(where: { normalizeProjectName($0.name) == wanted }) {
                result.project = .existing(existing)
            } else {
                result.project = .new(raw.replacingOccurrences(of: "[-_]+", with: " ", options: .regularExpression))
            }
            text = cut(text, match.range)
        }

        if let match = firstMatch(priorityPattern, in: text), let level = match.groups[2].flatMap({ Int($0) }) {
            result.priority = level
            text = cut(text, match.range)
        }

        for rule in dayRules {
            guard let match = firstMatch(rule.pattern, in: text), let spec = rule.resolve(match.groups, today) else { continue }
            result.day = spec
            text = cut(text, match.range)
            break
        }

        result.title = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return result
    }
}
