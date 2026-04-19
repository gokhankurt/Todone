import XCTest
@testable import Todone

// MARK: - Model types

final class TodoItemTests: XCTestCase {
    func testDefaultValues() {
        let item = TodoItem(text: "Buy milk")
        XCTAssertEqual(item.text, "Buy milk")
        XCTAssertFalse(item.done)
        XCTAssertEqual(item.notes, "")
    }

    func testDistinctInstancesHaveDifferentIDs() {
        let a = TodoItem(text: "A")
        let b = TodoItem(text: "A")
        XCTAssertNotEqual(a, b)
    }
}

final class MilestoneTests: XCTestCase {
    func testProgressClampedToRange() {
        XCTAssertEqual(Milestone(title: "M", progress: -10).progress, 0)
        XCTAssertEqual(Milestone(title: "M", progress: 150).progress, 100)
        XCTAssertEqual(Milestone(title: "M", progress: 42).progress, 42)
    }
}

final class YearlyProjectTests: XCTestCase {
    func testEffectiveProgressWithoutMilestones() {
        let p = YearlyProject(title: "P", progress: 60)
        XCTAssertEqual(p.effectiveProgress, 60)
    }

    func testEffectiveProgressAveragesMilestones() {
        let p = YearlyProject(
            title: "P",
            progress: 10,
            milestones: [
                Milestone(title: "A", progress: 40),
                Milestone(title: "B", progress: 80),
            ]
        )
        XCTAssertEqual(p.effectiveProgress, 60)
    }

    func testProgressClampedToRange() {
        XCTAssertEqual(YearlyProject(title: "P", progress: -5).progress, 0)
        XCTAssertEqual(YearlyProject(title: "P", progress: 200).progress, 100)
    }
}

// MARK: - Markdown parsing & rendering

final class ParseRenderTests: XCTestCase {
    func testParseSimpleWeeklyAndBacklog() {
        let md = """
        ## W16

        - [ ] Task A
        - [x] Task B

        ## Backlog

        - [ ] Someday task
        """
        let result = TodoStore.parse(md)

        XCTAssertEqual(result.sections.count, 2)

        let w16 = result.sections[0]
        XCTAssertEqual(w16.id, "w16")
        XCTAssertEqual(w16.items.count, 2)
        XCTAssertEqual(w16.items[0].text, "Task A")
        XCTAssertFalse(w16.items[0].done)
        XCTAssertEqual(w16.items[1].text, "Task B")
        XCTAssertTrue(w16.items[1].done)

        let backlog = result.sections[1]
        XCTAssertEqual(backlog.id, "backlog")
        XCTAssertEqual(backlog.items.count, 1)
    }

    func testParseItemNotes() {
        let md = """
        ## W16

        - [ ] Task with notes
          > First note line
          > Second note line
        - [ ] Task without notes
        """
        let result = TodoStore.parse(md)
        let item = result.sections[0].items[0]
        XCTAssertEqual(item.notes, "First note line\nSecond note line")

        let plain = result.sections[0].items[1]
        XCTAssertTrue(plain.notes.isEmpty)
    }

    func testParseYearlyGoals() {
        let md = """
        ## Yearly goals

        - Learn Swift :: 50
        - Ship App :: 75 | Design=80,Engineering=70
        """
        let result = TodoStore.parse(md)
        XCTAssertEqual(result.yearlyProjects.count, 2)

        let first = result.yearlyProjects[0]
        XCTAssertEqual(first.title, "Learn Swift")
        XCTAssertEqual(first.progress, 50)
        XCTAssertTrue(first.milestones.isEmpty)

        let second = result.yearlyProjects[1]
        XCTAssertEqual(second.title, "Ship App")
        XCTAssertEqual(second.milestones.count, 2)
        XCTAssertEqual(second.milestones[0].title, "Design")
        XCTAssertEqual(second.milestones[0].progress, 80)
        XCTAssertEqual(second.milestones[1].title, "Engineering")
        XCTAssertEqual(second.milestones[1].progress, 70)
    }

