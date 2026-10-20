import SwiftUI

/// The streak's numbers under the flame. While the vow runs: the next milestone (target, a bar from the
/// previous one, days to go) over your best streak. Once it is finished there is no next milestone, so
/// days kept ("12 of 14") take its place.
struct StreakStatsCard: View {
    let viewer: MemberStanding
    let isFinished: Bool

    init(viewer: MemberStanding, isFinished: Bool) {
        self.viewer = viewer
        self.isFinished = isFinished
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isFinished {
                StatRow(title: "Days kept", value: "\(Digest.daysKept(viewer)) of \(viewer.history.count)")
            } else {
                NextMilestone(streak: viewer.streak)
            }
            bleedLine
                .padding(.top, 14)
                .padding(.bottom, Gap.m)
            StatRow(title: "Best streak", value: DayText.count(viewer.bestStreak))
        }
        .padding(Gap.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    /// Full-bleed hairline across the card's side padding.
    private var bleedLine: some View {
        Hairline(leading: 0)
            .padding(.horizontal, -Gap.l)
    }
}

/// "Next milestone": the target, a bar from the previous milestone, and how many days to go.
private struct NextMilestone: View {
    let streak: Int

    private var previous: Int {
        StreakMilestones.previous(atOrBelow: streak)
    }

    private var next: Int {
        StreakMilestones.next(after: streak)
    }

    private var toGoText: String {
        "\(next - streak) to go"
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
        .accessibilityValue(DayText.count(next) + ", " + toGoText)
    }

    /// Side by side; stacked when it doesn't fit (accessibility sizes).
    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: Gap.s) {
                title
                Spacer(minLength: Gap.s)
                target
            }
            VStack(alignment: .leading, spacing: Gap.xxs) {
                title
                target
            }
        }
    }

    private var title: some View {
        Text("Next milestone")
            .font(Fonts.subheadlineMedium)
            .foregroundStyle(Ink.text)
    }

    private var target: some View {
        HStack(spacing: Gap.xs) {
            Image(systemName: "flame.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Ink.flameGradient)
            Text(DayText.count(next))
                .font(Fonts.subheadlineSemibold)
                .monospacedDigit()
                .foregroundStyle(Ink.flame)
        }
    }

    private var bar: some View {
        Capsule()
            .fill(Color.white.opacity(0.08))
            .frame(height: 6)
            .overlay(alignment: .leading) {
                GeometryReader { (proxy: GeometryProxy) in
                    Capsule()
                        .fill(Ink.milestoneGradient)
                        .frame(width: proxy.size.width * CGFloat(fraction), height: 6)
                }
            }
            .clipShape(Capsule())
    }

    /// The previous milestone under the bar's start (none below the first), days to go under its end.
    private var footer: some View {
        HStack(alignment: .firstTextBaseline, spacing: Gap.s) {
            if previous > 0 {
                Text(DayText.count(previous))
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

/// "Best streak · 11 days": title on the left, value on the right; stacked when it doesn't fit.
private struct StatRow: View {
    let title: String
    let value: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: Gap.s) {
                titleText
                Spacer(minLength: Gap.s)
                valueText
            }
            VStack(alignment: .leading, spacing: Gap.xxs) {
                titleText
                valueText
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var titleText: some View {
        Text(title)
            .font(Fonts.subheadlineMedium)
            .foregroundStyle(Ink.text)
    }

    private var valueText: some View {
        Text(value)
            .font(Fonts.subheadlineMedium)
            .monospacedDigit()
            .foregroundStyle(Ink.text2)
    }
}
