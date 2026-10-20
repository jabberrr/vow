import SwiftUI

/// The signed-in app, as a shell: the pinned top bar, the selected group's page for the chosen tab, the
/// tab bar and the sidebar overlay, which stays mounted and only ever slides or fades. It owns the selection, the
/// tab, the 60 s refresh, the reminder sync and the `Presenter`, whose one sheet and one confirmation
/// dialog are the only ones in the main experience: pages and chrome ask for them through closures.
struct MainView: View {
    @Binding var roomDimmed: Bool
    /// A sheet, a dialog or the sidebar is up: RootView's toast waits briefly, then it is dropped.
    @Binding var toastBlocked: Bool
    /// The top bar's measured height (its banner included): the toast sits below it.
    @Binding var topBarHeight: CGFloat

    @Environment(AppStore.self) private var store: AppStore
    @Environment(ReminderCenter.self) private var reminders: ReminderCenter
    @Environment(\.scenePhase) private var scenePhase: ScenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion: Bool

    @State private var presenter: Presenter = Presenter()
    @State private var selected: GroupID? = nil
    @State private var tab: MainTab = .home
    /// Bumped when the selected tab is tapped again: its page scrolls to the top.
    @State private var topToken: Int = 0
    @State private var sidebarOpen: Bool = false
    /// A swipe from the leading edge while the panel follows it. Gesture state, like `closeDrag`: a
    /// cancelled drag (a sheet or an alert taking the touch, the app going inactive) resets itself, so
    /// the panel can never be left half out.
    @GestureState(resetTransaction: Transaction(animation: Anim.sidebarIn))
    private var edgeDrag: SidebarDrag? = nil
    /// A drag on the open panel or its scrim.
    @GestureState(resetTransaction: Transaction(animation: Anim.sidebarIn))
    private var closeDrag: SidebarDrag? = nil
    /// The live drag's axis for the release decision (gesture state has reset by then). Cleared whenever
    /// no drag is live, so a drag that never reports its end can't leave it set.
    @State private var releaseAxis: DragAxis? = nil
    /// The sidebar was closed while a swipe from the edge was still under the finger: that swipe no
    /// longer shows or opens the panel. Cleared when it ends.
    @State private var edgeCancelled: Bool = false
    @State private var menuPulseToken: Int = 0
    /// The vow sealed on Home: it counts as open everywhere (sidebar, Streak tab) until the social beat.
    @State private var holdingLightID: GroupID? = nil
    @State private var backgroundedAt: Date? = nil
    /// Back from a long background while Home was busy: choose again once it is free.
    @State private var reselectPending: Bool = false
    /// An invite was accepted while Home was busy: show it once it is free.
    @State private var acceptPending: Bool = false
    @State private var reminderKey: String = ""
    @State private var didAppear: Bool = false
    /// The summaries between renders; a reference, so filling it never re-renders.
    @State private var memo: SummaryMemo = SummaryMemo()
    @State private var offerWindow: OfferWindow = OfferWindow()

    private let prefs: Preferences = Preferences()

    /// RootView's screen crossfade (`Anim.screen`): nothing is presented while the shell fades in.
    private static let crossfade: TimeInterval = 0.35
    /// The sidebar's slide, either way: a sheet asked for from the sidebar starts once the panel has gone.
    private static let sidebarSlide: TimeInterval = 0.35
    /// Back from the background after this long: an open vow is chosen again.
    private static let reselectAfter: TimeInterval = 600
    private static let refreshNanos: UInt64 = 60_000_000_000
    /// The strip along the leading edge that opens the sidebar with a swipe.
    private static let edgeWidth: CGFloat = 16

    init(roomDimmed: Binding<Bool>, toastBlocked: Binding<Bool>, topBarHeight: Binding<CGFloat>) {
        self._roomDimmed = roomDimmed
        self._toastBlocked = toastBlocked
        self._topBarHeight = topBarHeight
    }

    var body: some View {
        storeHooks
    }

    // MARK: - Layout

