import SwiftUI

/// The one sheet MainView shows at a time.
enum MainSheet: Identifiable, Equatable {
    case menu
    case settings
    case create
    case join
    case reminderOffer
    case invite(GroupID)
    case vow(GroupID)
    case member(GroupID, String)

    var id: String {
        switch self {
        case .menu: return "menu"
        case .settings: return "settings"
        case .create: return "create"
        case .join: return "join"
        case .reminderOffer: return "reminderOffer"
        case .invite(let g): return "invite-" + g.zoneName
        case .vow(let g): return "vow-" + g.zoneName
        case .member(let g, let u): return "member-" + g.zoneName + "-" + u
        }
    }
}

/// The app with a profile: the pinned global bar, the selected vow's stage (or the empty stage),
/// the dock of vows, every sheet (one at a time, through `present`) and the Activity push.
struct MainView: View {
    @Binding var roomDimmed: Bool

    @Environment(AppStore.self) private var store
    @Environment(ReminderCenter.self) private var reminders
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var path: [GroupID] = []
    @State private var selected: GroupID? = nil
    /// What `.sheet(item:)` shows.
    @State private var sheet: MainSheet? = nil
    /// Non-nil from `present` until `onDismiss`: a sheet is up or still animating out.
    @State private var showing: MainSheet? = nil
    /// Presented by `sheetDismissed` once the current sheet is gone.
    @State private var nextSheet: MainSheet? = nil
    @State private var scrollToTopToken: Int = 0
    @State private var pulseID: GroupID? = nil
    @State private var pulseToken: Int = 0
    /// The vow sealed on the stage; its dock chip stays unlit until the social beat.
    @State private var holdingLightID: GroupID? = nil
    @State private var backgroundedAt: Date? = nil
    @State private var reminderKey: String = ""
    @State private var didAppear: Bool = false
    /// False until RootView's crossfade has finished: no vow prompt rises mid-transition.
    @State private var promptReady: Bool = false
    /// The summaries between renders; a reference, so filling it never re-renders.
    @State private var memo: SummaryMemo = SummaryMemo()

    private let prefs: Preferences = Preferences()

    /// RootView's screen crossfade (`Anim.screen`). The first vow prompt waits for it.
    private static let crossfadeNanos: UInt64 = 350_000_000
    /// Back from the background after this long: an open vow is chosen again.
    private static let reselectAfter: TimeInterval = 600

    init(roomDimmed: Binding<Bool>) {
        self._roomDimmed = roomDimmed
    }

    var body: some View {
        storeHooks
    }

    // MARK: Layout

    /// `all` is computed once per minute or store change and passed down; the keyboard of a sheet
    /// never changes the metrics or lifts the dock behind it.
    private var shell: some View {
        TimelineView(.everyMinute) { context in
            GeometryReader { proxy in
                screen(all: memo.summaries(store, now: context.date),
                       metrics: StageMetrics.forHeight(proxy.size.height),
                       now: context.date)
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
    }

    private func screen(all: [GroupID: GroupSummary], metrics: StageMetrics, now: Date) -> some View {
        NavigationStack(path: $path) {
            root(metrics: metrics)
                .safeAreaInset(edge: .top, spacing: 0) {
                    bar(all: all, metrics: metrics)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    dockBand(all: all, metrics: metrics, now: now)
                }
        }
    }

    private func root(metrics: StageMetrics) -> some View {
        stageView(metrics: metrics)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Ink.bg.ignoresSafeArea())
            // Not displayed; names the way back from Activity for VoiceOver.
            .navigationTitle(rootTitle)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: GroupID.self) { gid in
                ActivityScreen(id: gid)
            }
    }

    @ViewBuilder
    private func stageView(metrics: StageMetrics) -> some View {
        if let id = selected, store.snapshots[id] != nil {
            StageScreen(id: id,
                        roomDimmed: $roomDimmed,
                        metrics: metrics,
                        scrollToTopToken: scrollToTopToken,
                        actions: stageActions(id))
                .id(id)
                .transition(.opacity)
        } else if store.groupIDs.isEmpty {
            if store.isRefreshing && store.lastSyncedAt == nil {
                ProgressView()
                    .tint(Ink.text3)
            } else {
                EmptyStage(metrics: metrics, onCreate: { present(.create) }, onJoin: { present(.join) })
            }
        } else {
            ProgressView()
                .tint(Ink.text3)
        }
    }

