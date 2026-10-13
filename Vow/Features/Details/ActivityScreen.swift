import SwiftUI

/// Pushed from the details: every ledger line by day, newest first, ranked within each day.
/// Reads the store live.
struct ActivityScreen: View {
    let id: GroupID

    @Environment(AppStore.self) private var store

    init(id: GroupID) {
        self.id = id
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            content
                .padding(.horizontal, Gap.gutter)
                .padding(.top, Gap.s)
                .padding(.bottom, Gap.huge)
        }
        .vowBackground()
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarRole(.editor)
        .toolbar(.visible, for: .navigationBar)
    }

    @ViewBuilder
    private var content: some View {
        if let summary: GroupSummary = store.summary(for: id), let group: GroupInfo = store.snapshots[id]?.group {
            dayList(LedgerFormat.days(summary.ledger, group: group, currentDay: summary.currentDay))
        }
    }

    private func dayList(_ days: [ActivityDay]) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            ForEach(days) { day in
                daySection(day)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func daySection(_ day: ActivityDay) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(day.title)
                .font(Fonts.subheadlineSemibold)
                .foregroundStyle(Ink.text2)
                .padding(.horizontal, Gap.xs)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(day.lines) { line in
                    LedgerRow(line: line)
                }
            }
            .padding(.vertical, Gap.xs)
            .frame(maxWidth: .infinity)
            .cardSurface()
        }
    }
}
