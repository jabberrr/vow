import SwiftUI

/// The stage of a vow you are not in yet (joined by link without a vow, or left): an unlit sphere in
/// the orb's place, the stake rule, one way in, and the people already keeping it.
struct NotMemberStage: View {
    let group: GroupInfo
    let summary: GroupSummary
    let theme: DailyTheme
    let viewerID: String
    let metrics: StageMetrics
    let onJoin: () -> Void
    let onMember: (String) -> Void

    init(group: GroupInfo,
         summary: GroupSummary,
         theme: DailyTheme,
         viewerID: String,
         metrics: StageMetrics,
         onJoin: @escaping () -> Void,
         onMember: @escaping (String) -> Void) {
        self.group = group
        self.summary = summary
        self.theme = theme
        self.viewerID = viewerID
        self.metrics = metrics
        self.onJoin = onJoin
        self.onMember = onMember
    }

    private static let sphereSize: CGFloat = 150

    var body: some View {
        VStack(spacing: 0) {
            vowSlot
            Sphere(theme: theme, state: .unlit, size: NotMemberStage.sphereSize, showsGlyph: true)
                .padding(.top, metrics.orbTop + (Gap.orbSlot - NotMemberStage.sphereSize) / 2)
            rule
                .padding(.top, Gap.l)
            PillButton("Write your vow to join", action: onJoin)
                .padding(.horizontal, Gap.gutter)
                .padding(.top, 14)
            strip
                .padding(.top, metrics.tagGap + Gap.m)
        }
        .frame(maxWidth: .infinity)
    }

    /// Holds the vow's line so the sphere's centre sits exactly where the orb's would.
    private var vowSlot: some View {
        Text("I will")
            .font(Fonts.vow)
            .hidden()
            .padding(.top, metrics.vowTop)
            .accessibilityHidden(true)
    }

    private var rule: some View {
        Text(StakeText.rule(group.stake))
            .font(Fonts.subheadline)
            .foregroundStyle(Ink.text2)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Gap.xxxl)
    }

    /// Without you and without the Invite seat.
    private var strip: some View {
        MemberStrip(theme: theme,
                    standings: summary.standings,
                    viewerID: viewerID,
                    viewerLit: false,
                    atRisk: false,
                    showsInvite: false,
                    cell: metrics.stripCell,
                    rowTop: metrics.stripRowTop,
                    hidesLabel: false,
                    onMember: onMember,
                    onInvite: {})
    }
}