    private var rootTitle: String {
        guard let id = selected, let group = store.snapshots[id]?.group else { return "Vow" }
        return group.name
    }

    private func bar(all: [GroupID: GroupSummary], metrics: StageMetrics) -> some View {
        GlobalBar(metrics: metrics,
                  balance: Overview.balance(all),
                  yesterday: Overview.yesterdayChange(all, tests: store.testGroupIDs),
                  dimmed: roomDimmed,
                  canReveal: showing == nil && sheet == nil && !roomDimmed,
                  onMenu: { present(.menu) },
                  onSettings: { present(.settings) })
            .background(Ink.bg.ignoresSafeArea(edges: .top))
    }

    /// A short fade, then a solid band: nothing shows through around the dock.
    @ViewBuilder
    private func dockBand(all: [GroupID: GroupSummary], metrics: StageMetrics, now: Date) -> some View {
        if !store.groupIDs.isEmpty {
            VStack(spacing: 0) {
                LinearGradient(colors: [Ink.bg.opacity(0), Ink.bg], startPoint: .top, endPoint: .bottom)
                    .frame(height: metrics.dockFade)
                    .allowsHitTesting(false)
                dock(all: all, now: now)
                    .padding(.horizontal, Gap.barInset)
                    .padding(.bottom, Gap.s)
                    .background(Ink.bg.ignoresSafeArea(edges: .bottom))
            }
        }
    }

    private func dock(all: [GroupID: GroupSummary], now: Date) -> some View {
        VowDock(all: all,
                selected: selected,
                holdingLightID: holdingLightID,
                pulseID: pulseID,
                pulseToken: pulseToken,
                now: now,
                dimmed: roomDimmed,
                onSelect: { id in dockSelect(id) },
                onCreate: { present(.create) },
                onJoin: { present(.join) })
    }

    // MARK: Sheets

    private var withSheet: some View {
        shell
            .sheet(item: $sheet, onDismiss: { sheetDismissed() }) { item in
                sheetContent(item)
            }
    }

    private func sheetContent(_ item: MainSheet) -> some View {
        sheetBody(item)
            .environment(store)
            .environment(reminders)
    }

    @ViewBuilder
    private func sheetBody(_ item: MainSheet) -> some View {
        switch item {
        case .menu:
            MenuSheet(onSelectVow: { id in openFromMenu(id) },
                      onCreate: { present(.create) },
                      onJoin: { present(.join) },
                      onSettings: { present(.settings) })
                .vowSheet([.large])
        case .settings:
            SettingsSheet()
                .vowSheet([.large])
        case .create:
            NewGroupSheet(onCreated: { id in groupCreated(id) })
                .vowSheet([.large])
        case .join:
            JoinLinkSheet()
                .vowSheet([.medium, .large])
        case .invite(let id):
            InviteLinkSheet(id: id)
                .vowSheet([.medium, .large])
        case .vow(let id):
            VowSheet(id: id)
                .vowSheet([.medium, .large])
        case .member(let id, let userID):
            MemberSheet(id: id, userID: userID, onEditVow: { present(.vow(id)) })
                .vowSheet([.medium, .large])
        case .reminderOffer:
            ReminderOfferSheet()
                .vowSheet([.height(380), .large])
        }
    }

    /// Shows `s` now when nothing is up or animating out; otherwise queues it and closes the current one.
    private func present(_ s: MainSheet) {
        if showing == nil && sheet == nil {
            showing = s
            sheet = s
        } else {
            nextSheet = s
            sheet = nil
        }
    }

    private func sheetDismissed() {
        let closed: MainSheet? = showing
        showing = nil
        // Closing the vow prompt without saving: the not-a-member stage offers it again.
        if case .vow(let id)? = closed, store.pendingVowPrompt == id {
            store.pendingVowPrompt = nil
        }
        if let next: MainSheet = nextSheet {
            nextSheet = nil
            present(next)
        } else {
            presentPendingVowIfIdle()
        }
    }