    func testRenderRoundTrips() {
        let sections = [
            TodoSection(id: "w16", title: "W16", isExpanded: true, items: [
                TodoItem(text: "A", done: false),
                TodoItem(text: "B", done: true),
            ]),
            TodoSection(id: "backlog", title: "Backlog", isExpanded: true, items: [
                TodoItem(text: "C"),
            ]),
        ]
        let projects = [
            YearlyProject(title: "Goal", progress: 42),
        ]

        let rendered = TodoStore.render(sections, yearlyProjects: projects)
        let parsed = TodoStore.parse(rendered)

        XCTAssertEqual(parsed.sections.count, 2)
        XCTAssertEqual(parsed.sections[0].items.count, 2)
        XCTAssertEqual(parsed.sections[0].items[0].text, "A")
        XCTAssertTrue(parsed.sections[0].items[1].done)
        XCTAssertEqual(parsed.sections[1].items[0].text, "C")
        XCTAssertEqual(parsed.yearlyProjects.count, 1)
        XCTAssertEqual(parsed.yearlyProjects[0].title, "Goal")
        XCTAssertEqual(parsed.yearlyProjects[0].progress, 42)
    }

    func testRenderNotesRoundTrips() {
        var item = TodoItem(text: "Noted", done: false)
        item.notes = "Line 1\nLine 2"
        let sections = [
            TodoSection(id: "w1", title: "W1", isExpanded: true, items: [item]),
        ]
        let rendered = TodoStore.render(sections, yearlyProjects: [])
        let parsed = TodoStore.parse(rendered)
        XCTAssertEqual(parsed.sections[0].items[0].notes, "Line 1\nLine 2")
    }

    func testRenderEmptySectionsOmitted() {
        let sections = [
            TodoSection(id: "w10", title: "W10", isExpanded: true, items: []),
            TodoSection(id: "backlog", title: "Backlog", isExpanded: true, items: [
                TodoItem(text: "X"),
            ]),
        ]
        let rendered = TodoStore.render(sections, yearlyProjects: [])
        XCTAssertFalse(rendered.contains("W10"))
        XCTAssertTrue(rendered.contains("Backlog"))
    }

    func testRenderMilestonesRoundTrip() {
        let projects = [
            YearlyProject(
                title: "Big Project",
                progress: 0,
                milestones: [
                    Milestone(title: "Phase 1", progress: 100),
                    Milestone(title: "Phase 2", progress: 30),
                ]
            ),
        ]
        let rendered = TodoStore.render([], yearlyProjects: projects)
        let parsed = TodoStore.parse(rendered)
        XCTAssertEqual(parsed.yearlyProjects.count, 1)
        XCTAssertEqual(parsed.yearlyProjects[0].milestones.count, 2)
        XCTAssertEqual(parsed.yearlyProjects[0].milestones[0].progress, 100)
    }

    func testParseFallbackCreatesDefaultSections() {
        let result = TodoStore.parse("")
        XCTAssertEqual(result.sections.count, 2)
        XCTAssertTrue(result.sections.contains(where: { $0.id == "backlog" }))
    }
}

// MARK: - Helper methods

final class HelperTests: XCTestCase {
    func testIsWeeklySection() {
        XCTAssertTrue(TodoStore.isWeeklySection(
            TodoSection(id: "w16", title: "W16", isExpanded: true, items: [])))
        XCTAssertFalse(TodoStore.isWeeklySection(
            TodoSection(id: "backlog", title: "Backlog", isExpanded: true, items: [])))
    }

    func testWeekNumber() {
        let section = TodoSection(id: "w42", title: "W42", isExpanded: true, items: [])
        XCTAssertEqual(TodoStore.weekNumber(from: section), 42)

        let backlog = TodoSection(id: "backlog", title: "Backlog", isExpanded: true, items: [])
        XCTAssertNil(TodoStore.weekNumber(from: backlog))
    }
}

// MARK: - Migration

final class MigrationTests: XCTestCase {
    func testMigratesOldBacklogSlug() {
        let md = """
        ## TODOs - Backlog

        - [ ] Legacy item
        """
        let result = TodoStore.parse(md)
        let backlog = result.sections.first(where: { $0.id == "backlog" })
        XCTAssertNotNil(backlog)
        XCTAssertEqual(backlog?.items.count, 1)
        XCTAssertEqual(backlog?.items.first?.text, "Legacy item")
    }

    func testMigratesOldWeeklySlug() {
        let md = """
        ## TODOs - Weekly

        - [ ] Weekly item
        """
        let result = TodoStore.parse(md)
        let cw = TodoStore.currentCalendarWeek
        XCTAssertTrue(result.sections.contains(where: { $0.id == "w\(cw)" }))
    }
}
