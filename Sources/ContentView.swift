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
        let contentWeeks = store.weeksWithContent()
        GeometryReader { geo in
            let weeks = weekRange
            HStack(spacing: boxSpacing) {
                ForEach(weeks, id: \.self) { week in
                    WeekBox(
                        week: week,
                        isSelected: week == selectedWeek,
                        isCurrent: week == currentWeek,
                        hasContent: contentWeeks.contains(week)
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
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.06),
                    .init(color: .black, location: 0.94),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
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

    private var isPast: Bool { week < TodoStore.currentCalendarWeek }

    var body: some View {
        VStack(spacing: 4) {
            Text("W\(week)")
                .font(.system(size: 11, weight: isSelected ? .bold : .medium, design: .monospaced))
                .foregroundStyle(isSelected ? Color(.windowBackgroundColor) : (isPast ? .secondary : .primary))
                .frame(width: 40, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isSelected ? Color.primary : (isPast ? Color.primary.opacity(0.05) : Color.primary.opacity(0.03)))
                )

            Circle()
                .fill(hasContent && !isSelected ? Color.primary.opacity(0.35) : Color.clear)
                .frame(width: 4, height: 4)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Folder Tab Shape

/// Browser-style folder tab: rounded convex top corners, concave bottom corners.
/// The path extends `concaveRadius` beyond the rect on both sides at y = height,
/// letting adjacent tabs share a smooth valley that reveals the window background.
private struct FolderTabShape: Shape {
    var cornerRadius: CGFloat = 13
    var concaveRadius: CGFloat = 9

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height
        let r = min(cornerRadius, w / 2, h / 2)
        let c = concaveRadius

        // In SwiftUI (y-axis down), clockwise: true = visually clockwise on screen.
        // Arc angles: 0°=right, 90°=down, 180°=left, 270°=up.

        // Start at extended bottom-left
        p.move(to: CGPoint(x: -c, y: h))

        // Concave arc BL: center(0,h), 180°→270° CW → sweeps upper-left = concave inward
        p.addArc(center: CGPoint(x: 0, y: h), radius: c,
                 startAngle: .degrees(180), endAngle: .degrees(270), clockwise: true)

        // Left edge up
        p.addLine(to: CGPoint(x: 0, y: r))

        // Convex arc TL: center(r,r), 180°→270° CW → sweeps upper-left = convex outward
        p.addArc(center: CGPoint(x: r, y: r), radius: r,
                 startAngle: .degrees(180), endAngle: .degrees(270), clockwise: true)

        // Top edge
        p.addLine(to: CGPoint(x: w - r, y: 0))

        // Convex arc TR: center(w-r,r), 270°→0° CW → sweeps upper-right = convex outward
        p.addArc(center: CGPoint(x: w - r, y: r), radius: r,
                 startAngle: .degrees(270), endAngle: .degrees(0), clockwise: true)

        // Right edge down
        p.addLine(to: CGPoint(x: w, y: h - c))

        // Concave arc BR: center(w,h), 270°→0° CW → sweeps upper-right = concave inward
        p.addArc(center: CGPoint(x: w, y: h), radius: c,
                 startAngle: .degrees(270), endAngle: .degrees(0), clockwise: true)

        // Extended bottom-right, then close across the bottom
        p.addLine(to: CGPoint(x: w + c, y: h))
        p.closeSubpath()
        return p
    }
}

// MARK: - Folder index (archive / card tabs)

/// High-contrast “index drawer” colors — system neutrals matched the window and hid the folders.
private enum FolderArchivePalette {
    static func drawer(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.22, green: 0.22, blue: 0.24)
            : Color(red: 0.72, green: 0.72, blue: 0.74)
    }

    static func drawerLip(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.16, green: 0.16, blue: 0.18)
            : Color(red: 0.62, green: 0.62, blue: 0.65)
    }

    static func paper(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.14, green: 0.14, blue: 0.16)
            : Color.white
    }

    static func ink(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.92) : Color.black
    }

    static let sticker = Color(red: 0.98, green: 0.92, blue: 0.38)

    static func outerStrokeWidth(for scheme: ColorScheme) -> CGFloat {
        scheme == .dark ? 1.5 : 2
    }
}

/// Card-index drawer shell: gray cavity, thick outline, yellow “drawer label”.
private struct FolderArchiveDrawer<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @ViewBuilder var content: () -> Content

    var body: some View {
        let scheme = colorScheme
        VStack(spacing: 0) {
            content()
                .padding(EdgeInsets(top: 14, leading: 14, bottom: 12, trailing: 14))
            ZStack {
                FolderArchivePalette.drawerLip(for: scheme)
                Text("Todone")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .textCase(.lowercase)
                    .foregroundStyle(FolderArchivePalette.ink(for: scheme))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(FolderArchivePalette.sticker)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .stroke(FolderArchivePalette.ink(for: scheme), lineWidth: 1)
                    )
            }
            .frame(height: 28)
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(FolderArchivePalette.drawer(for: scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(FolderArchivePalette.ink(for: scheme), lineWidth: FolderArchivePalette.outerStrokeWidth(for: scheme))
        )
        .shadow(color: Color.black.opacity(scheme == .dark ? 0.45 : 0.18), radius: 6, y: 3)
    }
}

