import SwiftUI

/// "Members" on the Group page: everyone in `summary.standings` order (you first, then by name) with
/// today's status, streak and net, then Invite. Only your own net is coloured; friends' nets stay grey,
/// streaks carry the comparison, and a friend who hasn't checked in yet is "not yet", never "missed".
struct GroupMembersCard: View {
    let summary: GroupSummary
    let viewerID: String
    /// The last 4 h of a real group's day: your open ring turns flame.
    let atRisk: Bool
    /// Members of an unfinished group: Invite closes the list it adds to.
    let canInvite: Bool
    let onSelect: (String) -> Void
    let onInvite: () -> Void

    init(summary: GroupSummary,
         viewerID: String,
         atRisk: Bool,
         canInvite: Bool,
         onSelect: @escaping (String) -> Void,
         onInvite: @escaping () -> Void) {
        self.summary = summary
        self.viewerID = viewerID
        self.atRisk = atRisk
        self.canInvite = canInvite
        self.onSelect = onSelect
        self.onInvite = onInvite
    }

    /// Home's strip count: "2 of 5 kept today" / "Everyone kept today". None once the vow is finished,
    /// since nobody has a today then.
    private var keptNote: String? {
        guard !summary.isFinished else { return nil }
        let kept: Int = Digest.keptCount(summary.standings)
        let total: Int = summary.standings.count
        if total >= 2 && kept == total {
            return "Everyone kept today"
        }
        return "\(kept) of \(total) kept today"
    }

    var body: some View {
        let theme: DailyTheme = Overview.theme(summary)
        return VStack(alignment: .leading, spacing: 0) {
            SectionTitle("Members", trailing: keptNote)
            card(theme)
        }
    }

    private func card(_ theme: DailyTheme) -> some View {
        VStack(spacing: 0) {
            ForEach(summary.standings) { (row: MemberStanding) in
                if row.userID != summary.standings.first?.userID {
                    Hairline(leading: 62)
                }
                GroupMemberRow(row: row,
                               theme: theme,
                               isViewer: row.userID == viewerID,
                               isFinished: summary.isFinished,
                               atRisk: atRisk,
                               onSelect: onSelect)
            }
            if canInvite {
                if !summary.standings.isEmpty {
                    Hairline(leading: 62)
                }
                GroupInviteRow(action: onInvite)
            }
        }
        .frame(maxWidth: .infinity)
        .cardSurface()
    }
}

/// Sphere, name over short vow; streak over net on the right. A button that opens the member sheet.
/// The Group page is never on screen during a check-in, so every value is the store's.
private struct GroupMemberRow: View {
    let row: MemberStanding
    let theme: DailyTheme
    let isViewer: Bool
    let isFinished: Bool
    let atRisk: Bool
    let onSelect: (String) -> Void

    init(row: MemberStanding,
         theme: DailyTheme,
         isViewer: Bool,
         isFinished: Bool,
         atRisk: Bool,
         onSelect: @escaping (String) -> Void) {
        self.row = row
        self.theme = theme
        self.isViewer = isViewer
        self.isFinished = isFinished
        self.atRisk = atRisk
        self.onSelect = onSelect
    }

    /// Lit = kept today; your open vow is ringed. Nobody is lit or ringed once the vow is finished.
    private var state: SphereState {
        if isFinished {
            return .unlit
        }
        if row.checkedInToday {
            return .lit
        }
        return isViewer ? .open : .unlit
    }

    private var name: String {
        isViewer ? "You" : MemberText.name(row.displayName)
    }

    private var shortVow: String {
        VowFormat.short(row.vow)
    }

    /// nil once the vow is finished: there is no today to report.
    private var status: String? {
        if isFinished {
            return nil
        }
        if row.checkedInToday {
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
        if let today: String = status {
            parts.append(today)
        }
        parts.append(row.streak == 1 ? "1-day streak" : "\(row.streak)-day streak")
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
               state: state,
               size: 32,
               initial: NameFormat.initial(row.displayName),
               ringColor: atRisk ? Ink.flame : Ink.text,
               glows: false)
            .animation(Anim.light, value: state)
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
            FlameStreak(count: row.streak, size: .small)
            Text(MemberText.net(row.net))
                .font(isViewer ? Fonts.footnoteSemibold : Fonts.footnote)
                .monospacedDigit()
                .foregroundStyle(isViewer ? Ink.points(row.net) : Ink.text2)
                .lineLimit(1)
        }
        .layoutPriority(1)
    }
}

/// Invite as an empty seat (a dashed circle) at the end of the list it adds to.
private struct GroupInviteRow: View {
    let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                seat
                Text("Invite")
                    .font(Fonts.subheadlineSemibold)
                    .foregroundStyle(Ink.text)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Gap.l)
            .padding(.vertical, 10)
            .frame(minHeight: 56)
        }
        .buttonStyle(RowPressStyle())
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityLabel("Invite")
    }

    private var seat: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.white.opacity(0.28), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
            Image(systemName: "plus")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Ink.text)
        }
        .frame(width: 32, height: 32)
        .accessibilityHidden(true)
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
