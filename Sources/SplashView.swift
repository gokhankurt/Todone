import SwiftUI

struct SplashView: View {
    var onComplete: () -> Void

    @State private var start = Date()
    @State private var completed = false

    private let totalDuration: Double = 5.0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { ctx in
            let t = ctx.date.timeIntervalSince(start)
            ZStack(alignment: .topLeading) {
                Color.black

                GeometryReader { geo in
                    AsciiArtCanvas(time: t, size: geo.size)
                }

                VStack(alignment: .leading, spacing: 0) {
                    HeaderBlock(time: t)
                        .padding(.horizontal, 44)
                        .padding(.top, 36)
                    Spacer(minLength: 0)
                    FooterBlock(time: t)
                        .padding(.horizontal, 44)
                        .padding(.bottom, 28)
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            start = Date()
            DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration) {
                if !completed {
                    completed = true
                    onComplete()
                }
            }
        }
    }
}

// MARK: - ASCII art grid

private struct AsciiArtCanvas: View {
    let time: TimeInterval
    let size: CGSize

    private static let word = "TODONE."

    // 5x7 bitmaps (X = on). The dot at the end is intentionally compact.
    private static let bitmaps: [Character: [String]] = [
        "T": [
            "XXXXX",
            "..X..",
            "..X..",
            "..X..",
            "..X..",
            "..X..",
            "..X..",
        ],
        "O": [
            ".XXX.",
            "X...X",
            "X...X",
            "X...X",
            "X...X",
            "X...X",
            ".XXX.",
        ],
        "D": [
            "XXXX.",
            "X...X",
            "X...X",
            "X...X",
            "X...X",
            "X...X",
            "XXXX.",
        ],
        "N": [
            "X...X",
            "XX..X",
            "X.X.X",
            "X.X.X",
            "X..XX",
            "X...X",
            "X...X",
        ],
        "E": [
            "XXXXX",
            "X....",
            "X....",
            "XXXX.",
            "X....",
            "X....",
            "XXXXX",
        ],
        ".": [
            ".....",
            ".....",
            ".....",
            ".....",
            ".....",
            ".XX..",
            ".XX..",
        ],
    ]

    private static let denseChars: [Character] = ["M", "K", "W", "H", "X", "N", "#", "@", "%", "$", "8", "&", "B"]
    private static let sparseChars: [Character] = [".", ".", ".", ".", ".", ".", ".", ":", "·", ",", "'", "`", "-"]

    private static let letterScale = 2
    private static let pixelRows = 7
    private static let pixelCols = 5
    private static let pixelSpacing = 1

    // Reveal timing
    private static let revealStart: Double = 0.3
    private static let revealPerRow: Double = 0.018   // time between rows
    private static let cyclePerRow: Double = 0.16     // how long chars shuffle before locking

    var body: some View {
        Canvas { ctx, canvasSize in
            let fontSize: CGFloat = 13
            let font = Font.system(size: fontSize, weight: .regular, design: .monospaced)

            // Pre-resolve all characters
            var resolvedMap: [Character: GraphicsContext.ResolvedText] = [:]
            for ch in Self.denseChars + Self.sparseChars {
                let text = Text(String(ch)).font(font).foregroundColor(.white.opacity(0.92))
                resolvedMap[ch] = ctx.resolve(text)
            }

            // Measure cell size (monospaced so all chars match)
            guard let sample = resolvedMap["M"] else { return }
            let measured = sample.measure(in: CGSize(width: CGFloat.greatestFiniteMagnitude,
                                                    height: CGFloat.greatestFiniteMagnitude))
            let cellW = measured.width
            let cellH = measured.height * 0.92

            // Reserved header + footer space
            let topInset: CGFloat = 170
            let bottomInset: CGFloat = 70
            let sideInset: CGFloat = 44

            let availW = max(10, canvasSize.width - sideInset * 2)
            let availH = max(10, canvasSize.height - topInset - bottomInset)
            let cols = max(1, Int(availW / cellW))
            let rows = max(1, Int(availH / cellH))

            let gridOriginX = sideInset
            let gridOriginY = topInset

            // Letter block geometry
            let scale = Self.letterScale
            let letterW = Self.pixelCols * scale
            let letterH = Self.pixelRows * scale
            let letterStride = letterW + Self.pixelSpacing * scale
            let wordCharCount = Self.word.count
            let totalLetterCols = wordCharCount * letterStride - Self.pixelSpacing * scale
            let letterStartCol = max(0, (cols - totalLetterCols) / 2)
            let letterStartRow = max(0, (rows - letterH) / 2)

            // Draw only rows that have reached reveal time
            for r in 0..<rows {
                let rowTime = Self.revealStart + Double(r) * Self.revealPerRow
                if time < rowTime { continue }
                let rowAge = time - rowTime
                let settled = rowAge > Self.cyclePerRow
                let shuffleFrame = settled ? 0 : Int(rowAge * 28)

                for c in 0..<cols {
                    let onState = letterOn(col: c - letterStartCol,
                                           row: r - letterStartRow)

                    // Decide a character for this cell
                    let h = hash(c &* 131 &+ r, r &* 7 &+ c, shuffleFrame)
                    let ch: Character
                    if onState == .filled {
                        let idx = Int(h * 9973) % Self.denseChars.count
                        ch = Self.denseChars[idx]
                    } else if onState == .edge {
                        // edge aura – half dense, half sparse
                        if h < 0.55 {
                            let idx = Int(h * 17021) % Self.denseChars.count
                            ch = Self.denseChars[idx]
                        } else {
                            let idx = Int(h * 4093) % Self.sparseChars.count
                            ch = Self.sparseChars[idx]
                        }
                    } else {
                        // background – mostly empty, occasional punctuation
                        if h < 0.88 { continue }
                        let idx = Int(h * 7919) % Self.sparseChars.count
                        ch = Self.sparseChars[idx]
                    }

                    guard let resolved = resolvedMap[ch] else { continue }
                    let x = gridOriginX + CGFloat(c) * cellW
                    let y = gridOriginY + CGFloat(r) * cellH

                    // During shuffle, characters appear slightly dimmer; lock bright
                    if settled {
                        ctx.draw(resolved, at: CGPoint(x: x, y: y), anchor: .topLeading)
                    } else {
                        var local = ctx
                        local.opacity = 0.75
                        local.draw(resolved, at: CGPoint(x: x, y: y), anchor: .topLeading)
                    }
                }
            }
        }
    }

