import Foundation
import Testing
@testable import NextletCore

private let today = Day("2026-10-01")!

private func task(_ id: String, day: Day? = today, planned: Day? = nil, sort: Double = 0, done: Bool = false) -> TaskItem {
    TaskItem(
        id: id, title: id, day: day, plannedDay: planned ?? day, sortOrder: sort,
        completedAt: done ? Date() : nil, createdAt: Date(timeIntervalSince1970: sort)
    )
}

@Suite struct TaskRulesTests {
    @Test func rollsUnfinishedTasksOntoToday() {
        let late = task("late", day: Day("2026-09-29"))
        #expect(TaskRules.effectiveDay(late, today: today) == today)
        #expect(TaskRules.carriedFrom(late, today: today) == Day("2026-09-29"))
    }

    @Test func remembersWhereAPushedTaskWasPlanned() {
        let pushed = task("pushed", day: today.adding(days: 1), planned: today)
        #expect(TaskRules.carriedFrom(pushed, today: today) == today)
        let rescheduled = task("moved", day: Day("2026-10-05"), planned: Day("2026-10-05"))
        #expect(TaskRules.carriedFrom(rescheduled, today: today) == nil)
    }

    @Test func groupsTheDay() {
        let first = task("first", sort: 1)
        let second = task("second", day: Day("2026-09-30"), sort: 5)
        let done = task("done", done: true)
        let inbox = task("inbox", day: nil)
        let later = task("later", day: Day("2026-10-03"))
        let all = [later, done, second, inbox, first]
        #expect(TaskRules.openOn(all, day: today, today: today).map(\.id) == ["first", "second"])
        #expect(TaskRules.doneOn(all, day: today).map(\.id) == ["done"])
        #expect(TaskRules.inbox(all).map(\.id) == ["inbox"])
        let counts = TaskRules.counts(all, today: today)
        #expect(counts.inbox == 1 && counts.today == 2 && counts.upcoming == 1)
    }

    @Test func findsTasksPushedToTomorrowToday() {
        var pushed = task("pushed", day: today.adding(days: 1), planned: today)
        pushed.postponedAt = today.date()
        #expect(TaskRules.pushedToTomorrow([pushed], today: today).map(\.id) == ["pushed"])
        pushed.postponedAt = nil
        #expect(TaskRules.pushedToTomorrow([pushed], today: today).isEmpty)
    }

    @Test func reordersWithinExistingSlots() {
        let a = task("a", sort: 1), b = task("b", sort: 4), c = task("c", sort: 9)
        #expect(TaskRules.moveInOrder(["a", "b", "c"], id: "c", to: 0) == ["c", "a", "b"])
        #expect(TaskRules.reorderSlots([a, b, c], ordered: ["c", "a", "b"]) == ["c": 1, "a": 4, "b": 9])
    }

    @Test func buildsAPIBodies() {
        var item = task("x")
        TaskField.apply([.day(Day("2026-10-05")), .priority(2)], to: &item)
        #expect(item.day == Day("2026-10-05") && item.plannedDay == Day("2026-10-05") && item.priority == 2)
        let body = TaskField.json([.projectId(nil), .repeatRule(.interval(every: 3))])
        #expect(body["projectId"] is NSNull)
        #expect((body["repeat"] as? [String: Any])?["every"] as? Int == 3)
    }
}
