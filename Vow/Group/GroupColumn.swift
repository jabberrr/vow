import SwiftUI

/// The group screen's single column: header, the stage (vow, orb, status, progress) or the join
/// prompt, then Crew and Points. Nothing above the orb changes height on check-in, so the orb never
/// moves. During a hold every block except the vow and the orb dims with the room: per-block opacity
/// only, no overlay and no hit-testing change, so the dim can never intercept the orb's gesture.
struct GroupColumn: View {
    let id: GroupID
    let group: GroupInfo
    let summary: GroupSummary
    let theme: DailyTheme
    let viewerID: String
    let roomDimmed: Bool
    let hintFlash: Bool
    let settleToken: Int
    let rewardToken: Int
    let canAdvance: Bool
    let onSealed: () -> Void
    let onFocusChange: (Bool) -> Void
    let onEarlyRelease: () -> Void
    let onEditVow: () -> Void
    let onInvite: () -> Void

    private var isMember: Bool {
        summary.viewer != nil
    }

    private var sealed: Bool {
        summary.viewer?.checkedInToday ?? false
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            stage
            crew
            points
        }
        .padding(.top, 4)
        .padding(.bottom, Space.huge)
    }

    private var header: some View {
        GroupHeader(group: group, sealed: sealed, isMember: isMember)
            .padding(.horizontal, Space.gutter)
            .focusDimmed(roomDimmed)
    }

    /// The member branch never flips on check-in, so every stage view stays mounted through the seal.
    /// Its views are direct children of the column, so the orb's zIndex lifts the burst above them all.
    @ViewBuilder
    private var stage: some View {
        if let viewer = summary.viewer {
            vowLine(viewer)
            orb
            status(viewer)
            progress(viewer)
        } else {
            JoinPrompt(theme: theme, stake: group.stake, action: onEditVow)
                .padding(.horizontal, Space.gutter)
                .padding(.top, Space.xxl)
        }
    }

    /// Never dimmed: the vow stays lit with the orb.
    private func vowLine(_ viewer: MemberStanding) -> some View {
        VowLine(vow: viewer.vow, onEdit: onEditVow)
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.xxl - VowLine.tapPadding)
    }

    /// Never dimmed. `.id` remounts the orb on a new day or a reset.
    private var orb: some View {
        OrbView(theme: theme,
                sealed: sealed,
                onSealed: onSealed,
                onFocusChange: onFocusChange,
                onEarlyRelease: onEarlyRelease)
            .frame(width: 220, height: 220)
            .id("\(group.epoch)-\(summary.currentDay)")
            .frame(maxWidth: .infinity)
            .padding(.top, Space.m - VowLine.tapPadding)
            .zIndex(1)
    }

    private func status(_ viewer: MemberStanding) -> some View {
        CheckInStatus(sealed: viewer.checkedInToday, highlighted: hintFlash, settleToken: settleToken)
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.xs)
            .focusDimmed(roomDimmed)
    }

    /// Capped here (not inside) so ProgressSection's @ScaledMetric numeral sees the cap too.
    private func progress(_ viewer: MemberStanding) -> some View {
        ProgressSection(viewer: viewer, summary: summary, rewardToken: rewardToken)
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.section)
            .focusDimmed(roomDimmed)
    }

    private var crew: some View {
        CrewSection(rows: summary.standings, viewerID: viewerID, onInvite: onInvite)
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.section)
            .focusDimmed(roomDimmed)
    }

    private var points: some View {
        PointsSection(id: id, group: group, summary: summary, isMember: isMember, canAdvance: canAdvance)
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.section)
            .focusDimmed(roomDimmed)
    }
}
