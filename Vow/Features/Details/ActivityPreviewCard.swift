import SwiftUI

/// "Activity": the latest settled day (up to 5 ranked lines) and the way into ActivityScreen.
struct ActivityPreviewCard: View {
    let group: GroupInfo
    let summary: GroupSummary
    /// You own this test group and testing mode is on (empty-state wording).
    let canAdvance: Bool
    let onShowAll: () -> Void

    init(group: GroupInfo, summary: GroupSummary, canAdvance: Bool, onShowAll: @escaping () -> Void) {
        self.group = group
        self.summary = summary
        self.canAdvance = canAdvance
        self.onShowAll = onShowAll
    }

    /// The pot tag in the meta line already says what carried over, so the preview drops the carry
    /// line meanwhile (ActivityScreen keeps it).
    private var previewSource: [LedgerLine] {
        guard summary.pot > 0 else { return summary.ledger }
        return summary.ledger.filter { $0.kind != .carry }
    }

    var body: some View {
        let preview: ActivityDay? = LedgerFormat.preview(previewSource, group: group, currentDay: summary.currentDay)
        return VStack(alignment: .leading, spacing: 0) {
            SectionTitle("Activity")
            card(preview)
        }
    }

    private func card(_ preview: ActivityDay?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let day = preview {
                dayBlock(day)
            } else {
                emptyText
            }
            if summary.ledger.count > (preview?.lines.count ?? 0) {
                Hairline(leading: 0)
                allActivityRow
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func dayBlock(_ day: ActivityDay) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(day.title)
                .font(Fonts.footnoteSemibold)
                .foregroundStyle(Ink.text3)
                .padding(.top, Gap.l)
                .padding(.horizontal, Gap.l)
                .padding(.bottom, Gap.xxs)
                .accessibilityAddTraits(.isHeader)
            ForEach(day.lines) { line in
                LedgerRow(line: line)
            }
        }
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyText: some View {
        Text(emptyMessage)
            .font(Fonts.subheadline)
            .foregroundStyle(Ink.text3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(Gap.l)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyMessage: String {
        if !group.isTest {
            return "Nothing settled yet. Days close at midnight."
        }
        return canAdvance ? "Nothing settled yet. Tap Next day to close today." : "Nothing settled yet. The owner moves the days."
    }

    private var allActivityRow: some View {
        Button(action: onShowAll) {
            HStack(spacing: Gap.s) {
                Text("All activity")
                    .font(Fonts.body)
                    .foregroundStyle(Ink.text)
                Spacer(minLength: Gap.s)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Ink.text3)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Gap.l)
            .frame(minHeight: 50)
        }
        .buttonStyle(RowPressStyle())
    }
}
