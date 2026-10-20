import SwiftUI

/// The member stage in reading order: the vow, the orb, the streak, the caption, then who kept today
/// with the milestone tag in the reserved gap above them. One VStack, so the orb's zIndex lifts its
/// burst over every sibling. Nothing here changes height on check-in: the three caption phrasings
/// share one slot, the tag is an overlay, and only the vow and the orb stay lit during a hold.
struct StageCenter: View {
    let group: GroupInfo
    let summary: GroupSummary
    let viewer: MemberStanding
    let theme: DailyTheme
    let viewerID: String
    let metrics: StageMetrics
    let now: Date
    let roomDimmed: Bool
    let shownStreak: Int
    let captionKept: Bool
    let viewerLit: Bool
    let hintFlash: Bool
    let flareToken: Int
    let milestone: StreakEvent?
    let milestoneToken: Int
    let onSealed: () -> Void
    let onFocusChange: (Bool) -> Void
    let onEarlyRelease: () -> Void
    let onEditVow: () -> Void
    let onStreak: () -> Void
    let onMember: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize: DynamicTypeSize

    init(group: GroupInfo,
         summary: GroupSummary,
         viewer: MemberStanding,
         theme: DailyTheme,
         viewerID: String,
         metrics: StageMetrics,
         now: Date,
         roomDimmed: Bool,
         shownStreak: Int,
         captionKept: Bool,
         viewerLit: Bool,
         hintFlash: Bool,
         flareToken: Int,
         milestone: StreakEvent?,
         milestoneToken: Int,
         onSealed: @escaping () -> Void,
         onFocusChange: @escaping (Bool) -> Void,
         onEarlyRelease: @escaping () -> Void,
         onEditVow: @escaping () -> Void,
         onStreak: @escaping () -> Void,
         onMember: @escaping (String) -> Void) {
        self.group = group
        self.summary = summary
        self.viewer = viewer
        self.theme = theme
        self.viewerID = viewerID
        self.metrics = metrics
        self.now = now
        self.roomDimmed = roomDimmed
        self.shownStreak = shownStreak
        self.captionKept = captionKept
        self.viewerLit = viewerLit
        self.hintFlash = hintFlash
        self.flareToken = flareToken
        self.milestone = milestone
        self.milestoneToken = milestoneToken
        self.onSealed = onSealed
        self.onFocusChange = onFocusChange
        self.onEarlyRelease = onEarlyRelease
        self.onEditVow = onEditVow
        self.onStreak = onStreak
        self.onMember = onMember
    }

    /// Invisible padding above and below the vow so its tap target is at least 44 pt; the stage
    /// spacing around it is reduced by the same amount, so the orb sits where the metrics say.
    static let vowTapPadding: CGFloat = 8

    var body: some View {
        VStack(spacing: 0) {
            vowButton
                .padding(.top, metrics.vowTop - StageCenter.vowTapPadding)
            orb
                .padding(.top, metrics.orbTop - StageCenter.vowTapPadding)
                .zIndex(1)
            streak
                .padding(.top, metrics.streakTop)
                .roomDim(roomDimmed)
                .zIndex(0.5)
            caption
                .padding(.top, metrics.captionTop)
                .roomDim(roomDimmed)
            strip
        }
    }

    // MARK: - Vow (never dimmed)

    private var vowButton: some View {
        Button(action: onEditVow) {
            StageCenter.vowText(viewer.vow)
                .font(Fonts.vow)
                .multilineTextAlignment(.center)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 36)
                .padding(.vertical, StageCenter.vowTapPadding)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(viewer.vow)
        .accessibilityHint("Edit your vow")
    }

    /// "I will" in text2 puts the weight on the verb. Also the finished stage's vow.
    static func vowText(_ vow: String) -> Text {
        let parts: (prefix: String, verb: String, suffix: String) = VowText.split(vow)
        if parts.verb.isEmpty {
            return Text(vow).foregroundStyle(Ink.text)
        }
        let head: Text = Text(parts.prefix).foregroundStyle(Ink.text2)
        let rest: Text = Text(parts.verb + parts.suffix).foregroundStyle(Ink.text)
        return head + rest
    }

    // MARK: - Orb (never dimmed, unchanged)

