import Foundation
import Testing
@testable import NextletCore

private let today = Day("2026-10-01")! // Thursday

@Suite struct TagsTests {
    @Test func cleansTags() {
        #expect(Tags.clean("@phone") == "phone")
        #expect(Tags.clean("  Deep   work ") == "Deep work")
        #expect(Tags.cleaned(["Phone", "@phone", " ", "errands", "PHONE"]) == ["Phone", "errands"])
    }

    @Test func quickAddPicksUpTags() {
        let result = QuickAdd.parse("Call the bank tomorrow @phone #Personal @errands !1", today: today, projects: [])
        #expect(result.title == "Call the bank")
        #expect(result.tags == ["phone", "errands"])
        #expect(result.day == .day(Day("2026-10-02")!))
        #expect(result.priority == 1)
    }

    @Test func quickAddReusesTheSpellingInUse() {
        let result = QuickAdd.parse("Ring the dentist @PHONE", today: today, projects: [], tags: ["Phone"])
        #expect(result.tags == ["Phone"])
    }

    @Test func emailAddressesStayInTheTitle() {
        let result = QuickAdd.parse("Email john@acme.com about @acme.com", today: today, projects: [])
        #expect(result.title == "Email john@acme.com about @acme.com")
        #expect(result.tags.isEmpty)
    }

    @Test func aTagCanLookLikeADay() {
        let result = QuickAdd.parse("Plan the week @today", today: today, projects: [])
        #expect(result.tags == ["today"])
        #expect(result.day == nil)
    }

    @Test func tasksWithoutTagsStillDecode() throws {
        let json = """
        {"id":"t1","title":"Old task","notes":"","projectId":null,"day":null,"plannedDay":null,"estimateMinutes":null,
         "priority":0,"repeat":null,"sortOrder":1,"completedAt":null,"completedFromDay":null,"postponedAt":null,
         "nextOccurrenceId":null,"createdAt":"2026-10-01T09:00:00.000Z","updatedAt":"2026-10-01T09:00:00.000Z","subtasks":[]}
        """
        let task = try JSONCoding.decoder().decode(TaskItem.self, from: Data(json.utf8))
        #expect(task.tags.isEmpty)
        let tagged = try JSONCoding.decoder().decode(TaskItem.self, from: Data(json.replacingOccurrences(of: "\"subtasks\":[]", with: "\"subtasks\":[],\"tags\":[\"phone\"]").utf8))
        #expect(tagged.tags == ["phone"])
    }
}