    private func openFromMenu(_ id: GroupID) {
        select(id)
        sheet = nil
    }

    /// Create → invite → the new vow's stage. Through `present`: if the create sheet is already
    /// gone the invite shows now, otherwise it follows the create sheet's dismissal.
    private func groupCreated(_ id: GroupID) {
        select(id)
        present(.invite(id))
    }

    // MARK: Lifecycle

    private var appearanceHooks: some View {
        withSheet
            .onAppear {
                firstAppear()
            }
            .task {
                await presentFirstPrompt()
            }
            .onChange(of: scenePhase) { _, phase in
                scenePhaseChanged(phase)
            }
            .onChange(of: roomDimmed) {
                presentPendingVowIfIdle()
            }
            .onChange(of: holdingLightID) {
                presentPendingVowIfIdle()
                if holdingLightID == nil {
                    syncReminders(force: false)
                }
            }
    }

    private var storeHooks: some View {
        appearanceHooks
            .onChange(of: store.groupIDs) {
                validateSelection()
                handleOpenRequest()
            }
            .onChange(of: store.pendingVowPrompt) {
                presentPendingVowIfIdle()
            }
            .onChange(of: store.acceptCount) {
                inviteAccepted()
            }
            .onChange(of: store.lastSyncedAt) {
                handleOpenRequest()
            }
            .onChange(of: reminders.openRequest) {
                handleOpenRequest()
            }
            .onChange(of: store.snapshots, initial: true) {
                if holdingLightID == nil {
                    syncReminders(force: false)
                }
            }
    }

    /// Once per MainView: the cold launch from a reminder tap is handled here.
    private func firstAppear() {
        guard !didAppear else { return }
        didAppear = true
        chooseSelection(force: true)
        handleOpenRequest()
    }

    /// A link accepted during onboarding or launch: the vow prompt rises once the screen has
    /// crossfaded in (presenting mid-transition is not relied on).
    @MainActor
    private func presentFirstPrompt() async {
        try? await Task.sleep(nanoseconds: MainView.crossfadeNanos)
        if Task.isCancelled { return }
        promptReady = true
        presentPendingVowIfIdle()
    }

    private func scenePhaseChanged(_ phase: ScenePhase) {
        if phase == .background {
            backgroundedAt = Date()
        }
        if phase == .active {
            if let since: Date = backgroundedAt, Date().timeIntervalSince(since) >= MainView.reselectAfter {
                chooseSelection(force: true)
            }
            backgroundedAt = nil
            syncReminders(force: true)
        }
    }

    /// A hold or the reward cascade is running on the stage: never switch the vow under it.
    private var stageBusy: Bool {
        roomDimmed || holdingLightID != nil
    }

    private func presentPendingVowIfIdle() {
        guard promptReady, !stageBusy, showing == nil, sheet == nil,
              let p: GroupID = store.pendingVowPrompt, store.snapshots[p] != nil else { return }
        select(p)
        present(.vow(p))
    }

    /// Already a member (no prompt): show that vow, under the store's toast.
    private func inviteAccepted() {
        guard !stageBusy, let id: GroupID = store.lastAcceptedGroup, store.pendingVowPrompt != id else { return }
        select(id)
    }

    /// A reminder tap. Kept until the group exists; dropped once a sync finished without it.
    private func handleOpenRequest() {
        guard let id: GroupID = reminders.openRequest else { return }
        guard store.snapshots[id] != nil else {
            if store.lastSyncedAt != nil {
                reminders.openRequest = nil
            }
            return
        }
        reminders.openRequest = nil
        nextSheet = nil
        sheet = nil
        path = []
        select(id)
    }

    // MARK: Selection

    private func select(_ id: GroupID) {
        guard store.snapshots[id] != nil else { return }
        if selected != id {
            let animation: Animation? = reduceMotion ? nil : Anim.switchVow
            withAnimation(animation) {
                selected = id
            }
        }
        if !path.isEmpty {
            path = []
        }
        prefs.saveLastVowZone(id.zoneName)
    }

