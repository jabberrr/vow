import SwiftUI
import Accessibility

/// Callbacks from Home to the shell, which owns the sheets, the confirmations, the tabs and the chrome.
struct StageActions {
    let editVow: () -> Void
    let showMember: (String) -> Void
    /// The streak was tapped: the shell selects the Streak tab.
    let showStreak: () -> Void
    /// TestDayBar's Reset: the shell confirms (MainDialog.resetTest).
    let confirmReset: () -> Void
    /// At the seal: the shell keeps this vow open everywhere (Streak tab, sidebar) until didLight.
    let willLight: () -> Void
    /// At the social beat, and on revert, cancel or disappear: the shell lights the Streak tab's flame.
    let didLight: () -> Void
    /// Seal + 2.0 s: the shell pulses the ≡ glyph if another vow is still open.
    let didKeep: () -> Void
    /// Seal + 2.3 s: the one-time reminder offer, if due.
    let offerReminder: () -> Void
    /// "Can't today?": the shell presents the excuse sheet.
    let excuse: () -> Void
    /// Add proof: the shell's proof chooser (camera or library).
    let addProof: () -> Void
    /// "Proof sent": the shell selects the Chat tab.
    let showChat: () -> Void
}

/// Where the cascade after a seal has got to. `.done` is the resting state: everything shows
/// the store's values. Compared through `rawValue`.
enum KeepBeat: Int {
    case sealed = 1, settled, rewarded, social, done
}

/// Home: one vow's stage (member, not a member, finished or loading), centred between the bars, with the
/// check-in choreography, the foot line (an excuse before, proof after) and the test controls. Sheets,
/// confirmations, the banner and the periodic refresh belong to the shell; this view asks for them through
/// `actions`.
struct StageScreen: View {
    let id: GroupID
    @Binding var roomDimmed: Bool
    let metrics: StageMetrics
    /// Bumped by the shell when the Home tab is tapped again: scroll to the top.
    let topToken: Int
    let actions: StageActions

    @Environment(AppStore.self) private var store
    @State private var testBusy: Bool = false
    // Check-in choreography
    @State private var dimTask: Task<Void, Never>? = nil
    @State private var beatTask: Task<Void, Never>? = nil
    @State private var hintTask: Task<Void, Never>? = nil
    @State private var awaitingSeal: Bool = false
    @State private var beat: KeepBeat = .done
    @State private var heldStreak: Int = 0
    @State private var flareToken: Int = 0
    @State private var rewardToken: Int = 0
    @State private var milestoneToken: Int = 0
    @State private var milestone: StreakEvent? = nil
    @State private var hintFlash: Bool = false
    /// The keep's ≡ pulse and reminder offer, while their beat has not come yet. Leaving Home before
    /// then delivers them at once instead of dropping them.
    @State private var pulsePending: Bool = false
    @State private var offerPending: Bool = false
    /// From the seal to the cascade's last beat, or until it is cut short: the foot stays empty, and the
    /// meta line holds what it said.
    @State private var cascadeRunning: Bool = false
    /// "Yesterday was overruled" as the meta line showed it when a hold or the cascade began, so a verdict
    /// landing then can't add a line; nil otherwise (the live value shows).
    @State private var heldOverrule: Bool? = nil

    init(id: GroupID, roomDimmed: Binding<Bool>, metrics: StageMetrics, topToken: Int, actions: StageActions) {
        self.id = id
        self._roomDimmed = roomDimmed
        self.metrics = metrics
        self.topToken = topToken
        self.actions = actions
    }

    private static let topID: String = "stage-top"

