import SwiftUI

/// "Cycle N": the chain, next milestone, best streak. While `todayLit` is false and you have
/// already checked in (the reward beats), it shows today's bead open and the streak minus one.
struct ProgressCard: View {
    let viewer: MemberStanding
    let summary: GroupSummary
    let todayLit: Bool

    init(viewer: MemberStanding, summary: GroupSummary, todayLit: Bool) {
        self.viewer = viewer
        self.summary = summary
        self.todayLit = todayLit
    }

    /// Checked in, but the social beat hasn't lit today yet.
    private var held: Bool {
        viewer.checkedInToday && !todayLit
    }

    /// The shown streak `s` (§6.10).
    private var shownStreak: Int {
        held ? max(0, viewer.streak - 1) : viewer.streak
    }

    /// Best before today's check-in while held: the longest closed run, or the shown streak.
    private var shownBest: Int {
        guard held else { return viewer.bestStreak }
        var best: Int = 0
        var run: Int = 0
        for outcome in viewer.history {
            if outcome == .kept {
                run += 1
                best = max(best, run)
            } else {
                run = 0
            }
        }
        return max(best, shownStreak)
    }

    private var beads: [ChainBead] {
        CycleChain.beads(history: viewer.history,
                         currentDay: summary.currentDay,
                         checkedInToday: viewer.checkedInToday && todayLit)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle("Cycle \(summary.cycle)")
            card
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            ChainGrid(beads: beads)
            bleedLine
                .padding(.top, 18)
                .padding(.bottom, 14)
            MilestoneBlock(streak: shownStreak)
            bleedLine
                .padding(.top, 14)
                .padding(.bottom, Gap.m)
            bestRow
        }
        .padding(.top, 18)
        .padding(.horizontal, Gap.l)
        .padding(.bottom, Gap.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    /// Full-bleed hairline across the card's side padding.
    private var bleedLine: some View {
        Hairline(leading: 0)
            .padding(.horizontal, -Gap.l)
    }

    private var bestRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: Gap.s) {
            Text("Best streak")
                .font(Fonts.subheadlineMedium)
                .foregroundStyle(Ink.text)
            Spacer(minLength: Gap.s)
            Text(ProgressCard.days(shownBest))
                .font(Fonts.subheadlineMedium)
                .monospacedDigit()
                .foregroundStyle(Ink.text2)
        }
        .accessibilityElement(children: .combine)
    }

    /// "1 day" / "21 days".
    static func days(_ n: Int) -> String {
        n == 1 ? "1 day" : "\(n) days"
    }
}

/// "Next milestone": the target, a bar from the previous milestone, and how many days to go.
private struct MilestoneBlock: View {
    let streak: Int

    private var previous: Int {
        StreakMilestones.previous(atOrBelow: streak)
    }

    private var next: Int {
        StreakMilestones.next(after: streak)
    }

    private var toGo: Int {
        next - streak
    }

    private var toGoText: String {
        "\(toGo) to go"
    }

    private var fraction: Double {
        let span: Int = next - previous
        guard span > 0 else { return 0 }
        let value: Double = Double(streak - previous) / Double(span)
        return min(1, max(0, value))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            bar
                .padding(.top, 10)
            footer
                .padding(.top, Gap.s)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Next milestone")
        .accessibilityValue(ProgressCard.days(next) + ", " + toGoText)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Gap.s) {
            Text("Next milestone")
                .font(Fonts.subheadlineMedium)
                .foregroundStyle(Ink.text)
            Spacer(minLength: Gap.s)
            HStack(spacing: Gap.xs) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Ink.flameGradient)
                Text(ProgressCard.days(next))
                    .font(Fonts.subheadlineSemibold)
                    .monospacedDigit()
                    .foregroundStyle(Ink.flame)
            }
        }
    }

    private var bar: some View {
        Capsule()
            .fill(Color.white.opacity(0.08))
            .frame(height: 6)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(Ink.milestoneGradient)
                        .frame(width: proxy.size.width * CGFloat(fraction), height: 6)
                }
            }
            .clipShape(Capsule())
    }

    private var footer: some View {
        HStack(alignment: .firstTextBaseline, spacing: Gap.s) {
            if previous > 0 {
                Text(ProgressCard.days(previous))
                    .font(Fonts.footnote)
                    .monospacedDigit()
                    .foregroundStyle(Ink.text3)
            }
            Spacer(minLength: Gap.s)
            Text(toGoText)
                .font(Fonts.footnote)
                .monospacedDigit()
                .foregroundStyle(Ink.text2)
        }
    }
}
