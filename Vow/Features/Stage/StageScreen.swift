import SwiftUI
import Accessibility

/// Callbacks from a stage to MainView (which owns the sheets, navigation, the bar and the dock).
struct StageActions {
    let editVow: () -> Void
    let invite: () -> Void
    let showMember: (String) -> Void
    let showActivity: () -> Void
    /// At the seal: MainView keeps this vow's dock chip unlit until didLight.
    let willLight: () -> Void
    /// At the social beat, and on revert, cancel or disappear: the dock chip may light.
    let didLight: () -> Void
    /// Seal + 2.0 s: pulse the next open vow in the dock.
    let didKeep: () -> Void
    /// Seal + 2.3 s: the one-time reminder offer (MainView checks it is due).
    let offerReminder: () -> Void
}

/// Where the cascade after a seal has got to (§7). `.done` is the resting state: everything shows
/// the store's values. Compared through `rawValue`.
enum KeepBeat: Int {
    case sealed = 1, settled, rewarded, social, done
}

/// One vow's stage (member, not-a-member or loading), its details, the check-in choreography,
/// the test controls, the leave/delete dialogs and the 60 s refresh.
struct StageScreen: View {
    let id: GroupID
    @Binding var roomDimmed: Bool
    let metrics: StageMetrics
    let scrollToTopToken: Int
    let actions: StageActions

    @Environment(AppStore.self) private var store
    // Dialogs and test controls
    @State private var confirmLeave: Bool = false
    @State private var confirmDelete: Bool = false
    @State private var confirmReset: Bool = false
    @State private var testBusy: Bool = false
    // Check-in choreography
    @State private var dimTask: Task<Void, Never>? = nil
    @State private var beatTask: Task<Void, Never>? = nil
    @State private var hintTask: Task<Void, Never>? = nil
    @State private var tagTask: Task<Void, Never>? = nil
    @State private var awaitingSeal: Bool = false
    @State private var beat: KeepBeat = .done
    @State private var heldStreak: Int = 0
    @State private var flareToken: Int = 0
    @State private var rewardToken: Int = 0
    @State private var milestoneToken: Int = 0
    @State private var milestone: StreakEvent? = nil
    @State private var hintFlash: Bool = false

    init(id: GroupID, roomDimmed: Binding<Bool>, metrics: StageMetrics, scrollToTopToken: Int, actions: StageActions) {
        self.id = id
        self._roomDimmed = roomDimmed
        self.metrics = metrics
        self.scrollToTopToken = scrollToTopToken
        self.actions = actions
    }

    private static let topID: String = "stage-top"
    private static let refreshNanos: UInt64 = 60_000_000_000
    /// Compact screens: the milestone tag covers the strip label for this long, then the label returns.
    private static let compactTagNanos: UInt64 = 3_000_000_000

