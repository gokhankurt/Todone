import Foundation
import Observation
#if canImport(AppKit)
import AppKit
#endif

struct TodoItem: Identifiable, Equatable {
    let id: UUID
    var text: String
    var done: Bool
    var notes: String

    init(text: String, done: Bool = false, notes: String = "") {
        self.id = UUID()
        self.text = text
        self.done = done
        self.notes = notes
    }
}

struct Milestone: Identifiable, Equatable {
    let id: UUID
    var title: String
    var progress: Int

    init(id: UUID = UUID(), title: String, progress: Int = 0) {
        self.id = id
        self.title = title
        self.progress = min(100, max(0, progress))
    }
}

struct YearlyProject: Identifiable, Equatable {
    let id: UUID
    var title: String
    /// Manual progress (0…100) used when no milestones are present.
    var progress: Int
    var milestones: [Milestone]

    /// Average milestone progress, or manual progress when no milestones exist.
    var effectiveProgress: Int {
        guard !milestones.isEmpty else { return progress }
        return milestones.map(\.progress).reduce(0, +) / milestones.count
    }

    init(id: UUID = UUID(), title: String, progress: Int = 0, milestones: [Milestone] = []) {
        self.id = id
        self.title = title
        self.progress = min(100, max(0, progress))
        self.milestones = milestones
    }
}

struct TodoSection: Identifiable, Equatable {
    let id: String
    var title: String
    var isExpanded: Bool
    var items: [TodoItem]
}

@Observable
class TodoStore {
    var sections: [TodoSection]
    var yearlyProjects: [YearlyProject]
    let fileURL: URL

    @ObservationIgnored private var pendingSave: DispatchWorkItem?
    @ObservationIgnored private let saveQueue = DispatchQueue(label: "todone.save", qos: .utility)
    @ObservationIgnored private var terminationObserver: TodoStoreTerminationObserver?
    private static let saveDebounce: TimeInterval = 0.25

    init() {
        let docs = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents")
        let dir = docs.appendingPathComponent("TodoApp")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("todos.md")

        if FileManager.default.fileExists(atPath: fileURL.path),
           let content = try? String(contentsOf: fileURL, encoding: .utf8),
           !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let parsed = Self.parse(content)
            self.sections = parsed.sections
            self.yearlyProjects = parsed.yearlyProjects
        } else {
            let cw = Self.currentCalendarWeek
            self.sections = [
                TodoSection(id: "w\(cw)", title: "W\(cw)", isExpanded: true, items: []),
                TodoSection(id: "backlog", title: "Backlog", isExpanded: true, items: []),
            ]
            self.yearlyProjects = []
            save()
        }

