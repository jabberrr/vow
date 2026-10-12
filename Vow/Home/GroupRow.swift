import SwiftUI

/// One group in the Home list (a NavigationLink label inside the Groups card).
struct GroupRow: View {
    let id: GroupID
    @Environment(AppStore.self) private var store

    var body: some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
            .contentShape(Rectangle())
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot = store.snapshots[id] {
            GroupRowContent(group: snapshot.group, summary: store.summary(for: id), theme: store.theme(for: id))
        } else {
            loading
        }
    }

    private var loading: some View {
        HStack(spacing: 14) {
            ProgressView()
                .controlSize(.small)
                .tint(Palette.text3)
                .frame(width: 36, height: 36)
            Text("Loading…")
                .font(Typeface.headline)
                .foregroundStyle(Palette.text3)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading…")
    }
}

/// Mini orb, name (+ Test chip), today's status and streak, your net, chevron.
private struct GroupRowContent: View {
    let group: GroupInfo
    let summary: GroupSummary?
    let theme: DailyTheme

    private var viewer: MemberStanding? {
        summary?.viewer
    }

    private var status: TodayStatus {
        guard let viewer = viewer else { return .notJoined }
        return TodayStatus(viewer.status(isViewer: true))
    }

    private var orbState: MiniOrbState {
        switch status {
        case .checkedIn:
            return .sealed
        case .notJoined:
            return .notJoined
        case .yourTurn, .notYet, .missedYesterday:
            return .open
        }
    }

    private var streak: Int {
        viewer?.streak ?? 0
    }

    var body: some View {
        HStack(spacing: 14) {
            MiniOrb(theme: theme, state: orbState)
            VStack(alignment: .leading, spacing: 2) {
                titleLine
                subline
                    .font(Typeface.subheadline)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let viewer = viewer {
                netText(viewer.net)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.text3)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
    }

    private var titleLine: some View {
        HStack(spacing: 8) {
            Text(group.name)
                .font(Typeface.headline)
                .foregroundStyle(Palette.text)
                .lineLimit(1)
                .layoutPriority(1)
            if group.isTest {
                Chip("Test")
            }
        }
    }

    @ViewBuilder
    private var subline: some View {
        switch status {
        case .notJoined:
            Text(TodayStatus.notJoined.title)
                .foregroundStyle(Palette.text2)
        case .checkedIn:
            Text("\(streak)-day streak")
                .foregroundStyle(Palette.text2)
        case .yourTurn, .notYet, .missedYesterday:
            yourTurnLine
        }
    }

    /// "Your turn · 12-day streak", falling back to "Your turn" when the row is too narrow.
    @ViewBuilder
    private var yourTurnLine: some View {
        if streak > 0 {
            ViewThatFits(in: .horizontal) {
                yourTurnWithStreak
                    .lineLimit(1)
                yourTurn
                    .lineLimit(1)
            }
        } else {
            yourTurn
        }
    }

    private var yourTurn: Text {
        Text(TodayStatus.yourTurn.title).foregroundStyle(Palette.text)
    }

    private var yourTurnWithStreak: Text {
        let tail: Text = Text(" · \(streak)-day streak").foregroundStyle(Palette.text2)
        return yourTurn + tail
    }

    /// Your own net, coloured; never truncated (the name gives way instead).
    private func netText(_ net: Double) -> some View {
        let parts: (number: String, unit: String) = PointsText.parts(net, signed: true)
        let label: String = parts.unit.isEmpty ? parts.number : parts.number + " " + parts.unit
        return Text(label)
            .font(Typeface.subheadlineSemibold)
            .monospacedDigit()
            .foregroundStyle(Palette.points(net))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    /// "Morning run, test group, Your turn, 12-day streak, plus 4.5 points".
    private var spokenLabel: String {
        var parts: [String] = [group.name]
        if group.isTest {
            parts.append("test group")
        }
        parts.append(status.title)
        if let viewer = viewer {
            if viewer.streak > 0 {
                parts.append("\(viewer.streak)-day streak")
            }
            parts.append(PointsText.spoken(viewer.net, signed: true))
        }
        return parts.joined(separator: ", ")
    }
}