    /// Forced: move to the most urgent open vow only when the shown vow is not open (kept, not a
    /// member, or gone); an open vow is never replaced. Nothing valid shown: most urgent open vow,
    /// else the last one viewed, else the first group.
    private func chooseSelection(force: Bool) {
        var current: GroupID? = nil
        if let id = selected, store.snapshots[id] != nil {
            current = id
        }
        guard force || current == nil else { return }
        let all: [GroupID: GroupSummary] = store.summaries()
        let urgent: GroupID? = store.mostUrgentGroupID(in: all)
        if force, let target = urgent, target != current {
            var currentIsOpen: Bool = false
            if let id = current, let summary = all[id] {
                currentIsOpen = Digest.isOpen(summary)
            }
            if !currentIsOpen {
                select(target)
                return
            }
        }
        if current == nil, let fallback = urgent ?? lastViewed() ?? store.groupIDs.first {
            select(fallback)
        }
    }

    private func lastViewed() -> GroupID? {
        guard let zone: String = prefs.loadLastVowZone() else { return nil }
        return store.groupIDs.first(where: { $0.zoneName == zone })
    }

    private func validateSelection() {
        let ids: [GroupID] = store.groupIDs
        if path.contains(where: { !ids.contains($0) }) {
            path.removeAll(where: { !ids.contains($0) })
        }
        chooseSelection(force: false)
    }

    /// Re-tapping the shown vow scrolls its stage to the top.
    private func dockSelect(_ id: GroupID) {
        if id == selected {
            scrollToTopToken += 1
        } else {
            select(id)
        }
    }

    // MARK: Stage callbacks

    private func stageActions(_ id: GroupID) -> StageActions {
        StageActions(
            editVow: { present(.vow(id)) },
            invite: { present(.invite(id)) },
            showMember: { userID in present(.member(id, userID)) },
            showActivity: { path.append(id) },
            willLight: { holdingLightID = id },
            didLight: { lightReleased(id) },
            didKeep: { pulseNextVow(after: id) },
            offerReminder: { offerReminderIfDue() }
        )
    }

    private func lightReleased(_ id: GroupID) {
        if holdingLightID == id {
            holdingLightID = nil
        }
    }

    private func pulseNextVow(after id: GroupID) {
        let next: GroupID? = store.mostUrgentGroupID(in: store.summaries(), excluding: id)
        pulseID = next
        if next != nil {
            pulseToken += 1
        }
    }

    /// Only once the day's vows are done (no next-vow pulse), and only with a real vow to remind.
    private func offerReminderIfDue() {
        guard pulseID == nil, showing == nil, sheet == nil, reminders.shouldOffer else { return }
        guard !store.reminderGroups(store.summaries()).isEmpty else { return }
        present(.reminderOffer)
    }

    // MARK: Reminders

    /// Callers skip it while `holdingLightID` is set; the seal syncs once the cascade has lit its dock chip.
    private func syncReminders(force: Bool) {
        let groups: [ReminderGroup] = store.reminderGroups(memo.summaries(store, now: Date()))
        let key: String = ReminderPlan.signature(groups)
        if !force && key == reminderKey {
            return
        }
        reminderKey = key
        reminders.sync(groups: groups, now: Date())
    }
}

/// One Settlement pass per (snapshots, groups, user, minute), not per MainView render.
@MainActor
final class SummaryMemo {
    private var snapshots: [GroupID: GroupSnapshot]? = nil
    private var order: [GroupID] = []
    private var userID: String? = nil
    private var minute: Int = Int.min
    private var value: [GroupID: GroupSummary] = [:]

    func summaries(_ store: AppStore, now: Date) -> [GroupID: GroupSummary] {
        let m: Int = Int(now.timeIntervalSince1970 / 60)
        if m == minute, userID == store.userID, order == store.groupIDs,
           let cached: [GroupID: GroupSnapshot] = snapshots, cached == store.snapshots {
            return value
        }
        snapshots = store.snapshots
        order = store.groupIDs
        userID = store.userID
        minute = m
        value = store.summaries(now: now)
        return value
    }
}
