import SwiftUI
import AppKit

private struct PointingHandCursor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { PointerView() }
    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.window?.invalidateCursorRects(for: nsView)
    }

    class PointerView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }
}

extension View {
    func pointerStyle() -> some View {
        self.overlay { PointingHandCursor() }
    }
}

struct ContentView: View {
    @State private var store = TodoStore()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(store.sections) { section in
                    SectionView(section: section, store: store)
                }

                Text("Because done feels good.")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.quaternary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 12)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.white)
    }
}

// MARK: - Section

struct SectionView: View {
    let section: TodoSection
    var store: TodoStore
    @State private var newTaskText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    store.toggleSection(section.id)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(section.isExpanded ? 90 : 0))

                    Text(section.title)
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                        .foregroundStyle(.primary)

                    if section.id.contains("weekly") {
                        Text("W\(Calendar.current.component(.weekOfYear, from: Date()))")
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .pointerStyle()
            .padding(.bottom, 6)

            if section.isExpanded {
                let pending = section.items.filter { !$0.done }
                let done = section.items.filter { $0.done }

                ForEach(pending) { item in
                    TodoRowView(item: item, sectionID: section.id, store: store)
                }

                AddTaskRow(text: $newTaskText) {
                    let trimmed = newTaskText.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    store.addItem(sectionID: section.id, text: trimmed)
                    newTaskText = ""
                }

                if !done.isEmpty {
                    CompletedGroup(items: done, sectionID: section.id, store: store)
                }
            }
        }
    }
}

// MARK: - Todo Row

struct TodoRowView: View {
    let item: TodoItem
    let sectionID: String
    var store: TodoStore
    @State private var editText: String
    @State private var isHovered = false
    @State private var strikeProgress: CGFloat
    @State private var dimmed: Bool

    init(item: TodoItem, sectionID: String, store: TodoStore) {
        self.item = item
        self.sectionID = sectionID
        self.store = store
        self._editText = State(initialValue: item.text)
        self._strikeProgress = State(initialValue: item.done ? 1 : 0)
        self._dimmed = State(initialValue: item.done)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    store.toggleItem(sectionID: sectionID, itemID: item.id)
                }
            } label: {
                Text(item.done ? "[x]" : "[ ]")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(dimmed ? .secondary : .primary)
            }
            .buttonStyle(.plain)
            .pointerStyle()
            .frame(width: 36, alignment: .leading)

            if item.done {
                Text(editText)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .overlay {
                        Rectangle()
                            .fill(Color(.labelColor).opacity(0.35))
                            .frame(height: 1)
                            .scaleEffect(x: strikeProgress, y: 1, anchor: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField("", text: $editText, axis: .vertical)
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.plain)
                    .foregroundStyle(.primary)
                    .lineLimit(1...10)
                    .onChange(of: editText) {
                        store.updateItemText(sectionID: sectionID, itemID: item.id, text: editText)
                    }
            }

        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .trailing) {
            HStack(spacing: 2) {
                if let target = store.targetSectionID(for: sectionID) {
                    let isBacklog = sectionID != store.sections.first?.id
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            store.moveItem(itemID: item.id, fromSection: sectionID, toSection: target)
                        }
                    } label: {
                        Image(systemName: isBacklog ? "arrow.up" : "arrow.down")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .pointerStyle()
                    .help(isBacklog ? "Move to Weekly" : "Move to Backlog")
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        store.deleteItem(sectionID: sectionID, itemID: item.id)
                    }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .pointerStyle()
            }
            .opacity(isHovered ? 1 : 0)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 3)
                .fill(isHovered ? Color.black.opacity(0.035) : .clear)
        )
        .onHover { isHovered = $0 }
        .onChange(of: item.done) {
            if item.done {
                strikeProgress = 0
                dimmed = true
                withAnimation(.easeOut(duration: 0.2)) {
                    strikeProgress = 1
                }
            } else {
                strikeProgress = 0
                dimmed = false
            }
        }
    }
}

// MARK: - Completed Group

struct CompletedGroup: View {
    let items: [TodoItem]
    let sectionID: String
    var store: TodoStore
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))

                    Text("\(items.count) completed")
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            .pointerStyle()
            .padding(.top, 6)
            .padding(.bottom, 2)

            if isExpanded {
                ForEach(items) { item in
                    TodoRowView(item: item, sectionID: sectionID, store: store)
                }
            }
        }
    }
}

// MARK: - Add Task

struct AddTaskRow: View {
    @Binding var text: String
    var onSubmit: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("[ ]")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.clear)
                .frame(width: 36, alignment: .leading)

            TextField("Add task…", text: $text)
                .font(.system(.body, design: .monospaced))
                .textFieldStyle(.plain)
                .onSubmit(onSubmit)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }
}
