import SwiftUI

/// One group in the Home list (used as a NavigationLink label).
struct GroupRow: View {
    let id: GroupID
    @Environment(AppStore.self) private var store

    var body: some View {
        if let snapshot = store.snapshots[id] {
            GroupRowContent(group: snapshot.group, summary: store.summary(for: id))
        } else {
            loading
        }
    }

    private var loading: some View {
        HStack(spacing: 12) {
            Text("Loading group…")
                .font(Theme.display(17, .semibold))
                .foregroundStyle(Color.white.opacity(0.5))
            Spacer(minLength: 8)
            ProgressView()
                .tint(Color.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}

private struct GroupRowContent: View {
    let group: GroupInfo
    let summary: GroupSummary?

    private var viewer: MemberStanding? {
        summary?.viewer
    }

    private var memberCount: Int {
        summary?.standings.count ?? 0
    }

    private var net: Double {
        viewer?.net ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            titleRow
            infoRow
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
            netRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .contentShape(Rectangle())
    }

    private var titleRow: some View {
        HStack(spacing: 8) {
            Text(group.name)
                .font(Theme.display(19, .semibold))
                .foregroundStyle(Color.white)
                .lineLimit(1)
            if group.isTest {
                Badge(text: "Test", color: Theme.amber)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.4))
        }
    }

    private var infoRow: some View {
        HStack(spacing: 8) {
            Text(GroupFormat.members(memberCount) + " · " + GroupFormat.stake(group.stake) + "/day")
                .font(Theme.mono(12, .medium))
                .foregroundStyle(Color.white.opacity(0.55))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            statusBadge
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        if let viewer = viewer {
            StatusBadge(status: viewer.status(isViewer: true))
        } else {
            Badge(text: "Set your vow", color: Theme.cyan)
        }
    }

    private var netRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Your net")
                .eyebrow()
            Spacer(minLength: 8)
            Text(Points.format(net, signed: true))
                .font(Theme.mono(15, .semibold))
                .foregroundStyle(net >= 0 ? Theme.lime : Theme.pink)
        }
    }
}
