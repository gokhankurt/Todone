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
            self.sections = Self.defaultSections
            save()
        }
    }

    func save() {
        let content = Self.render(sections)
        try? content.write(to: fileURL, atomically: true, encoding: .utf8)
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

    func targetSectionID(for sectionID: String) -> String? {
        guard let idx = sections.firstIndex(where: { $0.id == sectionID }) else { return nil }
        if idx == 0 && sections.count > 1 { return sections[1].id }
        if idx > 0 { return sections[0].id }
        return nil
    }

    func toggleSection(_ sectionID: String) {
        guard let si = sections.firstIndex(where: { $0.id == sectionID }) else { return }
        sections[si].isExpanded.toggle()
    }

    // MARK: - Markdown parsing

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

        return sections.isEmpty ? defaultSections : sections
    }

    static func render(_ sections: [TodoSection]) -> String {
        var lines: [String] = []
        for (i, section) in sections.enumerated() {
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

    static let defaultSections: [TodoSection] = [
        TodoSection(id: "todos-weekly", title: "TODOs - Weekly", isExpanded: true, items: []),
        TodoSection(id: "backlog", title: "Backlog", isExpanded: true, items: []),
    ]
}