/// Black index tab — current calendar week (like the left column in a card index).
private struct FolderRootWeekTab: View {
    @Environment(\.colorScheme) private var colorScheme
    let week: Int

    var body: some View {
        let scheme = colorScheme
        let ink = FolderArchivePalette.ink(for: scheme)
        let paper = FolderArchivePalette.paper(for: scheme)
        VStack(spacing: 1) {
            Text("W")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
            Text("\(week)")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
        }
        .foregroundStyle(scheme == .dark ? paper : Color.white)
        .frame(width: 44, height: 56)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 8, bottomLeadingRadius: 4, bottomTrailingRadius: 4, topTrailingRadius: 8,
                style: .continuous
            )
            .fill(ink)
        )
        .overlay(
            UnevenRoundedRectangle(
                topLeadingRadius: 8, bottomLeadingRadius: 4, bottomTrailingRadius: 4, topTrailingRadius: 8,
                style: .continuous
            )
            .stroke(ink.opacity(scheme == .dark ? 0.4 : 0.25), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 3, y: 2)
    }
}

/// White folder tab + card body; `slot` staggers tabs (three columns like a card index).
private struct FolderCategoryCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let slot: Int
    let code: String
    let title: String
    let isExpanded: Bool
    var isColumn: Bool = false
    let onToggle: () -> Void
    @ViewBuilder var cardContent: () -> Content

    private func leadingFlex(for slot: Int) -> CGFloat {
        switch slot % 3 {
        case 0: return 8
        case 1: return 108
        default: return 52
        }
    }

    private func trailingFlex(for slot: Int) -> CGFloat {
        switch slot % 3 {
        case 0: return 124
        case 1: return 12
        default: return 104
        }
    }

    var body: some View {
        let scheme = colorScheme
        let ink = FolderArchivePalette.ink(for: scheme)
        let paper = FolderArchivePalette.paper(for: scheme)

        if isColumn {
            columnCard(scheme: scheme, ink: ink, paper: paper)
        } else {
            folderTabCard(scheme: scheme, ink: ink, paper: paper)
        }
    }

    @ViewBuilder
    private func columnCard(scheme: ColorScheme, ink: Color, paper: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: 8) {
                    Text(code)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(ink.opacity(0.35))
                    Text(title)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(ink.opacity(0.3))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .foregroundStyle(ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .pointerStyle()

            if isExpanded {
                Rectangle()
                    .fill(ink.opacity(0.1))
                    .frame(height: 1)
                cardContent()
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(paper)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(ink.opacity(scheme == .dark ? 0.2 : 0.13), lineWidth: 1)
        )
        .shadow(color: .black.opacity(scheme == .dark ? 0.18 : 0.05), radius: 4, y: 2)
    }

    @ViewBuilder
    private func folderTabCard(scheme: ColorScheme, ink: Color, paper: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                Spacer(minLength: 0)
                    .frame(maxWidth: leadingFlex(for: slot))
                Button(action: onToggle) {
                    HStack(spacing: 10) {
                        Text(code)
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .frame(minWidth: 24, alignment: .leading)
                        Text(title)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .lineLimit(1)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(ink.opacity(0.45))
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                    .foregroundStyle(ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 9, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 9,
                            style: .continuous
                        )
                        .fill(paper)
                    )
                    .overlay(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 9, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 9,
                            style: .continuous
                        )
                        .stroke(ink, lineWidth: scheme == .dark ? 1.25 : 1.5)
                    )
                    .shadow(color: .black.opacity(scheme == .dark ? 0.35 : 0.12), radius: 2, y: 2)
                }
                .buttonStyle(.plain)
                .pointerStyle()
                Spacer(minLength: 0)
                    .frame(maxWidth: trailingFlex(for: slot))
            }

            if isExpanded {
                cardContent()
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(paper)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .stroke(ink, lineWidth: scheme == .dark ? 1.25 : 1.5)
                            )
                    )
                    .offset(y: -2)
                    .shadow(color: .black.opacity(scheme == .dark ? 0.3 : 0.1), radius: 2, y: 2)
            }
        }
        .zIndex(Double(100 - slot))
    }
}

// MARK: - Milestone Palette

private enum MilestonePalette {
    static let colors: [Color] = [
        Color(red: 0.38, green: 0.52, blue: 0.95),
        Color(red: 0.62, green: 0.38, blue: 0.90),
        Color(red: 0.92, green: 0.42, blue: 0.58),
        Color(red: 0.24, green: 0.72, blue: 0.52),
        Color(red: 0.95, green: 0.62, blue: 0.22),
        Color(red: 0.22, green: 0.70, blue: 0.84),
        Color(red: 0.96, green: 0.50, blue: 0.28),
        Color(red: 0.52, green: 0.78, blue: 0.32),
    ]
    static func color(at i: Int) -> Color { colors[i % colors.count] }
}

// MARK: - Donut Chart

struct DonutChartView: View {
    struct Segment {
        let color: Color
        let filled: Double  // 0.0 – 1.0
    }

    let segments: [Segment]
    let centerLabel: String
    let centerSublabel: String

