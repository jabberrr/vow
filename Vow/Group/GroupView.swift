import SwiftUI
import Accessibility

/// One group. Owns the check-in choreography (room dim gate, settle and reward beats, hint flash),
/// the inline nav title, the sheets, the confirmation dialogs and the 60 s auto-refresh.
struct GroupView: View {
    let id: GroupID

    @Environment(AppStore.self) private var store
    @State private var showVowPrompt: Bool = false
    @State private var showInvite: Bool = false
    @State private var confirmLeave: Bool = false
    @State private var confirmDelete: Bool = false
    // Check-in choreography
    @State private var roomDimmed: Bool = false
    @State private var dimTask: Task<Void, Never>? = nil
    @State private var awaitingSeal: Bool = false
    @State private var settleToken: Int = 0
    @State private var rewardToken: Int = 0
    @State private var rewardTask: Task<Void, Never>? = nil
    @State private var hintFlash: Bool = false
    @State private var hintTask: Task<Void, Never>? = nil
    // Nav bar title once the header scrolls away
    @State private var showInlineTitle: Bool = false
    @State private var headerRestMinY: CGFloat? = nil

    static let scrollSpace: String = "groupScroll"
    /// The "Checked in" bounce waits until its label and the room are mostly lit (the reward stays at 0.25 s).
    private static let settleDelayNanos: UInt64 = 120_000_000

    private var groupName: String {
        store.snapshots[id]?.group.name ?? "this group"
    }

    private var isOwner: Bool {
        store.isOwner(id)
    }

    private var isActiveMember: Bool {
        guard let member = store.myMember(id) else { return false }
        return member.leftDay == nil
    }

    private var showsTestBar: Bool {
        guard let group = store.snapshots[id]?.group else { return false }
        return store.testingMode && group.isTest && isOwner
    }

    private var viewerSealed: Bool {
        store.summary(for: id)?.viewer?.checkedInToday ?? false
    }

    var body: some View {
        screen
            .sheet(isPresented: $showVowPrompt) {
                VowPromptSheet(id: id)
                    .environment(store)
            }
            .sheet(isPresented: $showInvite) {
                InviteSheet(id: id)
                    .environment(store)
            }
            .confirmationDialog("Leave \(groupName)?", isPresented: $confirmLeave, titleVisibility: .visible) {
                Button("Leave group", role: .destructive) {
                    Task { await store.leave(id) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You stop staking from today. Your past days stay in the group's activity.")
            }
            .confirmationDialog("Delete \(groupName)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete group", role: .destructive) {
                    Task { await store.deleteGroup(id) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This deletes the group and its history for everyone. You can't undo it.")
            }
            .task(id: id) {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 60_000_000_000)
                    if Task.isCancelled { break }
                    await store.refresh(id)
                }
            }
    }

    /// Background, content, test bar, nav chrome and the check-in side effects.
    private var screen: some View {
        ZStack {
            Palette.bg.ignoresSafeArea()
            content
        }
        .safeAreaInset(edge: .bottom) {
            if showsTestBar {
                TestBar(id: id)
                    .focusDimmed(roomDimmed)
            }
        }
        // Empty at rest (the header shows the name); the default bar background appears on scroll.
        .navigationTitle(showInlineTitle ? groupName : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarRole(.editor)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                inviteButton
                menu
            }
        }
        .sensoryFeedback(.impact(weight: .light, intensity: 0.7), trigger: rewardToken)
        .onChange(of: viewerSealed) { oldValue, newValue in
            sealedChanged(from: oldValue, to: newValue)
        }
        .onDisappear {
            dimTask?.cancel()
            rewardTask?.cancel()
            hintTask?.cancel()
            roomDimmed = false
            hintFlash = false
        }
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot = store.snapshots[id], let summary = store.summary(for: id) {
            ScrollView(.vertical, showsIndicators: false) {
                GroupColumn(id: id,
                            group: snapshot.group,
                            summary: summary,
                            theme: store.theme(for: id),
                            viewerID: store.userID ?? "",
                            roomDimmed: roomDimmed,
                            hintFlash: hintFlash,
                            settleToken: settleToken,
                            rewardToken: rewardToken,
                            canAdvance: showsTestBar,
                            onSealed: handleSealed,
                            onFocusChange: focusChanged,
                            onEarlyRelease: earlyRelease,
                            onEditVow: { showVowPrompt = true },
                            onInvite: { showInvite = true })
            }
            .coordinateSpace(.named(GroupView.scrollSpace))
            .refreshable {
                await store.refresh(id)
            }
            .onPreferenceChange(GroupHeaderFrameKey.self) { frame in
                // The Xcode 16 SDK makes this closure @Sendable (nonisolated); SwiftUI calls it on main.
                MainActor.assumeIsolated {
                    headerMoved(frame)
                }
            }
        } else {
            ProgressView()
                .tint(Palette.text3)
        }
    }

