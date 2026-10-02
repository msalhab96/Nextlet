import Testing
@testable import NextletCore

private let today = Day("2026-10-01")! // Thursday
private let personal = Project(id: "p1", name: "Personal", color: "#3B3BD6")
private let side = Project(id: "p2", name: "Side project", color: "#0F766E")

private func parse(_ text: String) -> QuickAdd.Result {
    QuickAdd.parse(text, today: today, projects: [personal, side])
}

// The same cases as web/test/parse.test.ts, so both apps understand you the same way.
@Suite struct QuickAddTests {
    @Test func pullsOutDayProjectAndPriority() {
        let result = parse("Call mom tomorrow #Personal !2")
        #expect(result.title == "Call mom")
        #expect(result.day == .day(Day("2026-10-02")!))
        #expect(result.priority == 2)
        #expect(result.project == .existing(personal))
    }

    @Test func leavesPlainTitlesAlone() {
        #expect(parse("Buy sun cream and sat nav cable") == QuickAdd.Result(title: "Buy sun cream and sat nav cable"))
        #expect(parse("Read 20 pages") == QuickAdd.Result(title: "Read 20 pages"))
    }

    @Test func understandsWeekdays() {
        #expect(parse("Gym friday").day == .day(Day("2026-10-02")!))
        #expect(parse("Gym fri").day == .day(Day("2026-10-02")!))
        #expect(parse("Gym on sat with Sam").day == .day(Day("2026-10-03")!))
        #expect(parse("Team review thursday").day == .day(Day("2026-10-08")!))
        #expect(parse("Plan next mon").day == .day(Day("2026-10-12")!))
    }

    @Test func understandsRelativeAndExplicitDates() {
        #expect(parse("Weekly reset next week").day == .day(Day("2026-10-05")!))
        #expect(parse("Renew passport in 3 days").day == .day(Day("2026-10-04")!))
        #expect(parse("Renew passport in 2 weeks").day == .day(Day("2026-10-15")!))
        #expect(parse("Pay rent on 5 oct").day == .day(Day("2026-10-05")!))
        #expect(parse("Pay rent oct 5th").day == .day(Day("2026-10-05")!))
        #expect(parse("Dentist 2026-11-20").day == .day(Day("2026-11-20")!))
        #expect(parse("New year plans jan 2").day == .day(Day("2027-01-02")!))
    }

    @Test func sendsSomedayToTheInbox() {
        let result = parse("Learn the cello someday")
        #expect(result.title == "Learn the cello")
        #expect(result.day == .someday)
    }

    @Test func ignoresImpossibleDates() {
        #expect(parse("Party 2026-02-30").day == nil)
        #expect(parse("Party 31 feb").day == nil)
    }

    @Test func matchesProjectsLoosely() {
        #expect(parse("Ship it #side-project").project == .existing(side))
        #expect(parse("Plant tulips #Garden").project == .new("Garden"))
    }

    @Test func leavesTimesInTheTitle() {
        let result = parse("Call mom tomorrow 6pm")
        #expect(result.day == .day(Day("2026-10-02")!))
        #expect(result.title == "Call mom 6pm")
    }
}