    var body: some View {
        GeometryReader { geo in
            let sz = min(geo.size.width, geo.size.height)
            let cx = geo.size.width / 2
            let cy = geo.size.height / 2
            let center = CGPoint(x: cx, y: cy)
            let outerR = sz / 2 - 4
            let trackW = max(18, sz * 0.13)
            let midR = outerR - trackW / 2
            let n = max(1, segments.count)
            let gapDeg: Double = n > 1 ? 3.0 : 0.0

            ZStack {
                ForEach(0..<n, id: \.self) { i in
                    let sliceDeg = 360.0 / Double(n)
                    let sliceStart = Double(i) * sliceDeg - 90.0
                    let available = sliceDeg - gapDeg
                    let adjStart = sliceStart + gapDeg / 2
                    let adjEnd = adjStart + available
                    let fillFrac = max(0, min(1, segments[i].filled))
                    let fillEnd = adjStart + available * fillFrac

                    Path { path in
                        path.addArc(center: center, radius: midR,
                                    startAngle: .degrees(adjStart),
                                    endAngle: .degrees(adjEnd),
                                    clockwise: false)
                    }
                    .stroke(Color.primary.opacity(0.08),
                            style: StrokeStyle(lineWidth: trackW, lineCap: .butt))

                    if fillFrac > 0.005 {
                        Path { path in
                            path.addArc(center: center, radius: midR,
                                        startAngle: .degrees(adjStart),
                                        endAngle: .degrees(fillEnd),
                                        clockwise: false)
                        }
                        .stroke(segments[i].color,
                                style: StrokeStyle(lineWidth: trackW, lineCap: .butt))
                    }
                }

                VStack(spacing: 3) {
                    Text(centerLabel)
                        .font(.system(size: sz * 0.17, weight: .bold, design: .monospaced))
                        .foregroundStyle(.primary)
                    if !centerSublabel.isEmpty {
                        Text(centerSublabel)
                            .font(.system(size: sz * 0.08, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .position(center)
            }
        }
    }
}

// MARK: - Milestone Row

private struct MilestoneRow: View {
    let milestone: Milestone
    let projectID: UUID
    let colorIndex: Int
    var store: TodoStore
    @State private var titleText: String
    @State private var isHovered = false
    @State private var progressHover = false

    init(milestone: Milestone, projectID: UUID, colorIndex: Int, store: TodoStore) {
        self.milestone = milestone
        self.projectID = projectID
        self.colorIndex = colorIndex
        self.store = store
        _titleText = State(initialValue: milestone.title)
    }

    private var color: Color { MilestonePalette.color(at: colorIndex) }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            TextField("Milestone name", text: $titleText)
                .font(.system(.body, design: .monospaced))
                .textFieldStyle(.plain)
                .onChange(of: titleText) { _, new in
                    store.updateMilestoneTitle(projectID: projectID, milestoneID: milestone.id, title: new)
                }

            Spacer(minLength: 8)

            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(color.opacity(0.72))
                    .frame(width: 72 * CGFloat(milestone.progress) / 100, height: 5)
            }
            .frame(width: 72, height: 5)

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(milestone.progress)%")
                    .font(.system(.callout, design: .monospaced).weight(.medium))
                    .foregroundStyle(progressHover ? .primary : .secondary)
                    .monospacedDigit()
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(progressHover ? Color.primary.opacity(0.08) : Color.clear)
                    )

                if progressHover {
                    Slider(
                        value: Binding(
                            get: { Double(milestone.progress) },
                            set: { store.setMilestoneProgress(projectID: projectID, milestoneID: milestone.id, progress: Int($0.rounded())) }
                        ),
                        in: 0...100, step: 1
                    )
                    .controlSize(.mini)
                    .frame(width: 100)
                }
            }
            .animation(.easeInOut(duration: 0.12), value: progressHover)
            .onHover { progressHover = $0 }
            .pointerStyle()

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    store.deleteMilestone(projectID: projectID, milestoneID: milestone.id)
                }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .pointerStyle()
            .opacity(isHovered ? 1 : 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovered ? Color.primary.opacity(0.04) : Color.clear)
        )
        .onHover { isHovered = $0 }
        .onChange(of: milestone.title) { _, new in
            if new != titleText { titleText = new }
        }
    }
}

// MARK: - Yearly Project Detail View

struct YearlyProjectDetailView: View {
    let projectID: UUID
    var store: TodoStore
    @Environment(\.dismiss) private var dismiss
    @State private var newMilestoneText = ""
    @State private var chartVisible = false

    private let suggestions = ["Research", "Ideation", "Design", "Development", "Alignment"]

    private var project: YearlyProject? {
        store.yearlyProjects.first { $0.id == projectID }
    }

    var body: some View {
        Group {
            if let project = project {
                VStack(spacing: 0) {
                    headerBar(title: project.title)
                    Divider()
                    ScrollView {
                        VStack(spacing: 0) {
                            chartSection(project: project)
                            Divider()
                                .padding(.horizontal, 24)
                            milestonesSection(project: project)
                        }
                        .padding(.bottom, 24)
                    }
                }
                .background(Color(.windowBackgroundColor))
            }
        }
        .frame(width: 460, height: 560)
    }

