import Foundation

/// A calendar day with no time and no timezone, written as `YYYY-MM-DD`.
/// Nextlet tasks belong to days, never to hours.
public struct Day: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    public init?(year: Int, month: Int, day: Int) {
        guard (1900...2999).contains(year), (1...12).contains(month), day >= 1,
              day <= Day.daysIn(year: year, month: month)
        else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    public init?(_ string: String) {
        let parts = string.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else { return nil }
        self.init(year: year, month: month, day: day)
    }

    private init(utcDate: Date) {
        let parts = Day.utc.dateComponents([.year, .month, .day], from: utcDate)
        year = parts.year!
        month = parts.month!
        day = parts.day!
    }

    /// The day `date` falls on in the user's own calendar.
    public static func of(_ date: Date, calendar: Calendar = .current) -> Day {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return Day(year: parts.year!, month: parts.month!, day: parts.day!)!
    }

    public static func today(_ now: Date = Date(), calendar: Calendar = .current) -> Day {
        of(now, calendar: calendar)
    }

    public static func daysIn(year: Int, month: Int) -> Int {
        let components = DateComponents(year: year, month: month)
        let date = utc.date(from: components)!
        return utc.range(of: .day, in: .month, for: date)!.count
    }

    public var string: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public var description: String { string }

    var utcDate: Date {
        Day.utc.date(from: DateComponents(year: year, month: month, day: day))!
    }

    /// Midnight at the start of this day in the user's calendar, for date pickers.
    public func date(in calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    public func adding(days amount: Int) -> Day {
        Day(utcDate: Day.utc.date(byAdding: .day, value: amount, to: utcDate)!)
    }

    /// The first day of the month, `amount` months away.
    public func firstOfMonth(offset amount: Int = 0) -> Day {
        let first = Day.utc.date(from: DateComponents(year: year, month: month, day: 1))!
        return Day(utcDate: Day.utc.date(byAdding: .month, value: amount, to: first)!)
    }

    public var daysInMonth: Int { Day.daysIn(year: year, month: month) }

    /// ISO weekday: Monday is 1, Sunday is 7.
    public var isoWeekday: Int {
        let weekday = Day.utc.component(.weekday, from: utcDate)
        return weekday == 1 ? 7 : weekday - 1
    }

    /// Weeks start on Monday.
    public var startOfWeek: Day { adding(days: 1 - isoWeekday) }

    public func days(until other: Day) -> Int {
        Day.utc.dateComponents([.day], from: utcDate, to: other.utcDate).day!
    }

    public var isoWeekNumber: Int {
        let thursday = adding(days: 4 - isoWeekday)
        let yearStart = Day(year: thursday.year, month: 1, day: 1)!
        return yearStart.days(until: thursday) / 7 + 1
    }

    public static func < (lhs: Day, rhs: Day) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let day = Day(raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected YYYY-MM-DD, got \(raw)")
        }
        self = day
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(string)
    }
}

/// Human-friendly labels for days, matching the web app.
public enum DayFormat {
    public static let weekdayShort = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    public static let weekdayLong = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    public static let monthShort = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    public static let monthLong = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December",
    ]

    /// "Thu 1 Oct", with the year added when it isn't the current one.
    public static func short(_ day: Day, today: Day? = nil) -> String {
        let label = "\(weekdayShort[day.isoWeekday - 1]) \(day.day) \(monthShort[day.month - 1])"
        if let today, today.year != day.year { return "\(label) \(day.year)" }
        return label
    }

    /// "Thursday · 1 October"
    public static func long(_ day: Day) -> String {
        "\(weekdayLong[day.isoWeekday - 1]) · \(day.day) \(monthLong[day.month - 1])"
    }

    /// "Thursday, 1 October"
    public static func full(_ day: Day) -> String {
        "\(weekdayLong[day.isoWeekday - 1]), \(day.day) \(monthLong[day.month - 1])"
    }

    /// "Today", "Tomorrow", "Yesterday", or "Mon 5 Oct".
    public static func relative(_ day: Day, today: Day) -> String {
        switch today.days(until: day) {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case -1: return "Yesterday"
        default: return short(day, today: today)
        }
    }

    /// "Today · Thu 1 Oct", or just "Mon 5 Oct".
    public static func withDate(_ day: Day, today: Day) -> String {
        let relativeLabel = relative(day, today: today)
        let shortLabel = short(day, today: today)
        return relativeLabel == shortLabel ? shortLabel : "\(relativeLabel) · \(shortLabel)"
    }

    /// "From Tue" for nearby days, "From 12 Sep" for older ones.
    public static func from(_ origin: Day, today: Day) -> String {
        if abs(origin.days(until: today)) <= 6 { return "From \(weekdayShort[origin.isoWeekday - 1])" }
        return "From \(origin.day) \(monthShort[origin.month - 1])"
    }

    /// "28 Sep – 4 Oct"
    public static func weekRange(_ weekStart: Day) -> String {
        let end = weekStart.adding(days: 6)
        if weekStart.month == end.month { return "\(weekStart.day) – \(end.day) \(monthShort[end.month - 1])" }
        return "\(weekStart.day) \(monthShort[weekStart.month - 1]) – \(end.day) \(monthShort[end.month - 1])"
    }

    /// "October 2026"
    public static func month(_ day: Day) -> String {
        "\(monthLong[day.month - 1]) \(day.year)"
    }

    /// The Monday-first weeks covering the month that contains `day`.
    public static func monthWeeks(_ day: Day) -> [[Day]] {
        let first = day.firstOfMonth()
        let last = Day(year: first.year, month: first.month, day: first.daysInMonth)!
        var weeks: [[Day]] = []
        var weekStart = first.startOfWeek
        while weekStart <= last {
            weeks.append((0..<7).map { weekStart.adding(days: $0) })
            weekStart = weekStart.adding(days: 7)
        }
        return weeks
    }

    public static func ordinal(_ value: Int) -> String {
        let mod100 = value % 100
        if (11...13).contains(mod100) { return "\(value)th" }
        switch value % 10 {
        case 1: return "\(value)st"
        case 2: return "\(value)nd"
        case 3: return "\(value)rd"
        default: return "\(value)th"
        }
    }
}
