import SwiftUI

/// The single scrolling column for one group. Everything above the orb has constant height in both
/// states (header fixed, vow card unchanged by check-in, creed line fixed), so the orb never moves.
struct GroupColumn: View {
    let group: GroupInfo
    let summary: GroupSummary
    let theme: DailyTheme
    let viewerID: String
    let since: String
    let onSealed: () -> Void
    let onSetVow: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            HeaderView(group: group, cycle: summary.cycle, day: summary.dayInCycle)
            memberSection
            CrewCard(rows: summary.standings, viewerID: viewerID, stake: group.stake)
            PotCard(pot: summary.pot, totalForfeited: summary.totalForfeited, net: summary.viewer?.net ?? 0)
            LedgerCard(lines: summary.ledger, isTest: group.isTest)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 28)
    }

    @ViewBuilder
    private var memberSection: some View {
        if let viewer = summary.viewer {
            VowCard(vow: viewer.vow, groupName: group.name, stake: GroupFormat.stake(group.stake), since: since)
            CreedLine(glyphNumber: summary.glyphNumber, creed: theme.creed, sealed: viewer.checkedInToday)
            orb(sealed: viewer.checkedInToday)
            StreakCard(
                streak: viewer.streak,
                best: max(viewer.bestStreak, viewer.streak),
                history: viewer.history,
                sealedToday: viewer.checkedInToday
            )
        } else {
            JoinVowCard(groupName: group.name, stake: group.stake, action: onSetVow)
        }
    }

    private func orb(sealed: Bool) -> some View {
        OrbView(theme: theme, sealed: sealed, onSealed: onSealed)
            .frame(width: 220, height: 220)
            .id("\(group.epoch)-\(summary.currentDay)")
            .frame(maxWidth: .infinity)
            .zIndex(1)
    }
}

/// Shown instead of the orb section while you're not a member of the group yet.
struct JoinVowCard: View {
    let groupName: String
    let stake: Int
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Not in yet")
                .eyebrow()
            Text("Set your vow to join")
                .font(Theme.display(22, .semibold))
                .gradientText()
            Text("Everyone in \(groupName) keeps their own daily vow and stakes \(GroupFormat.stake(stake)) a day on it.")
                .font(Theme.display(15, .regular))
                .foregroundStyle(Color.white.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
            PrimaryButton(title: "Set my vow", action: action)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}
