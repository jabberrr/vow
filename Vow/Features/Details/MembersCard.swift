import SwiftUI

/// "Members": everyone in `summary.standings` order (you first, then by name), neutral colours.
/// Only your own net is coloured; friends' nets stay grey, and streaks carry the comparison.
struct MembersCard: View {
    let summary: GroupSummary
    let viewerID: String
    /// Same rule as ProgressCard.todayLit, for your own row.
    let viewerLit: Bool
    let onSelect: (String) -> Void

    init(summary: GroupSummary, viewerID: String, viewerLit: Bool, onSelect: @escaping (String) -> Void) {
        self.summary = summary
        self.viewerID = viewerID
        self.viewerLit = viewerLit
        self.onSelect = onSelect
    }

    var body: some View {
        let theme: DailyTheme = Overview.theme(summary)
        return VStack(alignment: .leading, spacing: 0) {
            SectionTitle("Members", trailing: PointsText.string(summary.totalForfeited) + " forfeited")
            card(theme)
        }
    }

    private func card(_ theme: DailyTheme) -> some View {
        VStack(spacing: 0) {
            ForEach(summary.standings) { row in
                if row.userID != summary.standings.first?.userID {
                    Hairline(leading: 62)
                }
                MemberCardRow(row: row,
                              theme: theme,
                              isViewer: row.userID == viewerID,
                              viewerLit: viewerLit,
                              onSelect: onSelect)
            }
        }
        .frame(maxWidth: .infinity)
        .cardSurface()
    }
}

/// Sphere, name over short vow; streak over net on the right. A button that opens the member sheet.
private struct MemberCardRow: View {
    let row: MemberStanding
    let theme: DailyTheme
    let isViewer: Bool
    let viewerLit: Bool
    let onSelect: (String) -> Void

    /// Yours follows `viewerLit` (the reward beats); everyone else's follows the store.
    private var lit: Bool {
        isViewer ? (row.checkedInToday && viewerLit) : row.checkedInToday
    }

    /// Your streak minus one while your check-in waits for the social beat.
    private var streak: Int {
        if isViewer && row.checkedInToday && !viewerLit {
            return max(0, row.streak - 1)
        }
        return row.streak
    }

    private var name: String {
        isViewer ? "You" : MemberText.name(row.displayName)
    }

    private var shortVow: String {
        VowFormat.short(row.vow)
    }

    private var status: String {
        if lit {
            return "kept today"
        }
        return isViewer ? "your turn" : "not yet"
    }

    /// "Maya, Swim 40 lengths, kept today, 21-day streak, plus 6.25 points"
    private var spoken: String {
        var parts: [String] = [name]
        if !shortVow.isEmpty {
            parts.append(shortVow)
        }
        parts.append(status)
        parts.append(streak == 1 ? "1-day streak" : "\(streak)-day streak")
        parts.append(MemberText.netSpoken(row.net))
        return parts.joined(separator: ", ")
    }

    var body: some View {
        Button {
            onSelect(row.userID)
        } label: {
            HStack(spacing: 14) {
                sphere
                nameColumn
                Spacer(minLength: Gap.s)
                trailingColumn
            }
            .padding(.horizontal, Gap.l)
            .padding(.vertical, 10)
            .frame(minHeight: 60)
        }
        .buttonStyle(RowPressStyle())
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityLabel(spoken)
    }

    private var sphere: some View {
        Sphere(theme: theme,
               state: lit ? .lit : .unlit,
               size: 32,
               initial: NameFormat.initial(row.displayName),
               glows: false)
            .animation(Anim.light, value: lit)
    }

    private var nameColumn: some View {
        VStack(alignment: .leading, spacing: Gap.xxs) {
            Text(name)
                .font(isViewer ? Fonts.subheadlineSemibold : Fonts.subheadlineMedium)
                .foregroundStyle(Ink.text)
                .lineLimit(1)
            if !shortVow.isEmpty {
                Text(shortVow)
                    .font(Fonts.footnote)
                    .foregroundStyle(Ink.text2)
                    .lineLimit(1)
            }
        }
    }

    /// Kept whole: the name and vow truncate first.
    private var trailingColumn: some View {
        VStack(alignment: .trailing, spacing: Gap.xxs) {
            FlameStreak(count: streak, size: .small)
            Text(MemberText.net(row.net))
                .font(isViewer ? Fonts.footnoteSemibold : Fonts.footnote)
                .monospacedDigit()
                .foregroundStyle(isViewer ? Ink.points(row.net) : Ink.text2)
                .lineLimit(1)
        }
        .layoutPriority(1)
    }
}

/// A member's name and net for display. Nets read like balances: signed unless zero ("+4.5 pts", "0 pts").
enum MemberText {
    /// Trimmed display name; empty -> "Someone" (as the ledger says).
    static func name(_ displayName: String) -> String {
        let trimmed: String = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Someone" : trimmed
    }

    /// "+4.5 pts", "−2 pts", "0 pts".
    static func net(_ value: Double) -> String {
        let parts: (number: String, unit: String) = PointsText.balanceParts(value)
        return parts.unit.isEmpty ? parts.number : parts.number + " " + parts.unit
    }

    /// "+6.25" (a stat whose label carries the unit).
    static func netNumber(_ value: Double) -> String {
        PointsText.balanceParts(value).number
    }

    /// "plus 6.25 points", "0 points".
    static func netSpoken(_ value: Double) -> String {
        let isZero: Bool = (abs(value) * 100).rounded() == 0
        return PointsText.spoken(value, signed: !isZero)
    }
}