    private enum CellState { case filled, edge, empty }

    private func letterOn(col: Int, row: Int) -> CellState {
        let scale = Self.letterScale
        if isOn(col: col, row: row, scale: scale) { return .filled }

        // Edge detection: one-cell aura around filled pixels
        for (dc, dr) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
            if isOn(col: col + dc, row: row + dr, scale: scale) { return .edge }
        }
        return .empty
    }

    private func isOn(col: Int, row: Int, scale: Int) -> Bool {
        guard row >= 0 else { return false }
        let letterH = Self.pixelRows * scale
        guard row < letterH else { return false }

        let letterW = Self.pixelCols * scale
        let stride = letterW + Self.pixelSpacing * scale

        let letterIdx = col / stride
        guard letterIdx >= 0, letterIdx < Self.word.count else { return false }
        let localCol = col - letterIdx * stride
        guard localCol >= 0, localCol < letterW else { return false }

        let bmpCol = localCol / scale
        let bmpRow = row / scale

        let ch = Self.word[Self.word.index(Self.word.startIndex, offsetBy: letterIdx)]
        guard let bitmap = Self.bitmaps[ch] else { return false }
        guard bmpRow < bitmap.count else { return false }
        let line = bitmap[bmpRow]
        guard bmpCol < line.count else { return false }
        return line[line.index(line.startIndex, offsetBy: bmpCol)] == "X"
    }

    private func hash(_ x: Int, _ y: Int, _ z: Int) -> Double {
        let s = sin(Double(x) * 12.9898 + Double(y) * 78.233 + Double(z) * 0.19) * 43758.5453
        return s - floor(s)
    }
}

// MARK: - Swiss 3-column header

private struct HeaderBlock: View {
    let time: TimeInterval

    private let column1: [String] = [
        "TODONE.",
        "Asynchronous Task",
        "Tracking System",
        "—",
        "An application for",
        "monospaced people",
        "who get things done."
    ]
    private let column2: [String] = [
        "Version 0.1.0",
        "Build 2026.04.19",
        "ASCII Edition",
        "—",
        "Rendered entirely",
        "in monospaced",
        "characters."
    ]
    private let column3: [String] = [
        "Todone.app",
        "SplashView.swift",
        "Loading 100%",
        "—",
        "booted 2026-04-19",
        "at 20:40:00 UTC",
        "ready to execute."
    ]

    var body: some View {
        HStack(alignment: .top, spacing: 48) {
            typingColumn(lines: column1, delay: 0.05, pace: 0.009)
            typingColumn(lines: column2, delay: 0.12, pace: 0.009)
            typingColumn(lines: column3, delay: 0.20, pace: 0.009)
            Spacer(minLength: 0)
        }
        .font(.system(size: 11, weight: .regular, design: .monospaced))
        .foregroundStyle(.white)
    }

    private func typingColumn(lines: [String], delay: Double, pace: Double) -> some View {
        let totalChars = lines.map(\.count).reduce(0, +)
        let elapsed = max(0, time - delay)
        let charsShown = Int(elapsed / pace)

        var remaining = min(charsShown, totalChars)
        var prefixes: [String] = []
        for line in lines {
            if remaining >= line.count {
                prefixes.append(line)
                remaining -= line.count
            } else if remaining > 0 {
                prefixes.append(String(line.prefix(remaining)))
                remaining = 0
            } else {
                prefixes.append("")
            }
        }

        return VStack(alignment: .leading, spacing: 2) {
            ForEach(0..<lines.count, id: \.self) { i in
                Text(prefixes[i].isEmpty ? " " : prefixes[i])
                    .frame(height: 14, alignment: .leading)
            }
        }
        .frame(width: 180, alignment: .topLeading)
    }
}

// MARK: - Footer

private struct FooterBlock: View {
    let time: TimeInterval

    private let lines: [String] = [
        "[ TODO ]   [ NOTES ]   [ TAGS ]   [ DONE ]   ///   press any key to continue_"
    ]

    var body: some View {
        let elapsed = max(0, time - 1.5)
        let charsShown = min(lines[0].count, Int(elapsed / 0.012))
        let shown = String(lines[0].prefix(charsShown))
        let cursor = Int(time * 2.2) % 2 == 0 ? "▍" : " "

        HStack(spacing: 0) {
            Text(shown)
            Text(cursor)
        }
        .font(.system(size: 10, weight: .regular, design: .monospaced))
        .foregroundStyle(.white.opacity(0.7))
    }
}