    @ViewBuilder
    private func headerBar(title: String) -> some View {
        HStack(alignment: .center) {
            Text(title)
                .font(.system(.headline, design: .monospaced).weight(.bold))
                .lineLimit(2)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.primary.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .pointerStyle()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private func chartSection(project: YearlyProject) -> some View {
        let segments = segmentsFor(project: project)
        let label = "\(project.effectiveProgress)%"
        let sublabel = project.milestones.isEmpty ? "" : "overall"

        VStack(spacing: 12) {
            DonutChartView(segments: segments, centerLabel: label, centerSublabel: sublabel)
                .frame(width: 200, height: 200)
                .opacity(chartVisible ? 1 : 0)
                .scaleEffect(chartVisible ? 1 : 0.88)
                .onAppear {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                        chartVisible = true
                    }
                }

            if !project.milestones.isEmpty {
                legendView(milestones: project.milestones)
            }
        }
        .padding(.vertical, 24)
    }

    @ViewBuilder
    private func legendView(milestones: [Milestone]) -> some View {
        let cols = 3
        let rows = (milestones.count + cols - 1) / cols
        VStack(spacing: 4) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 14) {
                    ForEach(0..<cols, id: \.self) { col in
                        let idx = row * cols + col
                        if idx < milestones.count {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(MilestonePalette.color(at: idx))
                                    .frame(width: 6, height: 6)
                                Text(milestones[idx].title)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        } else {
                            Spacer()
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func milestonesSection(project: YearlyProject) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Milestones")
                .font(.system(.callout, design: .monospaced).weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, 16)

            if project.milestones.isEmpty {
                emptyMilestonesView
            } else {
                ForEach(Array(project.milestones.enumerated()), id: \.element.id) { idx, milestone in
                    MilestoneRow(
                        milestone: milestone,
                        projectID: projectID,
                        colorIndex: idx,
                        store: store
                    )
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .frame(width: 20)

                TextField("Add milestone…", text: $newMilestoneText)
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.plain)
                    .onSubmit {
                        let t = newMilestoneText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !t.isEmpty else { return }
                        store.addMilestone(projectID: projectID, title: t)
                        newMilestoneText = ""
                    }
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
        }
    }

    @ViewBuilder
    private var emptyMilestonesView: some View {
        VStack(spacing: 14) {
            Text("Break this project into milestones\nto track detailed progress.")
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            HStack(spacing: 6) {
                ForEach(suggestions, id: \.self) { s in
                    Button {
                        store.addMilestone(projectID: projectID, title: s)
                    } label: {
                        Text(s)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(Color.primary.opacity(0.18), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .pointerStyle()
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 12)
    }

    private func segmentsFor(project: YearlyProject) -> [DonutChartView.Segment] {
        if project.milestones.isEmpty {
            return [DonutChartView.Segment(
                color: MilestonePalette.color(at: 0),
                filled: Double(project.progress) / 100.0
            )]
        }
        return project.milestones.enumerated().map { idx, m in
            DonutChartView.Segment(
                color: MilestonePalette.color(at: idx),
                filled: Double(m.progress) / 100.0
            )
        }
    }
}

// MARK: - Task Selection

struct TaskSelection: Equatable {
    let sectionID: String
    let itemID: UUID
}

// MARK: - App Palette

enum AppPalette {
    static func root(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.09, green: 0.09, blue: 0.10)
            : Color(red: 0.935, green: 0.935, blue: 0.945)
    }

    static func card(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.14, green: 0.14, blue: 0.16)
            : Color.white
    }

    static func detailCard(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.19, green: 0.16, blue: 0.24)
            : Color(red: 0.955, green: 0.935, blue: 0.985)
    }

    static func accent(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.76, green: 0.58, blue: 1.00)
            : Color(red: 0.46, green: 0.24, blue: 0.76)
    }

    static func accentSoft(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.76, green: 0.58, blue: 1.00).opacity(0.22)
            : Color(red: 0.46, green: 0.24, blue: 0.76).opacity(0.12)
    }

    static func cardStroke(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color.white.opacity(0.06)
            : Color.black.opacity(0.05)
    }

    static func detailStroke(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.76, green: 0.58, blue: 1.00).opacity(0.22)
            : Color(red: 0.46, green: 0.24, blue: 0.76).opacity(0.16)
    }

    static func cardShadow(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color.black.opacity(0.35)
            : Color.black.opacity(0.06)
    }

    static let panelAnimationDuration: Double = 0.32
    static var panelAnimation: Animation { .easeInOut(duration: panelAnimationDuration) }
}

// MARK: - Content View

struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var store = TodoStore()
    @State private var selectedWeek = TodoStore.currentCalendarWeek
    @State private var selectedTab: Int = 0
    @State private var selection: TaskSelection? = nil
    @State private var savedWindowWidth: CGFloat? = nil

    private let detailPanelWidth: CGFloat = 380
    private let expandedMinWindowWidth: CGFloat = 900

    private var sectionTitle: String {
        switch selectedTab {
        case 0:
            return selectedWeek == TodoStore.currentCalendarWeek ? "This week" : "Week \(selectedWeek)"
        case 1:
            return "Backlog"
        default:
            return "Yearly goals"
        }
    }

