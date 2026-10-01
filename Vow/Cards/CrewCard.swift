import SwiftUI

struct CrewCard: View {
    /// Active members, viewer first.
    let rows: [MemberStanding]
    let viewerID: String
    let stake: Int

    private var keptCount: Int {
        rows.filter { $0.checkedInToday }.count
    }

    private var memberText: String {
        rows.count == 1 ? "1 member" : "\(rows.count) members"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            VStack(spacing: 12) {
                ForEach(rows) { row in
                    CrewRowView(row: row, isViewer: row.userID == viewerID)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var header: some View {
        HStack {
            Text("Crew · " + memberText)
                .eyebrow()
                .lineLimit(1)
            Spacer(minLength: 8)
            Text("\(keptCount)/\(rows.count) in")
                .font(Theme.mono(11, .semibold))
                .foregroundStyle(Color.white.opacity(0.55))
        }
    }
}

private struct CrewRowView: View {
    let row: MemberStanding
    let isViewer: Bool

    private var displayName: String {
        isViewer ? "You" : row.displayName
    }

    private var initial: String {
        if let first = displayName.first {
            return String(first).uppercased()
        }
        return "?"
    }

    private var netColor: Color {
        row.net >= 0 ? Theme.lime : Theme.pink
    }

    var body: some View {
        HStack(spacing: 12) {
            avatar
            nameColumn
            Spacer(minLength: 8)
            statusColumn
        }
    }

    private var nameColumn: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(displayName)
                .font(Theme.display(16, .medium))
                .foregroundStyle(Color.white.opacity(isViewer ? 1.0 : 0.88))
                .lineLimit(1)
            Text(row.vow)
                .font(Theme.mono(11, .medium))
                .foregroundStyle(Color.white.opacity(0.45))
                .lineLimit(1)
        }
    }

    private var statusColumn: some View {
        VStack(alignment: .trailing, spacing: 5) {
            StatusBadge(status: row.status(isViewer: isViewer))
            Text(Points.format(row.net, signed: true))
                .font(Theme.mono(11, .semibold))
                .foregroundStyle(netColor)
                .lineLimit(1)
        }
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.06))
            Circle()
                .strokeBorder(Theme.brand, lineWidth: 1)
            Text(initial)
                .font(Theme.display(15, .semibold))
                .foregroundStyle(Color.white)
        }
        .frame(width: 34, height: 34)
    }
}
