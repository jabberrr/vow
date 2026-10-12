import SwiftUI

/// "Points" card: stats (your net, forfeited, daily stake), the carry callout, a preview of the last
/// settled day and the link to all activity.
struct PointsSection: View {
    let id: GroupID
    let group: GroupInfo
    let summary: GroupSummary
    let isMember: Bool
    /// The viewer owns this test group and sees the test bar.
    let canAdvance: Bool

    private var viewerNet: Double {
        summary.viewer?.net ?? 0
    }

    /// The callout already says what carried over, so the preview drops the carry line meanwhile
    /// (ActivityView keeps it).
    private var previewSource: [LedgerLine] {
        guard summary.pot > 0 else { return summary.ledger }
        return summary.ledger.filter { $0.kind != .carry }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Points")
            card(LedgerFormat.preview(previewSource, group: group, currentDay: summary.currentDay))
        }
    }

    private func card(_ preview: ActivityDay?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            stats
            if summary.pot > 0 {
                InsetDivider()
                carryCallout
            }
            InsetDivider()
            activity(preview)
            if summary.ledger.count > (preview?.lines.count ?? 0) {
                InsetDivider()
                allActivityLink
            }
        }
        .card()
    }

    // MARK: - Stats

    private var stats: some View {
        HStack(alignment: .top, spacing: 12) {
            if isMember {
                netStat
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            forfeitedStat
                .frame(maxWidth: .infinity, alignment: .leading)
            stakeStat
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private var netStat: some View {
        let net: (number: String, unit: String) = PointsText.parts(viewerNet, signed: true)
        return StatView(number: net.number, unit: net.unit, label: "Your net", tint: Palette.points(viewerNet))
    }

    private var forfeitedStat: some View {
        let forfeited: (number: String, unit: String) = PointsText.parts(summary.totalForfeited)
        return StatView(number: forfeited.number, unit: forfeited.unit, label: "Forfeited")
    }

    private var stakeStat: some View {
        StatView(number: "\(group.stake)", unit: group.stake == 1 ? "pt" : "pts", label: "Daily stake")
    }

    // MARK: - Carry

    private var carryCallout: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.uturn.right")
                .font(Typeface.subheadlineSemibold)
                .accessibilityHidden(true)
            Text("\(PointsText.string(summary.pot)) carried over to today")
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(Typeface.subheadlineMedium)
        .foregroundStyle(Palette.warn)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.warn.opacity(0.08))
    }

    // MARK: - Activity

    @ViewBuilder
    private func activity(_ preview: ActivityDay?) -> some View {
        if let day = preview {
            ActivityRows(day: day)
        } else {
            Text(emptyText)
                .font(Typeface.subheadline)
                .foregroundStyle(Palette.text3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var emptyText: String {
        if !group.isTest {
            return "Nothing yet. Days settle at midnight."
        }
        return canAdvance ? "Nothing yet. Tap Next day to settle today." : "Nothing yet. The owner moves the days."
    }

    private var allActivityLink: some View {
        NavigationLink {
            ActivityView(id: id)
        } label: {
            HStack {
                Text("All activity")
                    .font(Typeface.body)
                    .foregroundStyle(Palette.text)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.text3)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
        }
        .buttonStyle(RowStyle())
    }
}
