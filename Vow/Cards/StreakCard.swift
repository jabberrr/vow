import SwiftUI

private enum StreakPipKind: Equatable {
    case kept
    case missed
    case today(sealed: Bool)
    case empty
}

struct StreakCard: View {
    let streak: Int
    let best: Int
    let history: [DayOutcome]
    let sealedToday: Bool

    private static let slots: Int = 14

    /// Oldest -> newest, left -> right. Last 13 marks + today's pip, padded with empties.
    private var pips: [StreakPipKind] {
        let recent: [DayOutcome] = Array(history.suffix(StreakCard.slots - 1))
        var result: [StreakPipKind] = []
        for mark in recent {
            result.append(mark == .kept ? StreakPipKind.kept : StreakPipKind.missed)
        }
        result.append(StreakPipKind.today(sealed: sealedToday))
        while result.count < StreakCard.slots {
            result.append(StreakPipKind.empty)
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            top
            pipRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var top: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Streak")
                    .eyebrow()
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(streak)")
                        .font(Theme.mono(44, .bold))
                        .foregroundStyle(Color.white)
                    Text("day streak")
                        .font(Theme.mono(13, .medium))
                        .foregroundStyle(Color.white.opacity(0.6))
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                Text("Best")
                    .eyebrow()
                Text("\(best)")
                    .font(Theme.mono(20, .semibold))
                    .foregroundStyle(Theme.lime)
            }
        }
    }

    private var pipRow: some View {
        let items: [StreakPipKind] = pips
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                ForEach(0..<items.count, id: \.self) { index in
                    StreakPip(kind: items[index])
                        .frame(maxWidth: .infinity)
                }
            }
            Text("Last 14 days")
                .font(Theme.mono(10, .medium))
                .foregroundStyle(Color.white.opacity(0.35))
        }
    }
}

private struct StreakPip: View {
    let kind: StreakPipKind

    private let size: CGFloat = 13

    var body: some View {
        pip
            .frame(width: size, height: size)
    }

    @ViewBuilder
    private var pip: some View {
        switch kind {
        case .kept:
            Circle()
                .fill(Theme.lime)
        case .missed:
            Circle()
                .strokeBorder(Theme.pink.opacity(0.75), lineWidth: 1.5)
                .background(Circle().fill(Theme.pink.opacity(0.12)))
        case .today(let sealed):
            ZStack {
                Circle()
                    .strokeBorder(Theme.cyan, lineWidth: 1.5)
                Circle()
                    .fill(Theme.lime)
                    .padding(3.5)
                    .opacity(sealed ? 1 : 0)
            }
        case .empty:
            Circle()
                .fill(Color.white.opacity(0.08))
        }
    }
}