    private var orb: some View {
        OrbView(theme: theme,
                sealed: viewer.checkedInToday,
                onSealed: onSealed,
                onFocusChange: onFocusChange,
                onEarlyRelease: onEarlyRelease)
            .frame(width: Gap.orbSlot, height: Gap.orbSlot)
            .id(StageScreen.orbKey(group: group, summary: summary))
            .frame(maxWidth: .infinity)
    }

    // MARK: - Streak

    private var streakLabel: String {
        shownStreak == 1 ? "1-day streak" : "\(shownStreak)-day streak"
    }

    /// The secondary way to the Streak tab. Capped at AX2 here, so the scaled numeral sees the cap. The
    /// side padding only widens the target; embers are an overlay: neither changes the layout.
    private var streak: some View {
        Button(action: onStreak) {
            FlameStreak(count: shownStreak, size: metrics.compact ? .largeCompact : .large, flareToken: flareToken)
                .padding(.horizontal, Gap.l)
                .frame(minHeight: Gap.hit)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .overlay {
            EmberBurst(trigger: milestoneToken)
        }
        .accessibilityLabel(streakLabel)
        .accessibilityHint("Opens Streak")
    }

    // MARK: - Caption

    private var showsHint: Bool {
        !captionKept && hintFlash
    }

    private var showsOpen: Bool {
        !captionKept && !hintFlash
    }

    /// All three phrasings stay mounted in one slot, so its height never changes on check-in.
    private var caption: some View {
        ZStack {
            openCaption
                .opacity(showsOpen ? 1 : 0)
                .accessibilityHidden(!showsOpen)
            Text("Hold until the ring fills")
                .foregroundStyle(Ink.text)
                .opacity(showsHint ? 1 : 0)
                .accessibilityHidden(!showsHint)
            keptCaption
                .opacity(captionKept ? 1 : 0)
                .accessibilityHidden(!captionKept)
        }
        .font(Fonts.subheadline)
        .foregroundStyle(Ink.text2)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, Gap.gutter)
        .frame(maxWidth: .infinity)
        .animation(Anim.fade, value: hintFlash)
        .animation(Anim.fade, value: captionKept)
    }

    /// Time left appears only in the last 4 h of a real group's day (nil for test groups).
    private var openCaption: Text {
        guard let left: TimeInterval = DayWindow.secondsLeft(group, now: now),
              left < DayWindow.atRiskSeconds else {
            return Text("Hold to check in")
        }
        var timeText: String = "under a minute left"
        if let span: String = DayWindow.span(left) {
            timeText = span + " left"
        }
        let lead: Text = Text("Hold to check in · ")
        let time: Text = Text(timeText).foregroundStyle(Ink.flame).fontWeight(.semibold)
        return lead + time
    }

    /// Nothing follows the vow's final day, so kept on it reads just "Kept today".
    private var keptCaption: Text {
        if summary.endDay == summary.currentDay {
            return Text("Kept today")
        }
        guard let left: TimeInterval = DayWindow.secondsLeft(group, now: now) else {
            return Text("Kept today")
        }
        if let span: String = DayWindow.span(left) {
            return Text("Kept today · Next day in " + span)
        }
        return Text("Kept today · Next day in under a minute")
    }

    // MARK: - Who kept today, with the milestone tag in the gap above

    /// Your open ring turns flame in the last 4 h, until your sphere lights.
    private var atRisk: Bool {
        !viewerLit && DayWindow.isAtRisk(group, now: now)
    }

    private var strip: some View {
        MemberStrip(theme: theme,
                    standings: summary.standings,
                    viewerID: viewerID,
                    viewerLit: viewerLit,
                    atRisk: atRisk,
                    cell: metrics.stripCell,
                    rowTop: metrics.stripRowTop,
                    onMember: onMember)
            .padding(.top, metrics.tagGap)
            .overlay(alignment: .top) {
                tag
            }
            .roomDim(roomDimmed)
    }

    /// Inside the reserved gap (`tagOffset` from its top) on every screen size, for the rest of the day.
    @ViewBuilder
    private var tag: some View {
        if let event: StreakEvent = milestone {
            Tag(MilestoneText.title(event), systemImage: "flame.fill", style: .milestone)
                .offset(y: metrics.tagOffset)
                .transition(tagTransition)
        }
    }

    private var tagTransition: AnyTransition {
        if reduceMotion {
            return AnyTransition.opacity
        }
        return AnyTransition.opacity.combined(with: .scale(scale: 0.8))
    }
}