    var body: some View {
        ZStack {
            AppPalette.root(for: colorScheme)
                .ignoresSafeArea()

            HStack(spacing: 12) {
                mainColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(AppPalette.card(for: colorScheme))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(AppPalette.cardStroke(for: colorScheme), lineWidth: 1)
                    )
                    .shadow(color: AppPalette.cardShadow(for: colorScheme), radius: 14, y: 4)

                if let sel = selection {
                    TaskDetailPanel(
                        sectionID: sel.sectionID,
                        itemID: sel.itemID,
                        store: store,
                        onClose: { closeDetail() }
                    )
                    .frame(width: detailPanelWidth)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(AppPalette.detailCard(for: colorScheme))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(AppPalette.detailStroke(for: colorScheme), lineWidth: 1)
                    )
                    .shadow(color: AppPalette.cardShadow(for: colorScheme), radius: 14, y: 4)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
                }
            }
            .padding(12)
        }
        .animation(AppPalette.panelAnimation, value: selection)
        .onChange(of: selection) { _, newValue in
            handleWindowResize(detailOpen: newValue != nil)
        }
        .onAppear {
            store.ensureWeekSection(selectedWeek)
        }
        .onChange(of: selectedWeek) {
            store.ensureWeekSection(selectedWeek)
            selectedTab = 0
            closeDetail()
        }
        .onChange(of: selectedTab) {
            closeDetail()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            let cw = TodoStore.currentCalendarWeek
            if cw != selectedWeek {
                selectedWeek = cw
                selectedTab = 0
                store.ensureWeekSection(cw)
                closeDetail()
            }
        }
    }

    @ViewBuilder
    private var mainColumn: some View {
        VStack(spacing: 0) {
            WeekPickerView(selectedWeek: $selectedWeek, store: store)
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 8)

            MinimalTabBar(selectedTab: $selectedTab)
                .padding(.horizontal, 24)
                .padding(.bottom, 18)

            HStack {
                Text(sectionTitle)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 6)

            SectionTabContent(
                store: store,
                selectedWeek: selectedWeek,
                selectedTab: selectedTab,
                selection: $selection
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func closeDetail() {
        guard selection != nil else { return }
        selection = nil
    }

    // MARK: - Window resize

    private func handleWindowResize(detailOpen: Bool) {
        guard let window = NSApp.keyWindow
            ?? NSApp.mainWindow
            ?? NSApp.windows.first(where: { $0.isVisible && $0.contentViewController != nil })
        else { return }

        if detailOpen {
            if window.frame.width < expandedMinWindowWidth {
                if savedWindowWidth == nil {
                    savedWindowWidth = window.frame.width
                }
                resize(window: window, to: expandedMinWindowWidth)
            }
        } else if let saved = savedWindowWidth {
            resize(window: window, to: saved)
            savedWindowWidth = nil
        }
    }

    private func resize(window: NSWindow, to targetWidth: CGFloat) {
        let current = window.frame
        guard abs(current.width - targetWidth) > 1 else { return }
        var newX = current.origin.x
        if let screen = window.screen {
            let maxX = screen.visibleFrame.maxX - targetWidth
            newX = max(screen.visibleFrame.minX, min(newX, maxX))
        }
        let newFrame = NSRect(x: newX, y: current.origin.y, width: targetWidth, height: current.height)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = AppPalette.panelAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            window.animator().setFrame(newFrame, display: true)
        }
    }
}

// MARK: - Minimal Tab Bar

private struct MinimalTabBar: View {
    @Binding var selectedTab: Int

    private let labels = ["WEEKLY", "BACKLOG", "YEARLY"]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<labels.count, id: \.self) { i in
                TerminalTabItem(
                    label: labels[i],
                    isSelected: selectedTab == i,
                    action: {
                        withAnimation(.easeOut(duration: 0.18)) {
                            selectedTab = i
                        }
                    }
                )
                if i < labels.count - 1 {
                    Text("│")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.22))
                        .padding(.horizontal, 2)
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .overlay(alignment: .leading) {
            Text("▍")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.35))
                .offset(x: -14)
        }
    }
}

private struct TerminalTabItem: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false
    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Text("[")
                    .opacity(bracketOpacity)

                Text(label)
                    .fontWeight(isSelected ? .bold : .regular)

                Text("]")
                    .opacity(bracketOpacity)
            }
            .font(.system(size: 11, design: .monospaced))
            .tracking(1.8)
            .foregroundStyle(textColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(
                Rectangle()
                    .fill(.white.opacity(pressed ? 0.08 : 0))
            )
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(.white)
                    .frame(height: 1)
                    .opacity(isSelected ? 0.9 : 0)
                    .padding(.horizontal, 4)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .pointerStyle()
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
    }

    private var textColor: Color {
        if isSelected { return .white }
        return .white.opacity(hovering ? 0.85 : 0.5)
    }

    private var bracketOpacity: Double {
        if isSelected { return 1 }
        return hovering ? 0.35 : 0
    }
}

// MARK: - Section Tab Content

private struct SectionTabContent: View {
    var store: TodoStore
    var selectedWeek: Int
    var selectedTab: Int
    @Binding var selection: TaskSelection?

    var body: some View {
        switch selectedTab {
        case 0:
            if let section = store.sections.first(where: { $0.id == "w\(selectedWeek)" }) {
                TodoTabContent(section: section, store: store,
                               moveTargetID: "backlog", moveIsUp: false,
                               selection: $selection)
                .id(section.id)
            }
        case 1:
            if let section = store.sections.first(where: { $0.id == "backlog" }) {
                TodoTabContent(section: section, store: store,
                               moveTargetID: "w\(selectedWeek)", moveIsUp: true,
                               selection: $selection)
            }
        default:
            YearlyGoalsTabContent(store: store)
        }
    }
}

