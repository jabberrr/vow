import SwiftUI

struct CrewCard: View {
    let crewTitle: String
    let rows: [CrewMemberRow]

    private var keptCount: Int {
        rows.filter { $0.status == .checkedIn }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            VStack(spacing: 10) {
                ForEach(rows) { row in
                    CrewRowView(row: row)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var header: some View {
        HStack {
            Text("Crew · " + crewTitle)
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
    let row: CrewMemberRow

    private var displayName: String {
        row.isYou ? "You" : row.name
    }

    private var initial: String {
        let source: String = row.isYou ? "You" : row.name
        if let first = source.first {
            return String(first).uppercased()
        }
        return "?"
    }

    var body: some View {
        HStack(spacing: 12) {
            avatar
            Text(displayName)
                .font(Theme.display(16, .medium))
                .foregroundStyle(Color.white.opacity(row.isYou ? 1.0 : 0.88))
                .lineLimit(1)
            Spacer(minLength: 8)
            CrewStatusBadge(status: row.status)
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

private struct CrewStatusBadge: View {
    let status: MemberStatus

    private var badgeColor: Color {
        switch status {
        case .checkedIn: return Theme.lime
        case .missed: return Theme.pink
        case .notYet: return Color.white.opacity(0.5)
        case .yourMove: return Theme.cyan
        }
    }

    var body: some View {
        Text(status.label.uppercased())
            .font(Theme.mono(10, .semibold))
            .tracking(1.0)
            .foregroundStyle(badgeColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(badgeColor.opacity(0.12)))
            .overlay(Capsule().strokeBorder(badgeColor.opacity(0.45), lineWidth: 0.75))
    }
}
