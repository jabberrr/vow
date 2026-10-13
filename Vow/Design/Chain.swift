import SwiftUI

/// This cycle's 30 days: 2 rows of 15 beads.
struct ChainGrid: View {
    let beads: [ChainBead]

    init(beads: [ChainBead]) {
        self.beads = beads
    }

    var body: some View {
        VStack(spacing: 12) {
            row(0)
            row(15)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(CycleChain.summaryText(beads))
    }

    private func row(_ start: Int) -> some View {
        HStack(spacing: 0) {
            ForEach(start..<(start + 15), id: \.self) { index in
                bead(index)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func bead(_ index: Int) -> some View {
        if index < beads.count {
            beadView(beads[index])
        } else {
            Color.clear.frame(width: 16, height: 16)
        }
    }

    @ViewBuilder
    private func beadView(_ bead: ChainBead) -> some View {
        switch bead {
        case .kept(let day):
            Sphere(theme: ChainGrid.theme(day), state: .lit, size: 16, glows: false)
        case .missed(let day):
            Sphere(theme: ChainGrid.theme(day), state: .missed, size: 16, glows: false)
        case .today(let day, let kept):
            if kept {
                Sphere(theme: ChainGrid.theme(day), state: .lit, size: 16, glows: false)
                    .overlay(Circle().strokeBorder(Ink.text, lineWidth: 1.5).frame(width: 22, height: 22))
            } else {
                Sphere(theme: ChainGrid.theme(day), state: .open, size: 16, glows: false)
            }
        case .upcoming:
            Circle()
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                .frame(width: 16, height: 16)
        case .notJoined:
            Circle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 4, height: 4)
                .frame(width: 16, height: 16)
        }
    }

    /// The orb colours of absolute group day `day`.
    static func theme(_ day: Int) -> DailyTheme {
        DailyTheme.make(cycle: day / 30 + 1, day: day % 30 + 1)
    }
}