// MARK: - Todo Tab Content

private struct TodoTabContent: View {
    let section: TodoSection
    var store: TodoStore
    var moveTargetID: String?
    var moveIsUp: Bool
    @Binding var selection: TaskSelection?
    @State private var newTaskText = ""

    var body: some View {
        let pending = section.items.filter { !$0.done }
        let done = section.items.filter { $0.done }

        List {
            ForEach(pending) { item in
                TodoRowView(item: item, sectionID: section.id, store: store,
                            moveTargetID: moveTargetID, moveIsUp: moveIsUp,
                            selection: $selection)
                .listRowInsets(EdgeInsets(top: 2, leading: 22, bottom: 2, trailing: 22))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
            .onMove { indices, offset in
                store.reorderPendingItems(sectionID: section.id, fromOffsets: indices, toOffset: offset)
            }

            AddTaskRow(text: $newTaskText) {
                let t = newTaskText.trimmingCharacters(in: .whitespaces)
                guard !t.isEmpty else { return }
                store.addItem(sectionID: section.id, text: t)
                newTaskText = ""
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 22, bottom: 4, trailing: 22))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)

            if !done.isEmpty {
                CompletedGroup(items: done, sectionID: section.id, store: store,
                               moveTargetID: moveTargetID, moveIsUp: moveIsUp,
                               selection: $selection)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 30)
    }
}

// MARK: - Yearly Goals Tab Content

private struct YearlyGoalsTabContent: View {
    var store: TodoStore
    @State private var newProjectTitle = ""

    var body: some View {
        List {
            if store.yearlyProjects.isEmpty {
                Text("Add long-term projects and track progress toward the year.")
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .listRowInsets(EdgeInsets(top: 8, leading: 22, bottom: 4, trailing: 22))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }

            ForEach(store.yearlyProjects) { project in
                YearlyProjectRow(project: project, store: store)
                    .listRowInsets(EdgeInsets(top: 4, leading: 22, bottom: 4, trailing: 22))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }

            HStack(spacing: 8) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .frame(width: 22)
                TextField("Add yearly goal…", text: $newProjectTitle)
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.plain)
                    .onSubmit {
                        let t = newProjectTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !t.isEmpty else { return }
                        store.addYearlyProject(title: t)
                        newProjectTitle = ""
                    }
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 22, bottom: 4, trailing: 22))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 30)
    }
}

// MARK: - Todo folder (inner list keeps drag reorder)

private struct TodoFolderSection: View {
    let slot: Int
    let code: String
    let title: String
    let section: TodoSection
    var store: TodoStore
    var moveTargetID: String?
    var moveIsUp: Bool
    var isColumn: Bool = false
    @State private var newTaskText = ""

    private var listHeight: CGFloat {
        guard section.isExpanded else { return 0 }
        let pending = section.items.filter { !$0.done }.count
        let done = section.items.filter { $0.done }.count
        let completedBand: CGFloat = done > 0 ? 38 : 0
        return CGFloat(pending) * 34 + 44 + completedBand + 16
    }

    var body: some View {
        FolderCategoryCard(
            slot: slot,
            code: code,
            title: title,
            isExpanded: section.isExpanded,
            isColumn: isColumn,
            onToggle: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    store.toggleSection(section.id)
                }
            }
        ) {
            let pending = section.items.filter { !$0.done }
            let done = section.items.filter { $0.done }

            List {
                ForEach(pending) { item in
                    TodoRowView(
                        item: item,
                        sectionID: section.id,
                        store: store,
                        moveTargetID: moveTargetID,
                        moveIsUp: moveIsUp
                    )
                    .listRowInsets(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
                .onMove { indices, newOffset in
                    store.reorderPendingItems(sectionID: section.id, fromOffsets: indices, toOffset: newOffset)
                }

                AddTaskRow(text: $newTaskText) {
                    let trimmed = newTaskText.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    store.addItem(sectionID: section.id, text: trimmed)
                    newTaskText = ""
                }
                .listRowInsets(EdgeInsets(top: 2, leading: 4, bottom: 4, trailing: 4))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

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
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDisabled(true)
            .environment(\.defaultMinListRowHeight, 26)
            .frame(height: max(100, listHeight))
        }
    }
}

// MARK: - Yearly goals folder

private struct YearlyGoalsFolderSection: View {
    var store: TodoStore
    var isColumn: Bool = false
    @State private var isExpanded = true
    @State private var newProjectTitle = ""

    private var listHeight: CGFloat {
        guard isExpanded else { return 0 }
        let n = store.yearlyProjects.count
        let emptyHint: CGFloat = n == 0 ? 36 : 0
        return CGFloat(n) * 58 + 48 + emptyHint + 8
    }

    var body: some View {
        FolderCategoryCard(
            slot: 2,
            code: "03",
            title: "Yearly goals",
            isExpanded: isExpanded,
            isColumn: isColumn,
            onToggle: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            }
        ) {
            List {
                if store.yearlyProjects.isEmpty {
                    Text("Add long-term projects and track progress toward the year.")
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 4, trailing: 4))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }

                ForEach(store.yearlyProjects) { project in
                    YearlyProjectRow(project: project, store: store)
                        .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .frame(width: 22)

                    TextField("Add yearly goal…", text: $newProjectTitle)
                        .font(.system(.body, design: .monospaced))
                        .textFieldStyle(.plain)
                        .onSubmit {
                            let t = newProjectTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !t.isEmpty else { return }
                            store.addYearlyProject(title: t)
                            newProjectTitle = ""
                        }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDisabled(true)
            .environment(\.defaultMinListRowHeight, 28)
            .frame(height: max(96, listHeight))
        }
    }
}

