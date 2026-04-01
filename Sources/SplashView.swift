import SwiftUI

struct SplashView: View {
    var onComplete: () -> Void

    private let title = Array("TODONE.")
    private let tagline = Array("Because done feels good.")
    private let glyphs = Array("@#$%&!?░▒▓█/\\|<>^~*+=-01XKWM")

    @State private var chars: [String]
    @State private var locked = 0
    @State private var taglineLen = 0

    init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
        _chars = State(initialValue: Array(repeating: " ", count: 7))
    }

    var body: some View {
        ZStack {
            Color.black

            ScanlineOverlay()
                .opacity(0.5)
                .allowsHitTesting(false)

            VStack(spacing: 24) {
                HStack(spacing: 0) {
                    ForEach(0..<title.count, id: \.self) { i in
                        Text(chars[i])
                            .font(.system(size: 52, weight: .heavy, design: .monospaced))
                            .foregroundStyle(.white)
                            .frame(width: 40)
                    }
                }

                Text(taglineLen > 0 ? String(tagline.prefix(taglineLen)) : " ")
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(height: 20)
            }
        }
        .ignoresSafeArea()
        .onAppear(perform: runAnimation)
    }

    private func runAnimation() {
        for i in 0..<title.count {
            let t = 0.3 + Double(i) * 0.14

            for s in 0..<6 {
                DispatchQueue.main.asyncAfter(deadline: .now() + t + Double(s) * 0.04) {
                    guard locked <= i else { return }
                    chars[i] = String(glyphs.randomElement()!)
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + t + 0.25) {
                withAnimation(.easeOut(duration: 0.06)) {
                    chars[i] = String(title[i])
                    locked = i + 1
                }
            }
        }

        let phase2 = 0.3 + Double(title.count) * 0.14 + 0.45
        for i in 1...tagline.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + phase2 + Double(i) * 0.03) {
                taglineLen = i
            }
        }

        let total = phase2 + Double(tagline.count) * 0.03 + 0.7
        DispatchQueue.main.asyncAfter(deadline: .now() + total) {
            onComplete()
        }
    }
}

// MARK: - CRT scanline effect

private struct ScanlineOverlay: View {
    var body: some View {
        Canvas { context, size in
            for y in stride(from: 0.0, through: size.height, by: 4) {
                context.fill(
                    Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                    with: .color(.white.opacity(0.03))
                )
            }
        }
    }
}