        registerTerminationFlush()
    }

    deinit {
        flushPendingSave()
    }

    /// Debounced, background save. Rapid successive calls coalesce into one disk write.
    func save() {
        pendingSave?.cancel()

        let snapshotSections = sections
        let snapshotProjects = yearlyProjects
        let url = fileURL

        let work = DispatchWorkItem {
            let content = Self.render(snapshotSections, yearlyProjects: snapshotProjects)
            try? content.write(to: url, atomically: true, encoding: .utf8)
        }
        pendingSave = work
        saveQueue.asyncAfter(deadline: .now() + Self.saveDebounce, execute: work)
    }

    /// Cancel any pending debounced save and write the current state synchronously.
    func flushPendingSave() {
        pendingSave?.cancel()
        pendingSave = nil
        let content = Self.render(sections, yearlyProjects: yearlyProjects)
        try? content.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private func registerTerminationFlush() {
        #if canImport(AppKit)
        terminationObserver = TodoStoreTerminationObserver(store: self)
        #endif
    }

    // MARK: - Week management

    static var currentCalendarWeek: Int {
        Calendar(identifier: .iso8601).component(.weekOfYear, from: Date())
    }

    func ensureWeekSection(_ week: Int) {
        let id = "w\(week)"
        guard !sections.contains(where: { $0.id == id }) else { return }
        let section = TodoSection(id: id, title: "W\(week)", isExpanded: true, items: [])
        if let backlogIdx = sections.firstIndex(where: { $0.id == "backlog" }) {
            sections.insert(section, at: backlogIdx)
        } else {
            sections.append(section)
        }
    }

    static func isWeeklySection(_ section: TodoSection) -> Bool {
        section.id.hasPrefix("w") && Int(section.id.dropFirst()) != nil
    }

    static func weekNumber(from section: TodoSection) -> Int? {
        guard isWeeklySection(section) else { return nil }
        return Int(section.id.dropFirst())
    }

    func weeksWithContent() -> Set<Int> {
        Set(sections.compactMap { section -> Int? in
            guard Self.isWeeklySection(section), !section.items.isEmpty else { return nil }
            return Self.weekNumber(from: section)
        })
    }

    // MARK: - Mutations

    func toggleItem(sectionID: String, itemID: UUID) {
        guard let si = sections.firstIndex(where: { $0.id == sectionID }),
              let ii = sections[si].items.firstIndex(where: { $0.id == itemID }) else { return }
        sections[si].items[ii].done.toggle()
        save()
    }

    func updateItemText(sectionID: String, itemID: UUID, text: String) {
        guard let si = sections.firstIndex(where: { $0.id == sectionID }),
              let ii = sections[si].items.firstIndex(where: { $0.id == itemID }) else { return }
        sections[si].items[ii].text = text
        save()
    }

    func updateItemNotes(sectionID: String, itemID: UUID, notes: String) {
        guard let si = sections.firstIndex(where: { $0.id == sectionID }),
              let ii = sections[si].items.firstIndex(where: { $0.id == itemID }) else { return }
        sections[si].items[ii].notes = notes
        save()
    }

    func item(sectionID: String, itemID: UUID) -> TodoItem? {
        sections.first(where: { $0.id == sectionID })?
            .items.first(where: { $0.id == itemID })
    }

    func addItem(sectionID: String, text: String) {
        guard let si = sections.firstIndex(where: { $0.id == sectionID }) else { return }
        sections[si].items.append(TodoItem(text: text))
        save()
    }

    func deleteItem(sectionID: String, itemID: UUID) {
        guard let si = sections.firstIndex(where: { $0.id == sectionID }) else { return }
        sections[si].items.removeAll { $0.id == itemID }
        save()
    }

    func moveItem(itemID: UUID, fromSection: String, toSection: String) {
        guard let fromIdx = sections.firstIndex(where: { $0.id == fromSection }),
              let toIdx = sections.firstIndex(where: { $0.id == toSection }),
              let itemIdx = sections[fromIdx].items.firstIndex(where: { $0.id == itemID }) else { return }
        var item = sections[fromIdx].items.remove(at: itemIdx)
        item.done = false
        sections[toIdx].items.append(item)
        save()
    }

    func toggleSection(_ sectionID: String) {
        guard let si = sections.firstIndex(where: { $0.id == sectionID }) else { return }
        sections[si].isExpanded.toggle()
    }

    func reorderPendingItems(sectionID: String, fromOffsets: IndexSet, toOffset: Int) {
        guard let si = sections.firstIndex(where: { $0.id == sectionID }) else { return }
        var pending = sections[si].items.filter { !$0.done }
        let done = sections[si].items.filter { $0.done }
        pending.move(fromOffsets: fromOffsets, toOffset: toOffset)
        sections[si].items = pending + done
        save()
    }

    // MARK: - Yearly goals

    func addYearlyProject(title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        yearlyProjects.append(YearlyProject(title: trimmed, progress: 0))
        save()
    }

    func updateYearlyProjectTitle(id: UUID, title: String) {
        guard let i = yearlyProjects.firstIndex(where: { $0.id == id }) else { return }
        yearlyProjects[i].title = title
        save()
    }

    func setYearlyProjectProgress(id: UUID, progress: Int) {
        guard let i = yearlyProjects.firstIndex(where: { $0.id == id }) else { return }
        yearlyProjects[i].progress = min(100, max(0, progress))
        save()
    }

    func deleteYearlyProject(id: UUID) {
        yearlyProjects.removeAll { $0.id == id }
        save()
    }

    // MARK: - Milestone management

    func addMilestone(projectID: UUID, title: String) {
        guard let i = yearlyProjects.firstIndex(where: { $0.id == projectID }) else { return }
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        yearlyProjects[i].milestones.append(Milestone(title: t))
        save()
    }

    func updateMilestoneTitle(projectID: UUID, milestoneID: UUID, title: String) {
        guard let pi = yearlyProjects.firstIndex(where: { $0.id == projectID }),
              let mi = yearlyProjects[pi].milestones.firstIndex(where: { $0.id == milestoneID })
        else { return }
        yearlyProjects[pi].milestones[mi].title = title
        save()
    }

    func setMilestoneProgress(projectID: UUID, milestoneID: UUID, progress: Int) {
        guard let pi = yearlyProjects.firstIndex(where: { $0.id == projectID }),
              let mi = yearlyProjects[pi].milestones.firstIndex(where: { $0.id == milestoneID })
        else { return }
        yearlyProjects[pi].milestones[mi].progress = min(100, max(0, progress))
        save()
    }

    func deleteMilestone(projectID: UUID, milestoneID: UUID) {
        guard let pi = yearlyProjects.firstIndex(where: { $0.id == projectID }) else { return }
        yearlyProjects[pi].milestones.removeAll { $0.id == milestoneID }
        save()
    }

    // MARK: - Markdown persistence

    private static let yearlyGoalsTitle = "Yearly goals"

    static func parse(_ content: String) -> (sections: [TodoSection], yearlyProjects: [YearlyProject]) {
        var sections: [TodoSection] = []
        var yearlyProjects: [YearlyProject] = []
        var currentTitle: String?
        var currentItems: [TodoItem] = []
        var currentYearly: [YearlyProject] = []

        func flushCurrentSection() {
            guard let title = currentTitle else { return }
            if slug(title) == slug(yearlyGoalsTitle) {
                yearlyProjects = currentYearly
            } else {
                sections.append(TodoSection(
                    id: slug(title), title: title,
                    isExpanded: true, items: currentItems
                ))
            }
        }

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("## ") {
                flushCurrentSection()
                currentTitle = String(trimmed.dropFirst(3))
                currentItems = []
                currentYearly = []
            } else if let title = currentTitle, slug(title) == slug(yearlyGoalsTitle),
                      let project = parseYearlyProjectLine(trimmed) {
                currentYearly.append(project)
            } else if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") {
                currentItems.append(TodoItem(text: String(trimmed.dropFirst(6)), done: true))
            } else if trimmed.hasPrefix("- [ ] ") {
                currentItems.append(TodoItem(text: String(trimmed.dropFirst(6)), done: false))
            } else if trimmed.hasPrefix("> "),
                      let last = currentItems.indices.last {
                let noteLine = String(trimmed.dropFirst(2))
                if currentItems[last].notes.isEmpty {
                    currentItems[last].notes = noteLine
                } else {
                    currentItems[last].notes += "\n" + noteLine
                }
            } else if trimmed == ">", let last = currentItems.indices.last {
                currentItems[last].notes += currentItems[last].notes.isEmpty ? "" : "\n"
            }
        }

        flushCurrentSection()

        // Migrate old formats
        let cw = currentCalendarWeek

        // "TODOs - Backlog" (slug: todos-backlog) → "Backlog" (id: backlog)
        for i in 0..<sections.count {
            let id = sections[i].id
            if id != "backlog" && id.contains("backlog") {
                if let existing = sections.firstIndex(where: { $0.id == "backlog" }) {
                    sections[existing].items.append(contentsOf: sections[i].items)
                    sections.remove(at: i)
                } else {
                    sections[i] = TodoSection(
                        id: "backlog", title: "Backlog",
                        isExpanded: true, items: sections[i].items
                    )
                }
                break
            }
        }

        // "TODOs - Weekly" (slug: todos-weekly) → "W{currentWeek}"
        for i in 0..<sections.count {
            if sections[i].id == "todos-weekly" || sections[i].id.contains("weekly") {
                let existingID = "w\(cw)"
                if let existing = sections.firstIndex(where: { $0.id == existingID }) {
                    sections[existing].items.append(contentsOf: sections[i].items)
                    sections.remove(at: i)
                } else {
                    sections[i] = TodoSection(
                        id: existingID, title: "W\(cw)",
                        isExpanded: true, items: sections[i].items
                    )
                }
                break
            }
        }

        if sections.isEmpty {
            return (
                [
                    TodoSection(id: "w\(cw)", title: "W\(cw)", isExpanded: true, items: []),
                    TodoSection(id: "backlog", title: "Backlog", isExpanded: true, items: []),
                ],
                yearlyProjects
            )
        }

        if !sections.contains(where: { $0.id == "backlog" }) {
            sections.append(TodoSection(id: "backlog", title: "Backlog", isExpanded: true, items: []))
        }

        return (sections, yearlyProjects)
    }

    static func render(_ sections: [TodoSection], yearlyProjects: [YearlyProject]) -> String {
        let weekly = sections
            .filter { isWeeklySection($0) && !$0.items.isEmpty }
            .sorted { (weekNumber(from: $0) ?? 0) > (weekNumber(from: $1) ?? 0) }
        let backlog = sections.filter { $0.id == "backlog" }
        let ordered = weekly + backlog

        var lines: [String] = []
        for (i, section) in ordered.enumerated() {
            if i > 0 { lines.append("") }
            lines.append("## \(section.title)")
            lines.append("")
            for item in section.items {
                let check = item.done ? "x" : " "
                lines.append("- [\(check)] \(item.text)")
                let trimmedNotes = item.notes.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedNotes.isEmpty {
                    for noteLine in item.notes.components(separatedBy: "\n") {
                        lines.append("  > \(noteLine)")
                    }
                }
            }
        }

        if !yearlyProjects.isEmpty {
            if !lines.isEmpty { lines.append("") }
            lines.append("## \(yearlyGoalsTitle)")
            lines.append("")
            for project in yearlyProjects {
                var line = "- \(project.title) :: \(project.effectiveProgress)"
                if !project.milestones.isEmpty {
                    let mStr = project.milestones.map { m -> String in
                        let safe = m.title
                            .replacingOccurrences(of: "=", with: "-")
                            .replacingOccurrences(of: ",", with: "-")
                            .replacingOccurrences(of: "|", with: "-")
                        return "\(safe)=\(m.progress)"
                    }.joined(separator: ",")
                    line += " | \(mStr)"
                }
                lines.append(line)
            }
        }

        lines.append("")
        return lines.joined(separator: "\n")
    }

    private static func parseYearlyProjectLine(_ trimmed: String) -> YearlyProject? {
        guard trimmed.hasPrefix("- ") else { return nil }
        let rest = String(trimmed.dropFirst(2))
        let parts = rest.components(separatedBy: " :: ")
        guard parts.count >= 2 else { return nil }
        let title = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let rhs = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)

        // rhs = "50"  or  "75 | Research=80,Design=60"
        let pipeParts = rhs.components(separatedBy: " | ")
        guard let p = Int(pipeParts[0].trimmingCharacters(in: .whitespaces)) else { return nil }

        var milestones: [Milestone] = []
        if pipeParts.count > 1 {
            for entry in pipeParts[1].components(separatedBy: ",") {
                let kv = entry.components(separatedBy: "=")
                guard kv.count == 2,
                      let mp = Int(kv[1].trimmingCharacters(in: .whitespaces))
                else { continue }
                let mTitle = kv[0].trimmingCharacters(in: .whitespaces)
                guard !mTitle.isEmpty else { continue }
                milestones.append(Milestone(title: mTitle, progress: mp))
            }
        }
        return YearlyProject(title: title, progress: p, milestones: milestones)
    }

    private static func slug(_ title: String) -> String {
        title.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }
}

#if canImport(AppKit)
/// Objective-C target/action bridge so we can observe `NSApplication.willTerminateNotification`
/// without the Swift 6 `@Sendable` closure capture warning from using the block-based API.
final class TodoStoreTerminationObserver: NSObject {
    weak var store: TodoStore?

    init(store: TodoStore) {
        self.store = store
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(flush),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func flush() {
        store?.flushPendingSave()
    }
}
#endif