    /// The stage on a per-minute clock (caption, at-risk rings and the day roll over on time), with
    /// the reward haptics and the cleanup hooks.
    var body: some View {
        TimelineView(.everyMinute) { context in
            stage(now: context.date)
        }
        .vowBackground()
        .sensoryFeedback(.impact(weight: .light, intensity: 0.7), trigger: rewardToken)
        .sensoryFeedback(.success, trigger: milestoneToken)
        .onChange(of: roomDimmed || cascadeRunning) { (_: Bool, held: Bool) in
            holdMeta(held)
        }
        .onChange(of: id) { _, _ in
            resetChoreography()
        }
        .onDisappear {
            resetChoreography()
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func stage(now: Date) -> some View {
        if let snapshot: GroupSnapshot = store.snapshots[id], let summary: GroupSummary = store.summary(for: id) {
            loaded(snapshot: snapshot, summary: summary, now: now)
        } else {
            ProgressView()
                .tint(Ink.text3)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func loaded(snapshot: GroupSnapshot, summary: GroupSummary, now: Date) -> some View {
        let sealed: Bool = summary.viewer?.checkedInToday ?? false
        let orbKey: String = StageScreen.orbKey(group: snapshot.group, summary: summary)
        return ScrollViewReader { (proxy: ScrollViewProxy) in
            GeometryReader { (geometry: GeometryProxy) in
                ScrollView(.vertical, showsIndicators: false) {
                    page(snapshot: snapshot, summary: summary, now: now, height: geometry.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .onChange(of: topToken) { _, _ in
                withAnimation(Anim.standard) {
                    proxy.scrollTo(StageScreen.topID, anchor: .top)
                }
            }
        }
        .onChange(of: sealed) { oldValue, newValue in
            sealedChanged(from: oldValue, to: newValue)
        }
        .onChange(of: orbKey) { _, _ in
            dayChanged()
        }
    }

    /// Remounts the orb on a new day or a reset; the milestone tag belongs to the day it was earned.
    static func orbKey(group: GroupInfo, summary: GroupSummary) -> String {
        return "\(group.id.zoneName)-\(group.epoch)-\(summary.currentDay)"
    }

    /// The block is centred between the bars when it fits (the spacers share what is left), and then the
    /// page doesn't move at all: no bounce and no pull to refresh, which the shell's refresh makes
    /// unnecessary. It scrolls only when it doesn't fit: accessibility sizes, or a test bar on a small screen.
    private func page(snapshot: GroupSnapshot, summary: GroupSummary, now: Date, height: CGFloat) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: Gap.s)
            block(snapshot: snapshot, summary: summary, now: now)
            Spacer(minLength: Gap.xxl)
        }
        .frame(maxWidth: .infinity, minHeight: height)
        .id(StageScreen.topID)
    }

    /// The meta line, when it has something to say, over whichever stage applies.
    private func block(snapshot: GroupSnapshot, summary: GroupSummary, now: Date) -> some View {
        let overruled: Bool = heldOverrule ?? yesterdayOverruled(snapshot, summary: summary, now: now)
        return VStack(spacing: 0) {
            StageMeta(group: snapshot.group, summary: summary, now: now, yesterdayOverruled: overruled)
                .roomDim(roomDimmed)
            content(snapshot: snapshot, summary: summary, now: now)
        }
    }

    @ViewBuilder
    private func content(snapshot: GroupSnapshot, summary: GroupSummary, now: Date) -> some View {
        let group: GroupInfo = snapshot.group
        if summary.isFinished {
            finishedBody(group: group, summary: summary)
        } else if let viewer: MemberStanding = summary.viewer {
            memberBody(snapshot: snapshot, summary: summary, viewer: viewer, now: now)
        } else {
            NotMemberStage(group: group,
                           summary: summary,
                           theme: Overview.theme(summary),
                           viewerID: store.userID ?? "",
                           metrics: metrics,
                           onJoin: actions.editVow,
                           onMember: actions.showMember)
        }
    }

    /// The center keeps zIndex 1 so the orb's burst draws over the foot and the test bar.
    private func memberBody(snapshot: GroupSnapshot, summary: GroupSummary, viewer: MemberStanding,
                            now: Date) -> some View {
        VStack(spacing: 0) {
            center(group: snapshot.group, summary: summary, viewer: viewer,
                   excuse: todayExcuse(snapshot, summary: summary, viewer: viewer), now: now)
                .zIndex(1)
            foot(snapshot: snapshot, summary: summary, viewer: viewer)
            if isTestOwner(snapshot.group) {
                testBar(canAdvance: true)
                    .padding(.top, Gap.l)
            }
        }
    }

    /// A finished test vow keeps its bar, Next day disabled, so the owner can still reset it.
    private func finishedBody(group: GroupInfo, summary: GroupSummary) -> some View {
        VStack(spacing: 0) {
            FinishedStage(summary: summary, metrics: metrics)
            if isTestOwner(group) {
                testBar(canAdvance: false)
                    .padding(.top, Gap.xxl)
            }
        }
    }

    private func center(group: GroupInfo, summary: GroupSummary, viewer: MemberStanding, excuse: String?,
                        now: Date) -> some View {
        StageCenter(group: group,
                    summary: summary,
                    viewer: viewer,
                    excuse: excuse,
                    theme: Overview.theme(summary),
                    viewerID: store.userID ?? "",
                    metrics: metrics,
                    now: now,
                    roomDimmed: roomDimmed,
                    shownStreak: shownStreak(viewer),
                    captionKept: captionKept(viewer),
                    viewerLit: viewerLit(viewer),
                    hintFlash: hintFlash,
                    flareToken: flareToken,
                    milestone: milestone,
                    milestoneToken: milestoneToken,
                    onSealed: handleSealed,
                    onFocusChange: focusChanged,
                    onEarlyRelease: earlyRelease,
                    onEditVow: actions.editVow,
                    onStreak: showStreak,
                    onMember: actions.showMember)
    }

    private func foot(snapshot: GroupSnapshot, summary: GroupSummary, viewer: MemberStanding) -> some View {
        StageFoot(phase: footPhase(snapshot: snapshot, summary: summary, viewer: viewer),
                  onExcuse: excuse,
                  onAddProof: actions.addProof,
                  onRetry: retryProof,
                  onShowChat: actions.showChat)
            .padding(.top, metrics.footTop)
            .roomDim(roomDimmed)
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    private func testBar(canAdvance: Bool) -> some View {
        TestDayBar(metrics: metrics,
                   busy: testBusy,
                   canAdvance: canAdvance,
                   onNextDay: advanceDay,
                   onReset: actions.confirmReset)
            .roomDim(roomDimmed)
    }

    // MARK: - Derived

    /// Read at call time (focus changes, the seal), not from a captured body value.
    private var viewerSealed: Bool {
        store.summary(for: id)?.viewer?.checkedInToday ?? false
    }

    private func isTestOwner(_ group: GroupInfo) -> Bool {
        store.testingMode && group.isTest && store.isOwner(id)
    }

    /// The caption agrees with the orb first (settle beat).
    private func captionKept(_ viewer: MemberStanding) -> Bool {
        viewer.checkedInToday && beat.rawValue >= KeepBeat.settled.rawValue
    }

    /// The streak holds its old value until the reward beat.
    private func shownStreak(_ viewer: MemberStanding) -> Int {
        beat.rawValue >= KeepBeat.rewarded.rawValue ? viewer.streak : heldStreak
    }

    /// Your strip sphere and your place in the count light at the social beat, when the shell lights the
    /// Streak tab's flame.
    private func viewerLit(_ viewer: MemberStanding) -> Bool {
        viewer.checkedInToday && beat.rawValue >= KeepBeat.social.rawValue
    }

    /// Home's foot, first match wins: "Can't today?" until the caption says the check-in is kept; nothing
    /// while excused or while the cascade runs; then today's proof: sending, not sent, Add proof again while
    /// the check-in stands overruled (proof is how minds change), sent, or none yet. The upload's progress
    /// is the foot's own read, so its ticks never re-run this stage's Settlement pass.
    private func footPhase(snapshot: GroupSnapshot, summary: GroupSummary, viewer: MemberStanding) -> StageFoot.Phase {
        if viewer.excusedToday {
            return .quiet
        }
        if !captionKept(viewer) {
            return .excuse
        }
        if cascadeRunning {
            return .quiet
        }
        let proof: DayProof = DayProof(snapshot, author: viewer.userID, day: summary.currentDay, failed: store.failedPosts)
        if !proof.sending.isEmpty {
            return .sending(proof.sending)
        }
        if let postID: String = proof.failedID {
            return .notSent(postID)
        }
        if viewer.todayOverruled || !proof.sent {
            return .addProof
        }
        return .proofSent
    }

    /// Today's excuse, quoted under the caption while you are excused.
    private func todayExcuse(_ snapshot: GroupSnapshot, summary: GroupSummary, viewer: MemberStanding) -> String? {
        guard viewer.excusedToday else { return nil }
        for record in snapshot.excuses where record.userID == viewer.userID && record.day == summary.currentDay {
            if record.epoch == snapshot.group.epoch {
                return record.text
            }
        }
        return nil
    }

    /// The group overruled your check-in or excuse of yesterday, and the vow still runs.
    private func yesterdayOverruled(_ snapshot: GroupSnapshot, summary: GroupSummary, now: Date) -> Bool {
        guard !summary.isFinished, summary.currentDay > 0, let me: String = store.userID else { return false }
        let tally: ClaimTally? = Review.tally(subject: me, day: summary.currentDay - 1, snapshot: snapshot, now: now)
        return tally?.overruled == true
    }

    // MARK: - Taps

    /// Ignored while the room is dimmed: swapping the page then would take the orb off screen, and its
    /// teardown drops a seal that has not been delivered yet.
    private func showStreak() {
        guard !roomDimmed else { return }
        actions.showStreak()
    }

    /// "Can't today?" stays during a hold, dimmed, and until the settle beat; a tap on it then is ignored,
    /// as above, and once the check-in is in there is nothing left to excuse.
    private func excuse() {
        guard !roomDimmed, !viewerSealed else { return }
        actions.excuse()
    }

    private func retryProof(_ postID: String) {
        Task { @MainActor in
            await store.retryPost(postID, in: id)
        }
    }

    // MARK: - Test controls

    /// One Next day at a time. Reset goes through the shell's confirmation.
    private func advanceDay() {
        guard !testBusy else { return }
        testBusy = true
        Task { @MainActor in
            await store.advanceTestDay(id)
            testBusy = false
        }
    }

    // MARK: - Check-in choreography

    /// OrbView reports focus. The room only dims after 200 ms of steady pressure; a lift, movement
    /// or a scroll before then cancels it, so taps and scrolls never change the room.
    private func focusChanged(_ on: Bool) {
        dimTask?.cancel()
        dimTask = nil
        if on {
            dimTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: Anim.dimGateNanos)
                if Task.isCancelled { return }
                withAnimation(Anim.dimIn) { roomDimmed = true }
            }
        } else if roomDimmed {
            // Focus ends at the seal (fast lights-up) or on an early release (slower recovery).
            withAnimation(viewerSealed ? Anim.lightsUp : Anim.dimOut) { roomDimmed = false }
        }
    }

    /// OrbView's onSealed (0.9 s after completion, or VoiceOver's "Check in"). The beats start when
    /// the optimistic check-in flips `sealed` (below). The check-in task itself is never cancelled:
    /// it is the save. A check-in that returns without sealing finishes the beat here.
    private func handleSealed() {
        heldStreak = store.summary(for: id)?.viewer?.streak ?? 0
        awaitingSeal = true
        beat = .sealed
        cascadeRunning = true
        actions.willLight()
        Task { @MainActor in
            await store.checkIn(id)
            awaitingSeal = false
            if beatTask == nil && beat == .sealed {
                beat = .done
                cascadeRunning = false
                actions.didLight()
                if roomDimmed {
                    withAnimation(Anim.lightsUp) { roomDimmed = false }
                }
            }
        }
    }

    private func sealedChanged(from oldValue: Bool, to newValue: Bool) {
        if oldValue && !newValue {
            // A failed check-in reverted, or a new day began: no reward, nothing left half lit.
            finishBeats()
            milestone = nil
            return
        }
        guard !oldValue, newValue, awaitingSeal else { return }
        startBeats()
    }

    /// Seal + 0.12 settle, 0.25 reward, 0.45 social, 0.7 milestone, 2.0 the ≡ pulse, 2.3 reminder offer
    /// and the foot's proof line.
    private func startBeats() {
        awaitingSeal = false
        beatTask?.cancel()
        let viewer: MemberStanding? = store.summary(for: id)?.viewer
        let streak: Int = viewer?.streak ?? 0
        var event: StreakEvent? = nil
        if let v: MemberStanding = viewer {
            event = StreakEvents.event(streak: v.streak, history: v.history)
        }
        let found: StreakEvent? = event
        let isTest: Bool = store.snapshots[id]?.group.isTest ?? true
        pulsePending = true
        offerPending = !isTest
        beatTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Anim.settleNanos)
            if Task.isCancelled { return }
            withAnimation(Anim.fade) { beat = .settled }
            AccessibilityNotification.Announcement(MilestoneText.announcement(streak: streak, event: found)).post()

            try? await Task.sleep(nanoseconds: Anim.rewardNanos - Anim.settleNanos)
            if Task.isCancelled { return }
            withAnimation(Anim.reward) { beat = .rewarded }
            flareToken += 1
            rewardToken += 1

            try? await Task.sleep(nanoseconds: Anim.socialNanos - Anim.rewardNanos)
            if Task.isCancelled { return }
            withAnimation(Anim.light) { beat = .social }
            actions.didLight()

            try? await Task.sleep(nanoseconds: Anim.milestoneNanos - Anim.socialNanos)
            if Task.isCancelled { return }
            if let e: StreakEvent = found {
                showMilestone(e)
            }
            beat = .done

            try? await Task.sleep(nanoseconds: Anim.nextNanos - Anim.milestoneNanos)
            if Task.isCancelled { return }
            pulsePending = false
            actions.didKeep()

            try? await Task.sleep(nanoseconds: Anim.offerNanos - Anim.nextNanos)
            if Task.isCancelled { return }
            if offerPending {
                offerPending = false
                actions.offerReminder()
            }
            withAnimation(Anim.fade) { cascadeRunning = false }
            beatTask = nil
        }
    }

    /// Embers, the tag in its reserved gap (for the rest of the day) and the success haptic.
    private func showMilestone(_ event: StreakEvent) {
        withAnimation(Anim.reward) { milestone = event }
        milestoneToken += 1
    }

    /// Ends the cascade wherever it is: everything shows the store's values, the foot its final state, and
    /// the shell may light the Streak tab's flame.
    private func finishBeats() {
        beatTask?.cancel()
        beatTask = nil
        pulsePending = false
        offerPending = false
        beat = .done
        cascadeRunning = false
        actions.didLight()
    }

    /// Leaving Home after a keep, before its last beats: they run now, each once. The ≡ pulse plays at
    /// once; the reminder offer waits in the shell's presenter until nothing is up.
    private func deliverPendingKeep() {
        if pulsePending {
            pulsePending = false
            actions.didKeep()
        }
        if offerPending {
            offerPending = false
            actions.offerReminder()
        }
    }

    private func dayChanged() {
        milestone = nil
    }

    /// A hold or the cascade began: the meta line keeps its overrule item as it was until both are over.
    private func holdMeta(_ held: Bool) {
        guard held, let snapshot: GroupSnapshot = store.snapshots[id],
              let summary: GroupSummary = store.summary(for: id) else {
            heldOverrule = nil
            return
        }
        heldOverrule = yesterdayOverruled(snapshot, summary: summary, now: Date())
    }

    /// A lift before completion that was not a scroll: the caption teaches the gesture.
    private func earlyRelease() {
        hintTask?.cancel()
        withAnimation(Anim.fade) { hintFlash = true }
        hintTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Anim.hintNanos)
            if Task.isCancelled { return }
            withAnimation(Anim.fade) { hintFlash = false }
        }
    }

    /// On disappear (another tab, another group, leave) and on an id change: no task survives, the
    /// room is lit.
    private func resetChoreography() {
        dimTask?.cancel()
        dimTask = nil
        hintTask?.cancel()
        hintTask = nil
        hintFlash = false
        awaitingSeal = false
        deliverPendingKeep()
        finishBeats()
        if roomDimmed {
            roomDimmed = false
        }
    }
}

/// Your proof posts for one day, as Home's foot shows them.
private struct DayProof {
    /// The posts still uploading; empty when none is.
    private(set) var sending: [String] = []
    /// One that failed to send.
    private(set) var failedID: String? = nil
    private(set) var sent: Bool = false

    init(_ snapshot: GroupSnapshot, author: String, day: Int, failed: Set<String>) {
        for post in snapshot.posts where post.isProof && post.authorID == author && post.day == day {
            guard post.epoch == snapshot.group.epoch else { continue }
            if post.serverDate != nil {
                sent = true
            } else if failed.contains(post.id) {
                failedID = post.id
            } else {
                sending.append(post.id)
            }
        }
    }
}
