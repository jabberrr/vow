import SwiftUI

/// The quiet line above the vow, shown only when it has something to say: the Test tag, "Day 4 of 21"
/// (only with an end date; an open-ended vow counts nothing but its streak) and the Pot tag when
/// yesterday's pot carried over. A finished vow says when it ended instead: "Finished · Oct 30".
/// With nothing to say it renders nothing, so the stage below keeps its place.
struct StageMeta: View {
    let group: GroupInfo
    let summary: GroupSummary
    let now: Date

    init(group: GroupInfo, summary: GroupSummary, now: Date) {
        self.group = group
        self.summary = summary
        self.now = now
    }

    var body: some View {
        if summary.isFinished {
            finishedLine
        } else if hasItems {
            itemsLine
        }
    }

    // MARK: - Items

    private var dayText: String? {
        guard let counter: (day: Int, total: Int) = EndDate.dayCounter(summary) else { return nil }
        return "Day \(counter.day) of \(counter.total)"
    }

    private var hasPot: Bool {
        (summary.pot * 100).rounded() > 0
    }

    private var hasItems: Bool {
        group.isTest || dayText != nil || hasPot
    }

    /// One line when it fits; otherwise a centred column, so nothing is clipped at large sizes.
    private var itemsLine: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 7) {
                items
            }
            VStack(spacing: Gap.xs) {
                items
            }
        }
        .font(Fonts.footnoteMedium)
        .foregroundStyle(Ink.text2)
        .padding(.horizontal, Gap.gutter)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var items: some View {
        if group.isTest {
            Tag("Test")
        }
        if let text: String = dayText {
            Text(text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        if hasPot {
            Tag("Pot " + PointsText.string(summary.pot), systemImage: "arrow.uturn.forward", style: .gain)
        }
    }

    // MARK: - Finished

    /// "Finished · Oct 30"; a test group names its final day by number ("Finished · Day 30").
    private var finishedText: String {
        guard let day: String = DayText.finalDay(group, now: now) else { return "Finished" }
        return "Finished · " + day
    }

    private var finishedLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: Gap.s) {
            Image(systemName: "flag.checkered")
                .font(.system(size: 13, weight: .semibold))
                .accessibilityHidden(true)
            Text(finishedText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(Fonts.footnoteMedium)
        .foregroundStyle(Ink.text2)
        .padding(.horizontal, Gap.gutter)
        .accessibilityElement(children: .combine)
    }
}
