import Foundation
import Observation

struct TodoItem: Identifiable, Equatable {
    let id: UUID
    var text: String
    var done: Bool

    init(text: String, done: Bool = false) {
        self.id = UUID()
        self.text = text
        self.done = done
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
    let fileURL: URL

    init() {
        let docs = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents")
        let dir = docs.appendingPathComponent("TodoApp")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("todos.md")

        if FileManager.default.fileExists(atPath: fileURL.path),
           let content = try? String(contentsOf: fileURL, encoding: .utf8),
           !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.sections = Self.parse(content)
        } else {
            let cw = Self.currentCalendarWeek
            self.sections = [
                TodoSection(id: "w\(cw)", title: "W\(cw)", isExpanded: true, items: []),
                TodoSection(id: "backlog", title: "Backlog", isExpanded: true, items: []),
            ]
            save()
        }
    }

    func save() {
        let content = Self.render(sections)
        try? content.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    // MARK: - Week management

    static var currentCalendarWeek: Int {
        Calendar.current.component(.weekOfYear, from: Date())
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

    // MARK: - Markdown persistence

    static func parse(_ content: String) -> [TodoSection] {
        var sections: [TodoSection] = []
        var currentTitle: String?
        var currentItems: [TodoItem] = []

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("## ") {
                if let title = currentTitle {
                    sections.append(TodoSection(
                        id: slug(title), title: title,
                        isExpanded: true, items: currentItems
                    ))
                }
                currentTitle = String(trimmed.dropFirst(3))
                currentItems = []
            } else if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") {
                currentItems.append(TodoItem(text: String(trimmed.dropFirst(6)), done: true))
            } else if trimmed.hasPrefix("- [ ] ") {
                currentItems.append(TodoItem(text: String(trimmed.dropFirst(6)), done: false))
            }
        }

        if let title = currentTitle {
            sections.append(TodoSection(
                id: slug(title), title: title,
                isExpanded: true, items: currentItems
            ))
        }

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
            return [
                TodoSection(id: "w\(cw)", title: "W\(cw)", isExpanded: true, items: []),
                TodoSection(id: "backlog", title: "Backlog", isExpanded: true, items: []),
            ]
        }

        if !sections.contains(where: { $0.id == "backlog" }) {
            sections.append(TodoSection(id: "backlog", title: "Backlog", isExpanded: true, items: []))
        }

        return sections
    }

    static func render(_ sections: [TodoSection]) -> String {
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
            }
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private static func slug(_ title: String) -> String {
        title.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }
}
