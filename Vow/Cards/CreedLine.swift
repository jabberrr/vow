import SwiftUI

/// Fixed-height line above the orb. Its height never changes between sealed / unsealed.
struct CreedLine: View {
    let glyphNumber: Int
    let creed: String
    let sealed: Bool

    private var eyebrowText: String {
        "Today's glyph · No. " + String(format: "%02d", glyphNumber)
    }

    var body: some View {
        VStack(spacing: 8) {
            Text(eyebrowText)
                .eyebrow()
                .lineLimit(1)
            line
        }
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .padding(.horizontal, 8)
    }

    private var line: some View {
        ZStack {
            Text(creed)
                .font(Theme.display(17, .medium))
                .foregroundStyle(Color.white.opacity(0.85))
                .opacity(sealed ? 0 : 1)
            Text("Checked in.")
                .font(Theme.display(17, .semibold))
                .foregroundStyle(Theme.lime)
                .opacity(sealed ? 1 : 0)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(height: 24)
        .animation(.easeInOut(duration: 0.35), value: sealed)
    }
}