struct YearlyProjectRow: View {
    let project: YearlyProject
    var store: TodoStore
    @State private var titleText: String
    @State private var rowHovered = false
    @State private var progressHover = false
    @State private var showDetail = false

    init(project: YearlyProject, store: TodoStore) {
        self.project = project
        self.store = store
        _titleText = State(initialValue: project.title)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            TextField("Project title", text: $titleText, axis: .vertical)
                .font(.system(.body, design: .monospaced).weight(.medium))
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .onChange(of: titleText) {
                    store.updateYearlyProjectTitle(id: project.id, title: titleText)
                }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 6) {
                Text("\(project.effectiveProgress)%")
                    .font(.system(.callout, design: .monospaced).weight(.medium))
                    .foregroundStyle(progressHover && project.milestones.isEmpty ? .primary : .secondary)
                    .monospacedDigit()
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(progressHover && project.milestones.isEmpty ? Color.primary.opacity(0.08) : Color.clear)
                    )

                if progressHover && project.milestones.isEmpty {
                    Slider(
                        value: Binding(
                            get: { Double(project.progress) },
                            set: { store.setYearlyProjectProgress(id: project.id, progress: Int($0.rounded())) }
                        ),
                        in: 0...100,
                        step: 1
                    )
                    .controlSize(.mini)
                    .frame(width: 112)
                }
            }
            .animation(.easeInOut(duration: 0.12), value: progressHover)
            .onHover { h in
                if project.milestones.isEmpty { progressHover = h }
            }
            .pointerStyle()

            Button {
                showDetail = true
            } label: {
                Image(systemName: "chart.pie")
                    .font(.system(size: 11))
                    .foregroundStyle(project.milestones.isEmpty ? .tertiary : .secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .pointerStyle()
            .opacity(rowHovered ? 1 : 0.3)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    store.deleteYearlyProject(id: project.id)
                }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .pointerStyle()
            .opacity(rowHovered ? 1 : 0)
        }
        .onHover { rowHovered = $0 }
        .onChange(of: project.title) { _, newValue in
            if newValue != titleText {
                titleText = newValue
            }
        }
        .sheet(isPresented: $showDetail) {
            YearlyProjectDetailView(projectID: project.id, store: store)
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
    @Binding var selection: TaskSelection?
    @State private var editText: String
    @State private var isHovered = false

    init(item: TodoItem, sectionID: String, store: TodoStore,
         moveTargetID: String? = nil, moveIsUp: Bool = false,
         selection: Binding<TaskSelection?> = .constant(nil)) {
        self.item = item
        self.sectionID = sectionID
        self.store = store
        self.moveTargetID = moveTargetID
        self.moveIsUp = moveIsUp
        self._selection = selection
        self._editText = State(initialValue: item.text)
    }

    private var isSelected: Bool {
        selection?.itemID == item.id && selection?.sectionID == sectionID
    }

    private var hasNotes: Bool {
        !item.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    store.toggleItem(sectionID: sectionID, itemID: item.id)
                }
            } label: {
                TodoCheckbox(isOn: item.done)
            }
            .buttonStyle(.plain)
            .pointerStyle()

            if item.done {
                Text(editText)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
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

            if hasNotes {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .help("Has notes")
            }

            Spacer(minLength: 4)

            HStack(spacing: 2) {
                Button {
                    openDetail()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .pointerStyle()
                .help("Show task details")

                if let target = moveTargetID {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            store.moveItem(itemID: item.id, fromSection: sectionID, toSection: target)
                        }
                    } label: {
                        Image(systemName: moveIsUp ? "calendar" : "tray.and.arrow.down")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .pointerStyle()
                    .help(moveIsUp ? "Move to Weekly" : "Move to Backlog")
                }

                Button {
                    if isSelected { selection = nil }
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
            .fixedSize()
            .opacity(isHovered || isSelected ? 1 : 0)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(rowBackground)
        )
        .onHover { isHovered = $0 }
        .onChange(of: item.text) { _, new in
            if new != editText { editText = new }
        }
    }

    private var rowBackground: Color {
        if isSelected { return Color.primary.opacity(0.08) }
        if isHovered { return Color.primary.opacity(0.04) }
        return .clear
    }

    private func openDetail() {
        selection = TaskSelection(sectionID: sectionID, itemID: item.id)
    }
}

// MARK: - Todo Checkbox

private struct TodoCheckbox: View {
    let isOn: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(isOn ? Color.primary : Color.primary.opacity(0.08))
                .frame(width: 18, height: 18)
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(Color.primary.opacity(isOn ? 0 : 0.12), lineWidth: 1)
                .frame(width: 18, height: 18)
        }
        .animation(.easeInOut(duration: 0.15), value: isOn)
    }
}

// MARK: - Task Detail Panel

private struct TaskDetailPanel: View {
    @Environment(\.colorScheme) private var colorScheme
    let sectionID: String
    let itemID: UUID
    var store: TodoStore
    var onClose: () -> Void