    var body: some View {
        timeline
            .confirmationDialog(leaveTitle, isPresented: $confirmLeave, titleVisibility: .visible) {
                Button("Leave group", role: .destructive) {
                    Task { await store.leave(id) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You stop staking from today. Your past days stay in the group's activity.")
            }
            .confirmationDialog(deleteTitle, isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete group", role: .destructive) {
                    Task { await store.deleteGroup(id) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This deletes the group and its history for everyone. You can't undo it.")
            }
            .confirmationDialog("Reset this test group?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Reset group", role: .destructive) {
                    runTest { await store.resetTestGroup(id) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Everyone starts over from day 1. Check-ins, streaks and points are cleared.")
            }
    }

    /// The stage on a per-minute clock (caption, at-risk rings and the day roll over on time), with
    /// the refresh loop, the reward haptics and the cleanup hooks.
    private var timeline: some View {
        TimelineView(.everyMinute) { context in
            stage(now: context.date)
        }
        .vowBackground()
        .task(id: id) {
            await refreshLoop()
        }
        .sensoryFeedback(.impact(weight: .light, intensity: 0.7), trigger: rewardToken)
        .sensoryFeedback(.success, trigger: milestoneToken)
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
            loaded(group: snapshot.group, summary: summary, now: now)
        } else {
            ProgressView()
                .tint(Ink.text3)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func loaded(group: GroupInfo, summary: GroupSummary, now: Date) -> some View {
        let sealed: Bool = summary.viewer?.checkedInToday ?? false
        let orbKey: String = StageScreen.orbKey(group: group, summary: summary)
        return ScrollViewReader { (proxy: ScrollViewProxy) in
            ScrollView(.vertical, showsIndicators: false) {
                column(group: group, summary: summary, now: now)
            }
            .refreshable {
                await store.refreshAll()
            }
            .onChange(of: scrollToTopToken) { _, _ in
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

    private func column(group: GroupInfo, summary: GroupSummary, now: Date) -> some View {
        VStack(spacing: 0) {
            banner
            header(group: group, summary: summary)
            if let viewer: MemberStanding = summary.viewer {
                memberBody(group: group, summary: summary, viewer: viewer, now: now)
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
        .padding(.bottom, Gap.xxl)
        .id(StageScreen.topID)
    }

    /// Only with cached groups (the stage exists); without them RootView shows the problem screen.
    @ViewBuilder
    private var banner: some View {
        if let message: String = failureMessage {
            InlineBanner(systemImage: "exclamationmark.icloud", text: message, actionTitle: "Try again") {
                Task { await store.bootstrap() }
            }
            .padding(.horizontal, Gap.l)
            .padding(.top, Gap.xs)
            .roomDim(roomDimmed)
        }
    }

    private func header(group: GroupInfo, summary: GroupSummary) -> some View {
        StageHeader(group: group,
                    summary: summary,
                    isMember: summary.viewer != nil,
                    isOwner: store.isOwner(id),
                    canAdvance: isTestOwner(group),
                    testBusy: testBusy,
                    onEditVow: actions.editVow,
                    onInvite: actions.invite,
                    onRefresh: { Task { await store.refresh(id) } },
                    onNextDay: advanceDay,
                    onResetGroup: { confirmReset = true },
                    onLeave: { confirmLeave = true },
                    onDelete: { confirmDelete = true })
            .roomDim(roomDimmed)
    }

    /// The center keeps zIndex 1 so the orb's burst draws over the test bar and the details.
    private func memberBody(group: GroupInfo, summary: GroupSummary, viewer: MemberStanding, now: Date) -> some View {
        let lit: Bool = viewerLit(viewer)
        let canAdvance: Bool = isTestOwner(group)
        return VStack(spacing: 0) {
            center(group: group, summary: summary, viewer: viewer, lit: lit, now: now)
                .zIndex(1)
            if canAdvance {
                TestDayBar(metrics: metrics, busy: testBusy, onNextDay: advanceDay, onReset: { confirmReset = true })
                    .padding(.top, metrics.compact ? 36 : Gap.l)
                    .roomDim(roomDimmed)
            }
            details(group: group, summary: summary, viewer: viewer, lit: lit, canAdvance: canAdvance)
        }
    }

    private func center(group: GroupInfo, summary: GroupSummary, viewer: MemberStanding, lit: Bool, now: Date) -> some View {
        StageCenter(group: group,
                    summary: summary,
                    viewer: viewer,
                    theme: Overview.theme(summary),
                    viewerID: store.userID ?? "",
                    metrics: metrics,
                    now: now,
                    roomDimmed: roomDimmed,
                    shownStreak: shownStreak(viewer),
                    captionKept: captionKept(viewer),
                    viewerLit: lit,
                    hintFlash: hintFlash,
                    flareToken: flareToken,
                    milestone: milestone,
                    milestoneToken: milestoneToken,
                    onSealed: handleSealed,
                    onFocusChange: focusChanged,
                    onEarlyRelease: earlyRelease,
                    onEditVow: actions.editVow,
                    onMember: actions.showMember,
                    onInvite: actions.invite)
    }

    private func details(group: GroupInfo, summary: GroupSummary, viewer: MemberStanding, lit: Bool, canAdvance: Bool) -> some View {
        VStack(spacing: Gap.section) {
            ProgressCard(viewer: viewer, summary: summary, todayLit: lit)
            MembersCard(summary: summary, viewerID: store.userID ?? "", viewerLit: lit, onSelect: actions.showMember)
            ActivityPreviewCard(group: group, summary: summary, canAdvance: canAdvance, onShowAll: actions.showActivity)
        }
        .padding(.horizontal, Gap.gutter)
        .padding(.top, metrics.detailsTop)
        .roomDim(roomDimmed)
    }

    // MARK: - Derived

    private var failureMessage: String? {
        if case .failed(let message) = store.phase {
            return message
        }
        return nil
    }

    private var groupName: String {
        store.snapshots[id]?.group.name ?? "this group"
    }

    private var leaveTitle: String {
        "Leave \(groupName)?"
    }

    private var deleteTitle: String {
        "Delete \(groupName)?"
    }

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

    /// Your sphere, today's bead and your members row light together at the social beat.
    private func viewerLit(_ viewer: MemberStanding) -> Bool {
        viewer.checkedInToday && beat.rawValue >= KeepBeat.social.rawValue
    }

    // MARK: - Refresh and test controls

    private func refreshLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: StageScreen.refreshNanos)
            if Task.isCancelled { break }
            await store.refresh(id)
        }
    }

    private func advanceDay() {
        runTest { await store.advanceTestDay(id) }
    }

    /// One test action at a time, from the bar or the title menu.
    private func runTest(_ work: @escaping @MainActor () async -> Void) {
        guard !testBusy else { return }
        testBusy = true
        Task { @MainActor in
            await work()
            testBusy = false
        }
    }

    // MARK: - Check-in choreography (§7)

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
        actions.willLight()
        Task { @MainActor in
            await store.checkIn(id)
            awaitingSeal = false
            if beatTask == nil && beat == .sealed {
                beat = .done
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

    /// Seal + 0.12 settle, 0.25 reward, 0.45 social, 0.7 milestone, 2.0 next vow, 2.3 reminder offer.
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
        let compact: Bool = metrics.compact
        let isTest: Bool = store.snapshots[id]?.group.isTest ?? true
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
                showMilestone(e, compact: compact)
            }
            beat = .done

            try? await Task.sleep(nanoseconds: Anim.nextNanos - Anim.milestoneNanos)
            if Task.isCancelled { return }
            actions.didKeep()

            try? await Task.sleep(nanoseconds: Anim.offerNanos - Anim.nextNanos)
            if Task.isCancelled { return }
            if !isTest {
                actions.offerReminder()
            }
            beatTask = nil
        }
    }

    /// Embers, the tag in its reserved gap and the success haptic. Compact: the tag leaves after 3 s.
    private func showMilestone(_ event: StreakEvent, compact: Bool) {
        withAnimation(Anim.reward) { milestone = event }
        milestoneToken += 1
        tagTask?.cancel()
        tagTask = nil
        guard compact else { return }
        tagTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: StageScreen.compactTagNanos)
            if Task.isCancelled { return }
            withAnimation(Anim.fade) { milestone = nil }
            tagTask = nil
        }
    }

    /// Ends the cascade wherever it is: everything shows the store's values and the dock chip may light.
    private func finishBeats() {
        beatTask?.cancel()
        beatTask = nil
        if let task: Task<Void, Never> = tagTask {
            // The compact tag covers the strip label; never leave it there.
            task.cancel()
            tagTask = nil
            milestone = nil
        }
        beat = .done
        actions.didLight()
    }

    private func dayChanged() {
        tagTask?.cancel()
        tagTask = nil
        milestone = nil
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

    /// On disappear (vow switch, push, leave) and on an id change: no task survives, the room is lit.
    private func resetChoreography() {
        dimTask?.cancel()
        dimTask = nil
        hintTask?.cancel()
        hintTask = nil
        hintFlash = false
        awaitingSeal = false
        finishBeats()
        if roomDimmed {
            roomDimmed = false
        }
    }
}
