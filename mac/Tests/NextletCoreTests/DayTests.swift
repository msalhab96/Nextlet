import Foundation
import Testing
@testable import NextletCore

private let today = Day("2026-10-01")! // a Thursday

@Suite struct DayTests {
    @Test func parsesOnlyRealDays() {
        #expect(Day("2026-10-01") != nil)
        #expect(Day("2028-02-29") != nil)
        #expect(Day("2026-02-29") == nil)
        #expect(Day("2026-13-01") == nil)
        #expect(Day("2026-1-01") == nil)
        #expect(Day("2026-10-01T11:44") == nil)
    }

    @Test func doesArithmetic() {
        #expect(Day("2026-09-30")!.adding(days: 1) == Day("2026-10-01"))
        #expect(Day("2026-12-31")!.adding(days: 1) == Day("2027-01-01"))
        #expect(today.isoWeekday == 4)
        #expect(today.startOfWeek == Day("2026-09-28"))
        #expect(Day("2026-09-28")!.isoWeekNumber == 40)
        #expect(Day("2027-01-01")!.isoWeekNumber == 53)
        #expect(today.firstOfMonth(offset: -1) == Day("2026-09-01"))
        #expect(today.days(until: Day("2026-10-08")!) == 7)
    }

    @Test func codesAsAString() throws {
        let data = try JSONEncoder().encode(["day": today])
        #expect(String(data: data, encoding: .utf8) == #"{"day":"2026-10-01"}"#)
        let decoded = try JSONDecoder().decode([String: Day].self, from: data)
        #expect(decoded["day"] == today)
    }

    @Test func formatsForPeople() {
        #expect(DayFormat.withDate(today.adding(days: 1), today: today) == "Tomorrow · Fri 2 Oct")
        #expect(DayFormat.withDate(Day("2026-10-05")!, today: today) == "Mon 5 Oct")
        #expect(DayFormat.short(Day("2027-01-04")!, today: today) == "Mon 4 Jan 2027")
        #expect(DayFormat.from(Day("2026-09-29")!, today: today) == "From Tue")
        #expect(DayFormat.from(Day("2026-09-12")!, today: today) == "From 12 Sep")
        #expect(DayFormat.weekRange(Day("2026-09-28")!) == "28 Sep – 4 Oct")
        #expect(DayFormat.long(today) == "Thursday · 1 October")
        let weeks = DayFormat.monthWeeks(today)
        #expect(weeks.first?.first == Day("2026-09-28"))
        #expect(weeks.last?.last == Day("2026-11-01"))
    }
}

@Suite struct FormatTests {
    @Test func formatsEstimatesAndClocks() {
        #expect(Format.estimate(45) == "45 min")
        #expect(Format.estimate(90) == "1 h 30 min")
        #expect(Format.estimate(120) == "2 h")
        #expect(Format.clock(1452) == "24:12")
        #expect(Format.clock(3725) == "1:02:05")
        #expect(Format.clock(-5) == "00:00")
    }

    @Test func labelsRepeats() {
        #expect(RepeatRule.weekly(days: [5, 1, 3]).label == "Mon, Wed, Fri")
        #expect(RepeatRule.weekly(days: [4]).label == "Every Thu")
        #expect(RepeatRule.interval(every: 3).label == "Every 3 days")
        #expect(RepeatChoice.of(.weekly(days: [4]), day: today) == .weekly)
        #expect(RepeatChoice.of(.weekly(days: [1, 4]), day: today) == .custom)
        #expect(RepeatChoice.custom.rule(day: today, current: nil) == .weekly(days: [4]))
    }

    @Test func decodesTasksFromTheAPI() throws {
        let json = """
        {"id":"a","title":"Draft budget","notes":"","projectId":null,"day":"2026-10-01","plannedDay":"2026-09-29",
         "estimateMinutes":45,"priority":1,"repeat":{"type":"weekly","days":[1,3]},"sortOrder":1.5,
         "completedAt":"2026-10-01T09:12:30.123Z","completedFromDay":null,"postponedAt":null,"nextOccurrenceId":null,
         "createdAt":"2026-09-01T08:00:00.000Z","updatedAt":"2026-09-01T08:00:00Z",
         "subtasks":[{"id":"s","title":"Step","done":true,"sortOrder":1}]}
        """
        let task = try JSONCoding.decoder().decode(TaskItem.self, from: Data(json.utf8))
        #expect(task.day == today)
        #expect(task.repeat == .weekly(days: [1, 3]))
        #expect(task.completedAt != nil)
        #expect(task.subtasks.first?.done == true)
    }
}