    // MARK: - Toolbar (plain system items, never dimmed)

    private var inviteButton: some View {
        Button {
            showInvite = true
        } label: {
            Image(systemName: "person.badge.plus")
        }
        .accessibilityLabel("Invite")
    }

    private var menu: some View {
        Menu {
            Button {
                showVowPrompt = true
            } label: {
                Label(isActiveMember ? "Edit vow" : "Set vow", systemImage: "pencil")
            }
            Button {
                Task { await store.refresh(id) }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            Divider()
            destructiveItem
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("More")
    }

    @ViewBuilder
    private var destructiveItem: some View {
        if isOwner {
            Button(role: .destructive) {
                confirmDelete = true
            } label: {
                Label("Delete group", systemImage: "trash")
            }
        } else {
            Button(role: .destructive) {
                confirmLeave = true
            } label: {
                Label("Leave group", systemImage: "rectangle.portrait.and.arrow.right")
            }
        }
    }

    // MARK: - Check-in choreography

    /// OrbView reports focus. The room only dims after 200 ms of steady pressure; release, movement
    /// or a scroll before then cancels it, so taps and scrolls never change the room.
    private func focusChanged(_ on: Bool) {
        dimTask?.cancel()
        dimTask = nil
        if on {
            dimTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: Motion.dimGateNanos)
                if Task.isCancelled { return }
                withAnimation(Motion.dimIn) { roomDimmed = true }
            }
        } else if roomDimmed {
            // Focus ends at the seal (fast lights-up) or on an early release (slower recovery).
            withAnimation(viewerSealed ? Motion.lightsUp : Motion.dimOut) { roomDimmed = false }
        }
    }

    /// OrbView's onSealed (0.9 s after completion, or VoiceOver's "Check in" action). The settle and
    /// reward beats are driven by the sealed transition below, once the optimistic check-in lands.
    private func handleSealed() {
        awaitingSeal = true
        Task { @MainActor in
            await store.checkIn(id)
            // The seal path already cleared it; a check-in that never sealed must not reward a later one.
            awaitingSeal = false
        }
    }

    /// Seal + 0.12 s: the checkmark bounces (its label and the room are nearly lit) and VoiceOver hears
    /// "Checked in". Seal + 0.25 s: the reward lands, ripple and light haptic, together with the streak
    /// roll and bead fill (those animate on `Motion.reward`, which carries the same 0.25 s delay).
    private func sealedChanged(from oldValue: Bool, to newValue: Bool) {
        if oldValue && !newValue {
            // A failed check-in reverted (or a new day began): no reward for it.
            rewardTask?.cancel()
            rewardTask = nil
            return
        }
        guard !oldValue, newValue, awaitingSeal else { return }
        awaitingSeal = false
        rewardTask?.cancel()
        rewardTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: GroupView.settleDelayNanos)
            if Task.isCancelled { return }
            settleToken += 1
            let announcement: String = "Checked in"
            AccessibilityNotification.Announcement(announcement).post()
            try? await Task.sleep(nanoseconds: Motion.rewardDelayNanos - GroupView.settleDelayNanos)
            if Task.isCancelled { return }
            rewardToken += 1
        }
    }

    /// A release before completion that was not a scroll: flash the instruction in accent.
    private func earlyRelease() {
        hintTask?.cancel()
        withAnimation(Motion.fade) { hintFlash = true }
        hintTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Motion.hintNanos)
            if Task.isCancelled { return }
            withAnimation(Motion.fade) { hintFlash = false }
        }
    }

    /// Shows the group name in the nav bar once the header has scrolled fully above its resting place.
    private func headerMoved(_ frame: CGRect) {
        guard frame != .zero else { return }
        if headerRestMinY == nil {
            headerRestMinY = frame.minY
        }
        let show: Bool = frame.maxY < (headerRestMinY ?? frame.minY)
        if show != showInlineTitle {
            withAnimation(Motion.fade) { showInlineTitle = show }
        }
    }
}
