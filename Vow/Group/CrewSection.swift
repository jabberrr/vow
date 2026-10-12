import SwiftUI

/// "Crew" header with today's count, then one card of members (viewer first). When you are alone,
/// an "Invite friends" row follows.
struct CrewSection: View {
    /// summary.standings (viewer first).
    let rows: [MemberStanding]
    let viewerID: String
    let onInvite: () -> Void

    private var keptCount: Int {
        rows.filter { $0.checkedInToday }.count
    }

    private var firstID: String? {
        rows.first?.id
    }

    /// Only you are in the group (or nobody is): offer the invite row. Never shown to non-members.
    private var isAlone: Bool {
        if rows.isEmpty { return true }
        return rows.count == 1 && rows[0].userID == viewerID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Crew", trailing: "\(keptCount) of \(rows.count) checked in")
            card
        }
    }

    private var card: some View {
        VStack(spacing: 0) {
            ForEach(rows) { row in
                if row.id != firstID {
                    InsetDivider(leading: 64)
                }
                CrewRow(row: row, isViewer: row.userID == viewerID)
            }
            if isAlone {
                if !rows.isEmpty {
                    InsetDivider()
                }
                inviteRow
            }
        }
        .card()
    }

    /// Neutral colours: accent stays reserved for "your turn". The icon sits in the avatar column.
    private var inviteRow: some View {
        Button(action: onInvite) {
            HStack(spacing: 12) {
                Image(systemName: "person.badge.plus")
                    .foregroundStyle(Palette.text2)
                    .frame(width: 36)
                    .accessibilityHidden(true)
                Text("Invite friends")
                    .foregroundStyle(Palette.text)
                Spacer()
            }
            .font(Typeface.subheadlineSemibold)
            .padding(.horizontal, 16)
            .frame(minHeight: Space.fieldHeight)
        }
        .buttonStyle(RowStyle())
    }
}

/// Avatar, name and short vow; today's status and net on the right. One VoiceOver element.
struct CrewRow: View {
    let row: MemberStanding
    let isViewer: Bool

    private var status: TodayStatus {
        TodayStatus(row.status(isViewer: isViewer))
    }

    private var name: String {
        isViewer ? "You" : row.displayName
    }

    private var shortVow: String {
        VowFormat.short(row.vow)
    }

    /// "You, Run 5k before work, Your turn, plus 4.5 points"
    private var spoken: String {
        [name, shortVow, status.title, PointsText.spoken(row.net, signed: true)].joined(separator: ", ")
    }

    var body: some View {
        HStack(spacing: 12) {
            Avatar(name: row.displayName, isViewer: isViewer)
            nameColumn
            Spacer(minLength: 8)
            statusColumn
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 64)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var nameColumn: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
                .font(Typeface.headline)
                .foregroundStyle(Palette.text)
                .lineLimit(1)
            Text(shortVow)
                .font(Typeface.subheadline)
                .foregroundStyle(Palette.text2)
                .lineLimit(1)
        }
    }

    /// Kept whole: the name and vow truncate first.
    private var statusColumn: some View {
        VStack(alignment: .trailing, spacing: 2) {
            StatusText(status)
            Text(PointsText.string(row.net, signed: true))
                .font(Typeface.footnote)
                .monospacedDigit()
                .foregroundStyle(isViewer ? Palette.points(row.net) : Palette.text3)
                .lineLimit(1)
        }
        .layoutPriority(1)
    }
}