    /// `all` is computed once per minute or store change and passed down. A sheet's keyboard never
    /// changes the metrics or lifts the tab bar behind it, so `bottomInset` is the home indicator's.
    private var shell: some View {
        TimelineView(.everyMinute) { context in
            GeometryReader { (proxy: GeometryProxy) in
                screen(all: memo.summaries(store, now: context.date),
                       metrics: StageMetrics.forHeight(proxy.size.height),
                       panel: min(Gap.sidebarMax, proxy.size.width * 0.82),
                       bottomInset: proxy.safeAreaInsets.bottom,
                       now: context.date)
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
    }

    /// The main screen with the sidebar over it (an overlay: the page and the orb keep their place).
    private func screen(all: [GroupID: GroupSummary], metrics: StageMetrics, panel: CGFloat, bottomInset: CGFloat,
                        now: Date) -> some View {
        ZStack(alignment: .topLeading) {
            mainScreen(all: all, metrics: metrics, panel: panel, bottomInset: bottomInset, now: now)
            sidebarLayer(all: all, panel: panel, bottomInset: bottomInset, now: now)
        }
    }

    /// The page between the pinned top bar and tab bar, with the edge zone along its leading side.
    private func mainScreen(all: [GroupID: GroupSummary], metrics: StageMetrics, panel: CGFloat, bottomInset: CGFloat,
                            now: Date) -> some View {
        page(metrics: metrics)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .leading) {
                edgeZone(panel: panel)
            }
            .background(Ink.bg.ignoresSafeArea())
            .safeAreaInset(edge: .top, spacing: 0) {
                topBar(all: all, metrics: metrics, now: now)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                tabBar(all: all, bottomInset: bottomInset)
            }
    }

    private func topBar(all: [GroupID: GroupSummary], metrics: StageMetrics, now: Date) -> some View {
        TopBar(title: shownGroup?.name,
               dot: Overview.menuDot(all, groups: groupInfos, selected: selected, now: now),
               pulseToken: menuPulseToken,
               dimmed: roomDimmed,
               metrics: metrics,
               onMenu: { openSidebar() })
            .background(barHeightReader)
    }

    /// The bar's own height (row, paddings and banner), for RootView's toast.
    private var barHeightReader: some View {
        GeometryReader { (proxy: GeometryProxy) in
            Color.clear
                .onChange(of: proxy.size.height, initial: true) { (_: CGFloat, height: CGFloat) in
                    topBarHeight = height
                }
        }
    }

    /// Whenever a group's page is shown: members, not-members and finished vows alike, so the four tabs
    /// keep their places.
    @ViewBuilder
    private func tabBar(all: [GroupID: GroupSummary], bottomInset: CGFloat) -> some View {
        if let id: GroupID = shownID {
            VowTabBar(selection: tab,
                      streakLit: streakLit(id, all: all),
                      dimmed: roomDimmed,
                      bottomInset: bottomInset,
                      onSelect: { (t: MainTab) in selectTab(t) })
        }
    }

    /// The selected group's page, or the empty stage, or a spinner while the selected group (or a fresh
    /// install's first sync) loads, so a new install that does have groups never flashes "Your first vow".
    @ViewBuilder
    private func page(metrics: StageMetrics) -> some View {
        if let id: GroupID = shownID {
            tabPage(id, metrics: metrics)
                .id(id)
                .transition(.opacity)
        } else if store.groupIDs.isEmpty && !(store.isRefreshing && store.lastSyncedAt == nil) {
            EmptyStage(metrics: metrics,
                       onCreate: { presenter.present(.create, from: .screen) },
                       onJoin: { presenter.present(.join, from: .screen) })
        } else {
            ProgressView()
                .tint(Ink.text3)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Pages are swapped, not kept alive: the orb, its timers and the calendar never run off screen.
    @ViewBuilder
    private func tabPage(_ id: GroupID, metrics: StageMetrics) -> some View {
        switch tab {
        case .home:
            StageScreen(id: id, roomDimmed: $roomDimmed, metrics: metrics, topToken: topToken, actions: stageActions(id))
        case .streak:
            StreakPage(id: id, metrics: metrics, topToken: topToken, onJoin: { presenter.present(.vow(id), from: .screen) })
        case .activity:
            ActivityPage(id: id, topToken: topToken)
        case .group:
            GroupPage(id: id, topToken: topToken, actions: groupActions(id))
        }
    }

    // MARK: - Sidebar

    /// A 16 pt strip along the leading edge of the page, outside every scroll view: a clearly horizontal
    /// swipe from it opens the sidebar. Off when ≡ is (see `canOpenSidebar`) and while the sidebar is open.
    private func edgeZone(panel: CGFloat) -> some View {
        Color.clear
            .frame(width: MainView.edgeWidth)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(edgeGesture(panel: panel))
            .allowsHitTesting(!sidebarOpen && canOpenSidebar)
            .accessibilityHidden(true)
    }

    /// The scrim and the panel. Both stay mounted, so nothing is inserted or removed mid-slide: the panel's
    /// offset and the scrim's opacity follow one state, and a slide that turns around or a drag that is
    /// let go carries on from where the panel is. Both carry the close drag and take touches only while
    /// the panel is shown.
    private func sidebarLayer(all: [GroupID: GroupSummary], panel: CGFloat, bottomInset: CGFloat, now: Date) -> some View {
        ZStack(alignment: .leading) {
            scrim(panel: panel)
            sidebar(all: all, bottomInset: bottomInset, now: now)
                .frame(width: panel)
                .frame(maxHeight: .infinity)
                .offset(x: panelOffset(panel))
                .opacity(reduceMotion ? panelProgress(panel) : 1)
                .simultaneousGesture(closeGesture(panel: panel))
                .allowsHitTesting(sidebarShown)
        }
    }

    /// Over everything else, the bars included. A tap closes the sidebar.
    private func scrim(panel: CGFloat) -> some View {
        Ink.scrim
            .ignoresSafeArea()
            .opacity(panelProgress(panel))
            .contentShape(Rectangle())
            .onTapGesture {
                setSidebar(false)
            }
            .simultaneousGesture(closeGesture(panel: panel))
            .allowsHitTesting(sidebarShown)
            .accessibilityHidden(true)
    }

    private func sidebar(all: [GroupID: GroupSummary], bottomInset: CGFloat, now: Date) -> some View {
        Sidebar(all: all,
                selected: selected,
                holdingLightID: holdingLightID,
                now: now,
                isOpen: sidebarOpen,
                isShown: sidebarShown,
                canReveal: sidebarOpen && presenter.isIdle && !roomDimmed,
                bottomInset: bottomInset,
                onSelect: { (id: GroupID) in pickGroup(id) },
                onCreate: { openFromSidebar(.create) },
                onJoin: { openFromSidebar(.join) },
                onSettings: { openFromSidebar(.settings) },
                onProfile: { openFromSidebar(.profile) },
                onClose: { setSidebar(false) })
    }

    /// Open, or following a swipe from the edge.
    private var sidebarShown: Bool {
        sidebarOpen || edgeTravel != nil
    }

    /// How far a swipe from the edge has brought the panel out; nil when no horizontal swipe is moving it.
    private var edgeTravel: CGFloat? {
        guard !edgeCancelled, let drag: SidebarDrag = edgeDrag else { return nil }
        return drag.horizontalTravel
    }

    /// How much of the panel's width is out: all of it when open, less while a drag pulls it back, what a
    /// swipe from the edge has brought out, none when closed.
    private func panelExtent(_ panel: CGFloat) -> CGFloat {
        if sidebarOpen {
            return panel + min(0, closeDrag?.horizontalTravel ?? 0)
        }
        return max(0, edgeTravel ?? 0)
    }

    /// The trailing edge follows the finger. Closed, the panel is parked past its shadow as well, so no
    /// trace of it is left at the screen's edge. Reduce Motion: it stays in place and fades instead.
    private func panelOffset(_ panel: CGFloat) -> CGFloat {
        if reduceMotion {
            return 0
        }
        guard sidebarShown else { return -(panel + Sidebar.shadowReach) }
        return min(0, panelExtent(panel) - panel)
    }

    /// 0 closed to 1 open: the scrim's opacity, and the panel's under Reduce Motion.
    private func panelProgress(_ panel: CGFloat) -> Double {
        guard panel > 0 else { return sidebarShown ? 1 : 0 }
        return Double(min(max(panelExtent(panel) / panel, 0), 1))
    }

    /// Every slide first asks the presenter to start nothing for its length, so a sheet asked for from
    /// the sidebar rises only once the panel has gone. Closing works from any shown state, a swipe from
    /// the edge still under the finger included. Reduce Motion: a fade in place.
    private func setSidebar(_ open: Bool) {
        if !open && edgeTravel != nil {
            withAnimation(sidebarAnimation(open: false)) {
                edgeCancelled = true
            }
        }
        guard open != sidebarOpen else { return }
        presenter.delay(for: MainView.sidebarSlide)
        withAnimation(sidebarAnimation(open: open)) {
            sidebarOpen = open
        }
    }

    private func sidebarAnimation(open: Bool) -> Animation {
        if reduceMotion {
            return Anim.sidebarFade
        }
        return open ? Anim.sidebarIn : Anim.sidebarOut
    }

    /// ≡ and the edge swipe. Ignored while the room is dimmed (see `selectTab`), and while a sheet or a
    /// dialog is up or still to come (one asked for from the sidebar would otherwise rise over it).
    private var canOpenSidebar: Bool {
        !roomDimmed && presenter.isIdle
    }

    private func openSidebar() {
        guard canOpenSidebar else { return }
        setSidebar(true)
    }

    /// Another group: its Home, and the panel closes. The selected one: the panel just closes and the tab stays.
    private func pickGroup(_ id: GroupID) {
        if id != selected {
            select(id)
        }
        setSidebar(false)
    }

    /// Settings, you, New group, Join with a link: the panel closes and the sheet follows once it has gone.
    private func openFromSidebar(_ s: MainSheet) {
        setSidebar(false)
        presenter.present(s, from: .screen)
    }

    // MARK: - Sidebar gestures

    /// The panel follows a clearly horizontal swipe from the edge and opens past a third of its width,
    /// or when the predicted end passes half; otherwise it springs back.
    private func edgeGesture(panel: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .updating($edgeDrag) { (value: DragGesture.Value, state: inout SidebarDrag?, _: inout Transaction) in
                state = SidebarDrag.next(state, translation: value.translation)
            }
            .onChanged { (value: DragGesture.Value) in
                latchAxis(value.translation)
            }
            .onEnded { (value: DragGesture.Value) in
                edgeEnded(value, panel: panel)
            }
    }

    private func edgeEnded(_ value: DragGesture.Value, panel: CGFloat) {
        let axis: DragAxis? = releaseAxis
        releaseAxis = nil
        guard axis == .horizontal, !edgeCancelled, !sidebarOpen, canOpenSidebar else { return }
        if MainView.passes(value.translation.width, predicted: value.predictedEndTranslation.width, panel: panel) {
            setSidebar(true)
        }
    }

    /// Attached alongside the panel's own gestures, so the group list keeps its vertical scroll: only a
    /// clearly horizontal drag moves the panel, and a vertical one is ignored for the rest of the gesture.
    private func closeGesture(panel: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .updating($closeDrag) { (value: DragGesture.Value, state: inout SidebarDrag?, _: inout Transaction) in
                state = SidebarDrag.next(state, translation: value.translation)
            }
            .onChanged { (value: DragGesture.Value) in
                latchAxis(value.translation)
            }
            .onEnded { (value: DragGesture.Value) in
                closeEnded(value, panel: panel)
            }
    }

    private func closeEnded(_ value: DragGesture.Value, panel: CGFloat) {
        let axis: DragAxis? = releaseAxis
        releaseAxis = nil
        guard axis == .horizontal else { return }
        if MainView.passes(-value.translation.width, predicted: -value.predictedEndTranslation.width, panel: panel) {
            setSidebar(false)
        }
    }

    /// The first change decides, as in `SidebarDrag.next`.
    private func latchAxis(_ translation: CGSize) {
        if releaseAxis == nil {
            releaseAxis = DragAxis.of(translation)
        }
    }

    /// No drag is live any more (ended, or cancelled without a word): nothing of it may stay behind.
    private func dragsEnded() {
        releaseAxis = nil
        edgeCancelled = false
    }

    /// Past a third of the panel, or flung past half of it.
    private static func passes(_ travel: CGFloat, predicted: CGFloat, panel: CGFloat) -> Bool {
        return travel > panel / 3 || predicted > panel / 2
    }

    // MARK: - Tabs and selection

    /// Ignored while the room is dimmed (from the hold's 200 ms gate to the seal): the orb drops a
    /// completed seal that has not been delivered if it leaves the screen. Re-tapping the selected tab
    /// scrolls its page to the top.
    private func selectTab(_ t: MainTab) {
        guard !roomDimmed else { return }
        if t == tab {
            topToken += 1
        } else {
            tab = t
        }
    }

    /// Switching group resets the tab to Home: a switch is almost always to keep that vow.
    private func select(_ id: GroupID) {
        guard store.snapshots[id] != nil else { return }
        if selected != id {
            withAnimation(reduceMotion ? nil : Anim.switchVow) {
                selected = id
                tab = .home
            }
        }
        prefs.saveLastVowZone(id.zoneName)
    }

    /// That group's Home, also when it is already selected (a reminder, the vow prompt, an invite).
    private func showHome(_ id: GroupID) {
        select(id)
        if selected == id && tab != .home {
            tab = .home
        }
    }

    /// Forced: move to the most urgent open vow only when the shown vow is not open (kept, not a
    /// member, or gone); an open vow is never replaced, and a vow prompt waiting for its sheet keeps
    /// its group. Nothing valid shown: the most urgent open vow, else the last one viewed, else the first.
    private func chooseSelection(force: Bool) {
        var current: GroupID? = nil
        if let id: GroupID = selected, store.snapshots[id] != nil {
            current = id
        }
        guard force || current == nil else { return }
        if let prompt: GroupID = store.pendingVowPrompt, store.snapshots[prompt] != nil {
            select(prompt)
            return
        }
        let all: [GroupID: GroupSummary] = memo.summaries(store, now: Date())
        let urgent: GroupID? = store.mostUrgentGroupID(in: all)
        if force, let target: GroupID = urgent, target != current {
            var currentIsOpen: Bool = false
            if let id: GroupID = current, let summary: GroupSummary = all[id] {
                currentIsOpen = Digest.isOpen(summary)
            }
            if !currentIsOpen {
                select(target)
                return
            }
        }
        if current == nil, let fallback: GroupID = urgent ?? lastViewed() ?? store.groupIDs.first {
            select(fallback)
        }
    }

    private func lastViewed() -> GroupID? {
        guard let zone: String = prefs.loadLastVowZone() else { return nil }
        return store.groupIDs.first(where: { (id: GroupID) -> Bool in id.zoneName == zone })
    }

    // MARK: - Derived

    /// The selected group when its snapshot is loaded: its page, name and tab bar are shown.
    private var shownID: GroupID? {
        guard let id: GroupID = selected, store.snapshots[id] != nil else { return nil }
        return id
    }

    private var shownGroup: GroupInfo? {
        guard let id: GroupID = shownID else { return nil }
        return store.snapshots[id]?.group
    }

    /// Your groups in store order.
    private var groupInfos: [GroupInfo] {
        var out: [GroupInfo] = []
        for id in store.groupIDs {
            if let group: GroupInfo = store.snapshots[id]?.group {
                out.append(group)
            }
        }
        return out
    }

    /// A hold or the reward cascade is running on Home: nothing changes the page or the group by itself.
    private var stageBusy: Bool {
        roomDimmed || holdingLightID != nil
    }

    /// New group is up: a reminder tap waits until it closes, saving or not. Deliberate: closing it would
    /// discard what you typed (and cut a save off before its Invite).
    private var creating: Bool {
        presenter.sheet == MainSheet.create
    }

    /// Lit from the social beat on once you have kept today; never for a finished vow.
    private func streakLit(_ id: GroupID, all: [GroupID: GroupSummary]) -> Bool {
        guard let summary: GroupSummary = all[id], !summary.isFinished else { return false }
        return summary.viewer?.checkedInToday == true && holdingLightID != id
    }

    /// Your vows other than `besides` still open today.
    private func openVows(besides: GroupID?) -> MenuDot? {
        let now: Date = Date()
        return Overview.menuDot(memo.summaries(store, now: now), groups: groupInfos, selected: besides, now: now)
    }

    // MARK: - Page callbacks

    private func stageActions(_ id: GroupID) -> StageActions {
        return StageActions(
            editVow: { presenter.present(.vow(id), from: .screen) },
            showMember: { (userID: String) in presenter.present(.member(id, userID), from: .screen) },
            showStreak: { selectTab(.streak) },
            confirmReset: { presenter.confirm(.resetTest(id), from: .screen) },
            willLight: { holdingLightID = id },
            didLight: { lightReleased(id) },
            didKeep: { pulseMenuIfNeeded() },
            offerReminder: { offerReminderIfDue(kept: id) }
        )
    }

    private func groupActions(_ id: GroupID) -> GroupActions {
        return GroupActions(
            invite: { presenter.present(.invite(id), from: .screen) },
            editVow: { presenter.present(.vow(id), from: .screen) },
            showMember: { (userID: String) in presenter.present(.member(id, userID), from: .screen) },
            confirmLeave: { presenter.confirm(.leave(id), from: .screen) },
            confirmDelete: { presenter.confirm(.delete(id), from: .screen) }
        )
    }

    private func lightReleased(_ id: GroupID) {
        if holdingLightID == id {
            holdingLightID = nil
        }
    }

    /// Seal + 2.0 s (or on leaving Home before then): ≡ pulses once when a vow other than the shown one
    /// is still open. No dot is left behind.
    private func pulseMenuIfNeeded() {
        if openVows(besides: selected) != nil {
            menuPulseToken += 1
        }
    }

    /// Seal + 2.3 s (or on leaving Home before then): only once the day's vows are done, and only with a
    /// real vow to remind. The presenter shows it once nothing is up and the shell is not busy.
    private func offerReminderIfDue(kept id: GroupID) {
        guard openVows(besides: id) == nil, reminders.shouldOffer else { return }
        guard !store.reminderGroups(memo.summaries(store, now: Date())).isEmpty else { return }
        offerWindow.open()
        presenter.present(.reminderOffer, from: .automatic)
    }

    // MARK: - Sheets and dialogs

    /// The only `.sheet` and `.confirmationDialog` in the main experience.
    private var presentations: some View {
        shell
            .sheet(item: presenter.sheetBinding, onDismiss: { presenter.sheetDismissed() }) { (item: MainSheet) in
                sheetContent(item)
            }
            .confirmationDialog(dialogTitle,
                                isPresented: presenter.dialogBinding,
                                titleVisibility: .visible,
                                presenting: presenter.dialog) { (d: MainDialog) in
                dialogActions(d)
            } message: { (d: MainDialog) in
                Text(dialogMessage(d))
            }
    }

    /// The content's appearance is the presenter's proof that a presentation really happened.
    private func sheetContent(_ item: MainSheet) -> some View {
        sheetBody(item)
            .environment(store)
            .environment(reminders)
            .onAppear {
                presenter.sheetAppeared(item)
            }
            .onDisappear {
                presenter.sheetDisappeared(item)
            }
    }

    /// Every case is a real view: an `EmptyView` body never appears, so the presenter would clear it.
    @ViewBuilder
    private func sheetBody(_ item: MainSheet) -> some View {
        switch item {
        case .create:
            NewGroupSheet(onCreated: { (id: GroupID) in groupCreated(id) })
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
            MemberSheet(id: id, userID: userID, onEditVow: { presenter.present(.vow(id), from: .sheet) })
                .vowSheet([.medium, .large])
        case .settings:
            SettingsSheet()
                .vowSheet([.large])
        case .profile:
            ProfileSheet()
                .vowSheet([.large])
        case .reminderOffer:
            ReminderOfferSheet()
                .vowSheet([.height(380), .large])
        }
    }

    /// Create → Invite → the new vow's Home: the Create sheet closes, then Invite rises.
    private func groupCreated(_ id: GroupID) {
        select(id)
        presenter.present(.invite(id), from: .sheet)
    }

    private var dialogTitle: String {
        guard let d: MainDialog = presenter.dialog else { return "" }
        switch d {
        case .leave(let id):
            return "Leave \(groupName(id))?"
        case .delete(let id):
            return "Delete \(groupName(id))?"
        case .resetTest:
            return "Reset this test group?"
        }
    }

    @ViewBuilder
    private func dialogActions(_ d: MainDialog) -> some View {
        switch d {
        case .leave(let id):
            Button("Leave group", role: .destructive) {
                Task { await store.leave(id) }
            }
        case .delete(let id):
            Button("Delete group", role: .destructive) {
                Task { await store.deleteGroup(id) }
            }
        case .resetTest(let id):
            Button("Reset group", role: .destructive) {
                Task { await store.resetTestGroup(id) }
            }
        }
        Button("Cancel", role: .cancel) {}
    }

    private func dialogMessage(_ d: MainDialog) -> String {
        switch d {
        case .leave:
            return "You stop staking from today. Your past days stay in the group's activity."
        case .delete:
            return "This deletes the group and its history for everyone. You can't undo it."
        case .resetTest:
            return "Everyone starts over from day 1. Check-ins, streaks and points are cleared."
        }
    }

    private func groupName(_ id: GroupID) -> String {
        return store.snapshots[id]?.group.name ?? "this group"
    }

    /// The hooks capture the store, the reminder centre and the offer window (references), never this
    /// view value.
    private func wirePresenter() {
        let store: AppStore = self.store
        let reminders: ReminderCenter = self.reminders
        let window: OfferWindow = offerWindow
        presenter.isStillWanted = { (s: MainSheet) -> Bool in
            switch s {
            case .vow(let id):
                guard store.pendingVowPrompt == id, let group: GroupInfo = store.snapshots[id]?.group else { return false }
                return !EndDate.isFinished(group, now: Date())
            case .reminderOffer:
                return reminders.shouldOffer && window.isOpen
            case .create, .join, .invite, .member, .settings, .profile:
                return true
            }
        }
        presenter.didClose = { (s: MainSheet) -> Void in
            // Closing the vow prompt without saving: the not-a-member page offers it again.
            if case .vow(let id) = s, store.pendingVowPrompt == id {
                store.pendingVowPrompt = nil
            }
        }
    }

    // MARK: - Lifecycle

    private var appearanceHooks: some View {
        presentations
            .onAppear {
                appeared()
            }
            .onDisappear {
                presenter.setActive(false)
                toastBlocked = false
            }
            .onChange(of: scenePhase) { (_: ScenePhase, phase: ScenePhase) in
                scenePhaseChanged(phase)
            }
            .task(id: shownID) {
                await refreshLoop(shownID)
            }
    }

    /// What the presenter and RootView need to know about the shell, and what waited for Home.
    private var shellHooks: some View {
        appearanceHooks
            .onChange(of: stageBusy || sidebarOpen || edgeDrag != nil, initial: true) { (_: Bool, busy: Bool) in
                presenter.setBusy(busy)
            }
            .onChange(of: sidebarShown || !presenter.isIdle, initial: true) { (_: Bool, blocked: Bool) in
                toastBlocked = blocked
            }
            .onChange(of: edgeDrag == nil && closeDrag == nil) { (_: Bool, idle: Bool) in
                if idle {
                    dragsEnded()
                }
            }
            .onChange(of: stageBusy) { (_: Bool, busy: Bool) in
                if !busy {
                    catchUp()
                }
            }
            .onChange(of: holdingLightID) {
                if holdingLightID == nil {
                    syncReminders(force: false)
                }
            }
            .onChange(of: creating) { (_: Bool, open: Bool) in
                if !open {
                    handleOpenRequest()
                }
            }
    }

    private var storeHooks: some View {
        shellHooks
            .onChange(of: store.groupIDs) {
                chooseSelection(force: false)
                promptPendingVow()
                handleOpenRequest()
            }
            .onChange(of: store.pendingVowPrompt, initial: true) {
                promptPendingVow()
            }
            .onChange(of: store.acceptCount) {
                acceptPending = true
                showAccepted()
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

    /// Every time: nothing is presented until the screen's crossfade has finished. Once per shell: the
    /// first selection, and the reminder tap that launched the app.
    private func appeared() {
        wirePresenter()
        presenter.delay(for: MainView.crossfade)
        presenter.setActive(scenePhase == .active)
        guard !didAppear else { return }
        didAppear = true
        chooseSelection(force: true)
        handleOpenRequest()
    }

    private func scenePhaseChanged(_ phase: ScenePhase) {
        presenter.setActive(phase == .active)
        if phase == .background {
            backgroundedAt = Date()
        }
        if phase == .active {
            if let since: Date = backgroundedAt, Date().timeIntervalSince(since) >= MainView.reselectAfter {
                reselectPending = true
                reselectIfDue()
            }
            backgroundedAt = nil
            syncReminders(force: true)
        }
    }

    /// The shown group, every 60 s, on every tab. A group that has gone is never polled.
    private func refreshLoop(_ id: GroupID?) async {
        guard let target: GroupID = id else { return }
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: MainView.refreshNanos)
            if Task.isCancelled || store.snapshots[target] == nil { break }
            await store.refresh(target)
        }
    }

    // MARK: - Programmatic switches (they wait for the busy window)

    /// The hold and the cascade are over: whatever waited for them runs now.
    private func catchUp() {
        reselectIfDue()
        showAccepted()
        promptPendingVow()
        handleOpenRequest()
    }

    private func reselectIfDue() {
        guard reselectPending, !stageBusy else { return }
        reselectPending = false
        chooseSelection(force: true)
    }

    /// Already a member (no prompt): that vow's Home, under the store's toast.
    private func showAccepted() {
        guard acceptPending, !stageBusy else { return }
        acceptPending = false
        guard let id: GroupID = store.lastAcceptedGroup, store.pendingVowPrompt != id else { return }
        showHome(id)
    }

    /// Joined by link (also during onboarding or launch): that vow's Home, then its vow sheet once
    /// nothing is up and the shell is not busy. A finished vow has nothing to join: just its Home.
    private func promptPendingVow() {
        guard !stageBusy, let id: GroupID = store.pendingVowPrompt,
              let group: GroupInfo = store.snapshots[id]?.group else { return }
        showHome(id)
        if EndDate.isFinished(group, now: Date()) {
            store.pendingVowPrompt = nil
            return
        }
        presenter.present(.vow(id), from: .automatic)
    }

    /// A reminder tap: everything closes, then that vow's Home. Kept until the group exists (a cold
    /// launch comes before the first sync) and dropped once a sync finished without it. Waits while Home
    /// is busy and while New group is up, so a save is never cut off.
    private func handleOpenRequest() {
        guard let id: GroupID = reminders.openRequest else { return }
        guard store.snapshots[id] != nil else {
            if store.lastSyncedAt != nil {
                reminders.openRequest = nil
            }
            return
        }
        guard !stageBusy, !creating else { return }
        reminders.openRequest = nil
        presenter.dismissAll()
        setSidebar(false)
        showHome(id)
    }

    // MARK: - Reminders

    /// Callers skip it while `holdingLightID` is set; the seal syncs once the cascade has lit its tab.
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

/// One Settlement pass per (snapshots, groups, user, minute), not per shell render.
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

/// The reminder offer belongs to the moment after a keep. If the shell stays busy longer than this
/// (the sidebar, a sheet you opened), it is not shown; the next keep asks again.
@MainActor
private final class OfferWindow {
    private var openedAt: TimeInterval? = nil

    private static let length: TimeInterval = 10

    func open() {
        openedAt = ProcessInfo.processInfo.systemUptime
    }

    var isOpen: Bool {
        guard let start: TimeInterval = openedAt else { return false }
        return ProcessInfo.processInfo.systemUptime - start < OfferWindow.length
    }
}

/// How a drag on the sidebar or its edge was classified: horizontal only when clearly wider than tall.
private enum DragAxis {
    case horizontal
    case vertical

    static func of(_ translation: CGSize) -> DragAxis {
        return abs(translation.width) > 2 * abs(translation.height) ? DragAxis.horizontal : DragAxis.vertical
    }
}

/// A live drag on the sidebar or its edge: its axis, decided once on the first change, and the finger's
/// horizontal travel.
private struct SidebarDrag {
    let axis: DragAxis
    let dx: CGFloat

    /// The travel while it can move the panel; nil for a vertical drag (the group list's scroll).
    var horizontalTravel: CGFloat? {
        axis == .horizontal ? dx : nil
    }

    static func next(_ previous: SidebarDrag?, translation: CGSize) -> SidebarDrag {
        let axis: DragAxis = previous?.axis ?? DragAxis.of(translation)
        return SidebarDrag(axis: axis, dx: translation.width)
    }
}