    @State private var titleText: String = ""
    @State private var notesText: String = ""
    @FocusState private var notesFocused: Bool

    private var item: TodoItem? {
        store.item(sectionID: sectionID, itemID: itemID)
    }

    private var sectionLabel: String {
        if sectionID == "backlog" { return "Backlog" }
        if sectionID.hasPrefix("w"), let w = Int(sectionID.dropFirst()) {
            return w == TodoStore.currentCalendarWeek ? "This week" : "Week \(w)"
        }
        return sectionID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if let item = item {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        titleRow(item: item)

                        Rectangle()
                            .fill(AppPalette.detailStroke(for: colorScheme))
                            .frame(height: 1)

                        notesSection
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 4)
                    .padding(.bottom, 22)
                }
            } else {
                VStack {
                    Spacer()
                    Text("Task no longer exists.")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear { syncLocalState() }
        .onChange(of: itemID) { _, _ in syncLocalState() }
        .onChange(of: item?.text ?? "") { _, new in
            if new != titleText { titleText = new }
        }
        .onChange(of: item?.notes ?? "") { _, new in
            if new != notesText { notesText = new }
        }
    }

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(AppPalette.accent(for: colorScheme))
                    .frame(width: 6, height: 6)
                Text(sectionLabel)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppPalette.accent(for: colorScheme))
                    .textCase(.uppercase)
                    .tracking(0.5)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(AppPalette.accentSoft(for: colorScheme))
            )
            .overlay(
                Capsule()
                    .stroke(AppPalette.accent(for: colorScheme).opacity(0.25), lineWidth: 1)
            )

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppPalette.accent(for: colorScheme).opacity(0.9))
                    .frame(width: 24, height: 24)
                    .background(
                        Circle().fill(AppPalette.accentSoft(for: colorScheme))
                    )
            }
            .buttonStyle(.plain)
            .pointerStyle()
            .help("Close details")
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private func titleRow(item: TodoItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                store.toggleItem(sectionID: sectionID, itemID: itemID)
            } label: {
                TodoCheckbox(isOn: item.done)
            }
            .buttonStyle(.plain)
            .pointerStyle()
            .padding(.top, 5)

            TextField("Task title", text: $titleText, axis: .vertical)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .textFieldStyle(.plain)
                .foregroundStyle(item.done ? .secondary : .primary)
                .lineLimit(1...6)
                .onChange(of: titleText) {
                    store.updateItemText(sectionID: sectionID, itemID: itemID, text: titleText)
                }
        }
    }

    @ViewBuilder
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Notes")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .textCase(.uppercase)
                .tracking(0.5)
                .foregroundStyle(AppPalette.accent(for: colorScheme).opacity(0.8))

            ZStack(alignment: .topLeading) {
                TextEditor(text: $notesText)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .focused($notesFocused)
                    .frame(minHeight: 280)
                    .foregroundStyle(AppPalette.accent(for: colorScheme).opacity(colorScheme == .dark ? 0.92 : 0.80))
                    .onChange(of: notesText) {
                        store.updateItemNotes(sectionID: sectionID, itemID: itemID, notes: notesText)
                    }

                if notesText.isEmpty {
                    Text("Write your notes here… Add context, links, sub-steps, anything useful.")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(AppPalette.accent(for: colorScheme).opacity(0.35))
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private func syncLocalState() {
        guard let item = item else {
            titleText = ""
            notesText = ""
            return
        }
        titleText = item.text
        notesText = item.notes
    }
}

// MARK: - Completed Group

struct CompletedGroup: View {
    let items: [TodoItem]
    let sectionID: String
    var store: TodoStore
    var moveTargetID: String? = nil
    var moveIsUp: Bool = false
    @Binding var selection: TaskSelection?
    @State private var isExpanded = false

    init(items: [TodoItem], sectionID: String, store: TodoStore,
         moveTargetID: String? = nil, moveIsUp: Bool = false,
         selection: Binding<TaskSelection?> = .constant(nil)) {
        self.items = items
        self.sectionID = sectionID
        self.store = store
        self.moveTargetID = moveTargetID
        self.moveIsUp = moveIsUp
        self._selection = selection
    }

    var body: some View {
        Group {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 10)
                    Text("\(items.count) completed")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .contentShape(Rectangle())
                .padding(.top, 14)
                .padding(.bottom, 4)
            }
            .buttonStyle(.plain)
            .pointerStyle()
            .listRowInsets(EdgeInsets(top: 2, leading: 22, bottom: 2, trailing: 22))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)

            if isExpanded {
                ForEach(items) { item in
                    TodoRowView(
                        item: item,
                        sectionID: sectionID,
                        store: store,
                        moveTargetID: moveTargetID,
                        moveIsUp: moveIsUp,
                        selection: $selection
                    )
                    .listRowInsets(EdgeInsets(top: 2, leading: 22, bottom: 2, trailing: 22))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
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
        HStack(alignment: .center, spacing: 12) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(Color.primary.opacity(0.14), style: StrokeStyle(lineWidth: 1, dash: [2.5, 2.5]))
                .frame(width: 18, height: 18)

            TextField("Add task…", text: $text)
                .font(.system(.body, design: .monospaced))
                .textFieldStyle(.plain)
                .onSubmit(onSubmit)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 6)
        .padding(.top, 4)
    }
}
