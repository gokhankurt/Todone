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

// MARK: - Week Picker

struct WeekPickerView: View {
    @Binding var selectedWeek: Int
    var store: TodoStore

    private let currentWeek = TodoStore.currentCalendarWeek
    private let boxWidth: CGFloat = 40
    private let boxSpacing: CGFloat = 6

    @State private var dragOffset: CGFloat = 0
    @State private var baseOffset: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var didInitialize = false

    private var totalBoxWidth: CGFloat { boxWidth + boxSpacing }

    private func offsetForWeek(_ week: Int) -> CGFloat {
        let idx = CGFloat(week - weekRange.first!)
        return -idx * totalBoxWidth + containerWidth / 2 - boxWidth / 2
    }

    var body: some View {
        GeometryReader { geo in
            let weeks = weekRange
            HStack(spacing: boxSpacing) {
                ForEach(weeks, id: \.self) { week in
                    WeekBox(
                        week: week,
                        isSelected: week == selectedWeek,
                        isCurrent: week == currentWeek,
                        hasContent: store.weeksWithContent().contains(week)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedWeek = week
                            store.ensureWeekSection(week)
                            baseOffset = offsetForWeek(week)
                        }
                    }
                    .pointerStyle()
                }
            }
            .offset(x: baseOffset + dragOffset)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        dragOffset = value.translation.width
                    }
                    .onEnded { value in
                        let combined = baseOffset + dragOffset
                        let idx = round(-(combined - containerWidth / 2 + boxWidth / 2) / totalBoxWidth)
                        let clampedIdx = Int(max(0, min(CGFloat(weeks.count - 1), idx)))
                        let snappedWeek = weeks[clampedIdx]
                        withAnimation(.easeOut(duration: 0.25)) {
                            selectedWeek = snappedWeek
                            store.ensureWeekSection(snappedWeek)
                            baseOffset = offsetForWeek(snappedWeek)
                            dragOffset = 0
                        }
                    }
            )
            .onAppear {
                containerWidth = geo.size.width
                if !didInitialize {
                    baseOffset = offsetForWeek(selectedWeek)
                    didInitialize = true
                }
            }
            .onChange(of: geo.size.width) { _, newWidth in
                containerWidth = newWidth
                baseOffset = offsetForWeek(selectedWeek)
            }
        }
        .frame(height: 50)
        .clipped()
    }

    private var weekRange: [Int] {
        let start = max(1, currentWeek - 10)
        let end = min(52, currentWeek + 10)
        return Array(start...end)
    }
}

struct WeekBox: View {
    let week: Int
    let isSelected: Bool
    let isCurrent: Bool
    let hasContent: Bool

    var body: some View {
        VStack(spacing: 3) {
            Text("W\(week)")
                .font(.system(size: 12, weight: isSelected ? .bold : .regular, design: .monospaced))
                .foregroundStyle(isSelected ? Color(.windowBackgroundColor) : .primary)
                .frame(width: 40, height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isSelected ? Color.primary : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.primary.opacity(isSelected ? 0 : 0.25), lineWidth: 1)
                )

            Circle()
                .fill(Color.primary.opacity(hasContent && !isSelected ? 0.3 : 0))
                .frame(width: 4, height: 4)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Content View

struct ContentView: View {
    @State private var store = TodoStore()
    @State private var selectedWeek = TodoStore.currentCalendarWeek

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                WeekPickerView(selectedWeek: $selectedWeek, store: store)
                    .padding(.bottom, 4)

                if let weekSection = store.sections.first(where: { $0.id == "w\(selectedWeek)" }) {
                    SectionView(
                        section: weekSection,
                        store: store,
                        displayTitle: "TODOs - Weekly",
                        moveTargetID: "backlog",
                        moveIsUp: false
                    )
                    .id(weekSection.id)
                }

                if let backlog = store.sections.first(where: { $0.id == "backlog" }) {
                    SectionView(
                        section: backlog,
                        store: store,
                        moveTargetID: "w\(selectedWeek)",
                        moveIsUp: true
                    )
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
        .background(Color(.windowBackgroundColor))
        .onAppear {
            store.ensureWeekSection(selectedWeek)
        }
        .onChange(of: selectedWeek) {
            store.ensureWeekSection(selectedWeek)
        }
    }
}

// MARK: - Section

struct SectionView: View {
    let section: TodoSection
    var store: TodoStore
    var displayTitle: String? = nil
    var moveTargetID: String? = nil
    var moveIsUp: Bool = false
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

                    Text(displayTitle ?? section.title)
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                        .foregroundStyle(.primary)
                }
            }
            .buttonStyle(.plain)
            .pointerStyle()
            .padding(.bottom, 6)

            if section.isExpanded {
                let pending = section.items.filter { !$0.done }
                let done = section.items.filter { $0.done }

                ForEach(pending) { item in
                    TodoRowView(
                        item: item,
                        sectionID: section.id,
                        store: store,
                        moveTargetID: moveTargetID,
                        moveIsUp: moveIsUp
                    )
                }

                AddTaskRow(text: $newTaskText) {
                    let trimmed = newTaskText.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    store.addItem(sectionID: section.id, text: trimmed)
                    newTaskText = ""
                }

                if !done.isEmpty {
                    CompletedGroup(
                        items: done,
                        sectionID: section.id,
                        store: store,
                        moveTargetID: moveTargetID,
                        moveIsUp: moveIsUp
                    )
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
    var moveTargetID: String?
    var moveIsUp: Bool
    @State private var editText: String
    @State private var isHovered = false
    @State private var strikeProgress: CGFloat
    @State private var dimmed: Bool

    init(item: TodoItem, sectionID: String, store: TodoStore,
         moveTargetID: String? = nil, moveIsUp: Bool = false) {
        self.item = item
        self.sectionID = sectionID
        self.store = store
        self.moveTargetID = moveTargetID
        self.moveIsUp = moveIsUp
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
                if let target = moveTargetID {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            store.moveItem(itemID: item.id, fromSection: sectionID, toSection: target)
                        }
                    } label: {
                        Image(systemName: moveIsUp ? "arrow.up" : "arrow.down")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .pointerStyle()
                    .help(moveIsUp ? "Move to Weekly" : "Move to Backlog")
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
                .fill(isHovered ? Color.primary.opacity(0.05) : .clear)
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
    var moveTargetID: String? = nil
    var moveIsUp: Bool = false
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
                    TodoRowView(
                        item: item,
                        sectionID: sectionID,
                        store: store,
                        moveTargetID: moveTargetID,
                        moveIsUp: moveIsUp
                    )
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
