import SwiftUI
import UIKit

/// The signed-in app, as a shell: the pinned top bar, the selected group's page for the chosen tab, the
/// tab bar and the sidebar overlay, which stays mounted and only ever slides or fades. It owns the selection, the
/// tab and the swipe between tabs, the fallback refresh (every 15 s, every 5 s on Chat), Chat's unsent drafts,
/// the reminder sync and the `Presenter`, whose one sheet, one full-screen cover and one confirmation dialog are
/// the only ones in the main experience: pages and chrome ask for them through closures. It ignores the
/// keyboard: Chat lifts its own composer, and a sheet's keyboard never moves the shell behind it.
struct MainView: View {
    @Binding var roomDimmed: Bool
    /// A sheet, a cover, a dialog or the sidebar is up: RootView's toast waits briefly, then it is dropped.
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
    /// Bumped when the selected tab is tapped again: its page scrolls to the top (Chat: to the latest).
    @State private var topToken: Int = 0
    /// Each group's unsent Chat message, kept across tab and group switches while the app runs.
    @State private var chatDrafts: [GroupID: String] = [:]
    @State private var sidebarOpen: Bool = false
    /// A swipe from the leading edge while the panel follows it. Gesture state, like `closeDrag`: a
    /// cancelled drag (a sheet or an alert taking the touch, the app going inactive) resets itself, so
    /// the panel can never be left half out.
    @GestureState(resetTransaction: Transaction(animation: Anim.sidebarIn))
    private var edgeDrag: ShellDrag? = nil
    /// A drag on the open panel or its scrim.
    @GestureState(resetTransaction: Transaction(animation: Anim.sidebarIn))
    private var closeDrag: ShellDrag? = nil
    /// The live drag's axis for the release decision (gesture state has reset by then). Cleared whenever
    /// no drag is live, so a drag that never reports its end can't leave it set.
    @State private var releaseAxis: DragAxis? = nil
    /// The sidebar was closed while a swipe from the edge or across Home was still under the finger: that
    /// swipe no longer shows or opens the panel. Cleared when it ends.
    @State private var edgeCancelled: Bool = false
    /// A swipe on the page that owns its touch, as `SwipeablePage` reports it: which way the slide would go,
    /// or how far Home's swipe has brought the sidebar out. nil while none does (a scroll never sets it).
    @State private var pageSwipe: PageSwipe? = nil
    /// The slide a released swipe started, until it has finished: the page it brings in arrives with it.
    @State private var pageSlide: PageSlide? = nil
    /// What stops a swipe from starting, read only then: Chat's overlays, and a seal Home may still owe.
    @State private var swipeGuard: SwipeGuard = SwipeGuard()
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
    /// The shown group's poll. A fallback: silent pushes bring most changes as they happen, and a poll only
    /// fetches what changed in the zone since the last one, so it is small.
    private static let refreshNanos: UInt64 = 15_000_000_000
    /// While Chat is shown: a reply or a vote that no push brought still arrives within seconds.
    private static let chatRefreshNanos: UInt64 = 5_000_000_000
    /// The strip along the leading edge that opens the sidebar with a swipe.
    private static let edgeWidth: CGFloat = 16
    /// A swipe on Home that began on the orb without dimming the room (it moved within the dim gate) can
    /// complete the hold under it. Its first change came within one gate of touch-down, so one let go
    /// sooner than this can't have, and a longer one stays: the orb must not leave before its seal. The
    /// hold's length less two gates, one of them margin. A drag on Home this long may also leave a seal
    /// owed after it ends (`SwipeGuard`).
    private static let homeSwipeLimit: TimeInterval = OrbTiming.hold - 2 * Double(Anim.dimGateNanos) / 1_000_000_000

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
                       width: proxy.size.width,
                       bottomInset: proxy.safeAreaInsets.bottom,
                       now: context.date)
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
    }

    /// The main screen with the sidebar over it (an overlay: the page and the orb keep their place).
    private func screen(all: [GroupID: GroupSummary], metrics: StageMetrics, width: CGFloat, bottomInset: CGFloat,
                        now: Date) -> some View {
        let panel: CGFloat = min(Gap.sidebarMax, width * 0.82)
        return ZStack(alignment: .topLeading) {
            mainScreen(all: all, metrics: metrics, width: width, panel: panel, bottomInset: bottomInset, now: now)
            sidebarLayer(all: all, panel: panel, bottomInset: bottomInset, now: now)
        }
    }

    /// The page between the pinned top bar and tab bar, with the edge zone along its leading side (over the
    /// page, so a swipe from it never reaches the page's own swipe).
    private func mainScreen(all: [GroupID: GroupSummary], metrics: StageMetrics, width: CGFloat, panel: CGFloat,
                            bottomInset: CGFloat, now: Date) -> some View {
        page(all: all, metrics: metrics, width: width, panel: panel)
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

    /// Whenever a group's page is shown: members, not-members and finished vows alike, so the five tabs
    /// keep their places. Chat's dot is for the shown group, and never while Chat is the page.
    @ViewBuilder
    private func tabBar(all: [GroupID: GroupSummary], bottomInset: CGFloat) -> some View {
        if let id: GroupID = shownID {
            VowTabBar(selection: tab,
                      streakLit: streakLit(id, all: all),
                      chatDot: tab != .chat && store.hasUnseenChat(id),
                      dimmed: roomDimmed,
                      bottomInset: bottomInset,
                      onSelect: { (t: MainTab) in selectTab(t) })
        }
    }

    /// The selected group's page, or the empty stage, or a spinner while the selected group (or a fresh
    /// install's first sync) loads, so a new install that does have groups never flashes "Your first vow".
    /// Only a group's page swipes (`SwipeablePage`). A swipe's hold limit applies only on Home while its orb
    /// can still be held (`Digest.isOpen`): once you have checked in or been excused, on a finished vow or for a
    /// non-member, there is no seal to wait for.
    @ViewBuilder
    private func page(all: [GroupID: GroupSummary], metrics: StageMetrics, width: CGFloat, panel: CGFloat) -> some View {
        if let id: GroupID = shownID {
            let orbOpen: Bool = all[id].map { (s: GroupSummary) -> Bool in Digest.isOpen(s) } ?? false
            SwipeablePage(width: width,
                          hasNext: tab.next != nil,
                          hasPrevious: tab.previous != nil,
                          opensSidebar: tab == .home,
                          holdLimit: tab == .home && orbOpen ? MainView.homeSwipeLimit : nil,
                          hooks: swipeHooks(panel: panel)) {
                tabPage(id, metrics: metrics, width: width)
            }
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

    /// Pages are swapped, not kept alive: the orb, its timers and the calendar never run off screen. Two
    /// are mounted only while a swipe's slide runs, and the one leaving is gone when it ends.
    @ViewBuilder
    private func tabPage(_ id: GroupID, metrics: StageMetrics, width: CGFloat) -> some View {
        switch tab {
        case .home:
            sliding(StageScreen(id: id, roomDimmed: $roomDimmed, metrics: metrics, topToken: topToken,
                                actions: stageActions(id)),
                    width: width)
        case .chat:
            sliding(ChatPage(id: id, topToken: topToken, draft: chatDraft(id), covered: sidebarShown,
                             actions: chatActions(id)),
                    width: width)
        case .streak:
            sliding(StreakPage(id: id, metrics: metrics, topToken: topToken,
                               onJoin: { presenter.present(.vow(id), from: .screen) }),
                    width: width)
        case .activity:
            sliding(ActivityPage(id: id, topToken: topToken), width: width)
        case .group:
            sliding(GroupPage(id: id, topToken: topToken, actions: groupActions(id)), width: width)
        }
    }

    /// Each page carries the slide that takes it out or brings it in; `SwipeablePage` moves whichever is shown
    /// while a finger does.
    private func sliding<Page: View>(_ page: Page, width: CGFloat) -> some View {
        page
            .transition(pageTransition(width))
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

    /// How far a swipe from the edge, or one to the right on Home, has brought the panel out; nil when no
    /// horizontal swipe is moving it.
    private var edgeTravel: CGFloat? {
        guard !edgeCancelled else { return nil }
        return edgeDrag?.horizontalTravel ?? sidebarSwipeTravel
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
    /// the edge still under the finger included. Opening ends editing, so Chat's keyboard never sits over
    /// the panel's footer. Reduce Motion: a fade in place.
    private func setSidebar(_ open: Bool) {
        if !open && edgeTravel != nil {
            withAnimation(sidebarAnimation(open: false)) {
                edgeCancelled = true
            }
        }
        guard open != sidebarOpen else { return }
        if open {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
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

    /// ≡, the edge swipe and every swipe on the page. Ignored while the room is dimmed (see `selectTab`), and
    /// while a sheet or a dialog is up or still to come (one asked for from the sidebar would otherwise rise
    /// over it).
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
            .updating($edgeDrag) { (value: DragGesture.Value, state: inout ShellDrag?, _: inout Transaction) in
                ShellDrag.track(&state, translation: value.translation)
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
        guard axis == .horizontal else { return }
        openIfPassed(value, panel: panel)
    }

    /// A swipe that has brought the panel out, from the edge or across Home, is let go.
    private func openIfPassed(_ value: DragGesture.Value, panel: CGFloat) {
        guard !edgeCancelled, !sidebarOpen, canOpenSidebar else { return }
        if MainView.passes(value.translation.width, predicted: value.predictedEndTranslation.width, panel: panel) {
            setSidebar(true)
        }
    }

    /// Attached alongside the panel's own gestures, so the group list keeps its vertical scroll: only a
    /// clearly horizontal drag moves the panel, and a vertical one is ignored for the rest of the gesture.
    private func closeGesture(panel: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .updating($closeDrag) { (value: DragGesture.Value, state: inout ShellDrag?, _: inout Transaction) in
                ShellDrag.track(&state, translation: value.translation)
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

    /// The first change decides, as in `ShellDrag.track`.
    private func latchAxis(_ translation: CGSize) {
        if releaseAxis == nil {
            releaseAxis = DragAxis.of(translation)
        }
    }

    /// No drag is live any more (ended, or cancelled without a word): nothing of it may stay behind. Each is
    /// written only when set, so the end of a scroll of the group list costs the shell no extra render.
    private func dragsEnded() {
        if releaseAxis != nil {
            releaseAxis = nil
        }
        if edgeCancelled {
            edgeCancelled = false
        }
    }

    /// Past a third of the panel, or flung past half of it.
    private static func passes(_ travel: CGFloat, predicted: CGFloat, panel: CGFloat) -> Bool {
        return travel > panel / 3 || predicted > panel / 2
    }

    // MARK: - Swiping between tabs

    /// What the page's swipe asks of the shell and tells it. A swipe starts only while ≡ could open the sidebar,
    /// with the sidebar closed and no swipe from the edge under way, nothing of Chat's up (a drag there is the
    /// overlay's or the cursor's, and standing the page down would take the keyboard away) and no seal owed on
    /// Home. Nothing the swipe itself reports changes the answer, so the page's two reads of it agree. It stops
    /// counting once the room dims or a presentation is coming, and a page swipe once the sidebar has opened
    /// under it (≡ under a second finger).
    private func swipeHooks(panel: CGFloat) -> SwipeHooks {
        return SwipeHooks(
            canStart: { () -> Bool in
                return canOpenSidebar && !sidebarOpen && edgeDrag == nil && !swipeGuard.overlay && !swipeGuard.owesSeal
            },
            canContinue: { (toSidebar: Bool) -> Bool in
                return canOpenSidebar && (toSidebar || !sidebarOpen)
            },
            changed: { (swipe: PageSwipe?) in pageSwipeChanged(swipe) },
            commit: { (forward: Bool) in commitSwipe(forward: forward) },
            releaseToSidebar: { (value: DragGesture.Value) in openIfPassed(value, panel: panel) },
            heldLong: { swipeGuard.longDragEnded() }
        )
    }

    /// Written only when it changes: the shell renders as a swipe takes its touch, turns around and ends, and on
    /// every frame only while Home's swipe moves the panel. One toward the sidebar let go short springs back as
    /// one from the edge does.
    private func pageSwipeChanged(_ swipe: PageSwipe?) {
        guard swipe != pageSwipe else { return }
        if swipe == nil, case .sidebar? = pageSwipe {
            withAnimation(Anim.sidebarIn) {
                pageSwipe = nil
            }
            return
        }
        pageSwipe = swipe
    }

    /// The next page (`forward`) or the previous one slides in edge to edge with this one, from where the finger
    /// left it: `SwipeablePage` springs its offset back as the slide runs. The tab bar's path, so the room's
    /// dimming and an owed seal stop it too. Reduce Motion: a crossfade.
    private func commitSwipe(forward: Bool) {
        guard canOpenSidebar, !sidebarOpen, let target: MainTab = forward ? tab.next : tab.previous else { return }
        let slide: PageSlide = PageSlide(forward: forward, startedAt: ProcessInfo.processInfo.systemUptime)
        pageSlide = slide
        withAnimation(reduceMotion ? Anim.fade : Anim.standard) {
            selectTab(target)
        } completion: {
            if pageSlide == slide {
                pageSlide = nil
            }
        }
    }

    /// A swipe owns its touch: automatic presentations wait for it.
    private var swipeOwnsTouch: Bool {
        pageSwipe != nil
    }

    /// How far Home's swipe toward the sidebar has gone; nil while none is under way.
    private var sidebarSwipeTravel: CGFloat? {
        guard case .sidebar(let travel)? = pageSwipe else { return nil }
        return travel
    }

    /// While a swipe moves the page, and while the slide it started runs, the page leaving and the page
    /// arriving move a width apart on the swipe's side. A page that leaves keeps the transition of its last
    /// render, which the swipe's start (or its last turn) set; the one arriving takes the slide's. Otherwise
    /// none: a tab-bar tap stays an instant swap.
    private func pageTransition(_ width: CGFloat) -> AnyTransition {
        if case .page(let forward)? = pageSwipe {
            return MainView.slideTransition(forward: forward, width: width, reduceMotion: reduceMotion)
        }
        if let slide: PageSlide = pageSlide {
            return MainView.slideTransition(forward: slide.forward, width: width, reduceMotion: reduceMotion)
        }
        return AnyTransition.identity
    }

    /// Forward (to the next tab), pages move toward the leading edge: the old one out by a width, the new one in
    /// from a width away. Both ride on the swipe's offset as it springs back, so they meet where the finger
    /// left the old one and stay edge to edge.
    private static func slideTransition(forward: Bool, width: CGFloat, reduceMotion: Bool) -> AnyTransition {
        if reduceMotion {
            return AnyTransition.opacity
        }
        let shift: CGFloat = forward ? -width : width
        return AnyTransition.asymmetric(insertion: AnyTransition.offset(x: -shift),
                                        removal: AnyTransition.offset(x: shift))
    }

    // MARK: - Tabs and selection

    /// The tab bar, Home's links and a swipe. Ignored while the room is dimmed (from the hold's 200 ms gate to
    /// the seal), and while a hold that completed under a long drag on Home, with the room lit, may still owe
    /// its seal (`SwipeGuard.owesSeal`): the orb drops a completed seal that has not been delivered if it
    /// leaves the screen. Re-tapping the selected tab scrolls its page to the top.
    private func selectTab(_ t: MainTab) {
        guard !roomDimmed, !swipeGuard.owesSeal else { return }
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

    /// New group, an excuse or proof on its way is up, or about to rise in place of what is up (the proof
    /// sheet after the camera): a reminder tap waits until it has closed, sent or not. Deliberate: closing
    /// it would discard what you typed, picked or shot (and cut a save off before its Invite).
    private var holdsUnsavedWork: Bool {
        presenter.sheet?.holdsUnsavedWork == true || presenter.queued?.holdsUnsavedWork == true
    }

    /// Lit from the social beat on while your check-in today stands (not excused, not overruled); never for
    /// a finished vow.
    private func streakLit(_ id: GroupID, all: [GroupID: GroupSummary]) -> Bool {
        guard let summary: GroupSummary = all[id], !summary.isFinished,
              let viewer: MemberStanding = summary.viewer else { return false }
        return Digest.checkInStands(viewer) && holdingLightID != id
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
            offerReminder: { offerReminderIfDue(kept: id) },
            excuse: { presenter.present(.excuse(id), from: .screen) },
            addProof: { addProof(id) },
            showChat: { selectTab(.chat) }
        )
    }

    private func groupActions(_ id: GroupID) -> GroupActions {
        return GroupActions(
            invite: { presenter.present(.invite(id), from: .screen) },
            editVow: { presenter.present(.vow(id), from: .screen) },
            showMember: { (userID: String) in presenter.present(.member(id, userID), from: .screen) },
            confirmLeave: { presenter.confirm(.leave(id), from: .screen) },
            confirmDelete: { presenter.confirm(.delete(id), from: .screen) },
            voteRule: { presenter.present(.voteRule(id), from: .screen) }
        )
    }

    /// Chat's "+" card lists the camera and the library itself, so it skips Home's proof chooser.
    private func chatActions(_ id: GroupID) -> ChatActions {
        return ChatActions(
            takeProof: { presenter.present(.camera(id), from: .screen) },
            pickProof: { presenter.present(.library(id), from: .screen) },
            excuse: { presenter.present(.excuse(id), from: .screen) },
            openMedia: { (postID: String) in presenter.present(.media(id, postID), from: .screen) },
            join: { presenter.present(.vow(id), from: .screen) },
            overlay: { (open: Bool) in swipeGuard.overlay = open }
        )
    }

    /// The group's unsent message; an emptied draft is dropped.
    private func chatDraft(_ id: GroupID) -> Binding<String> {
        return Binding<String>(
            get: { () -> String in
                return chatDrafts[id] ?? ""
            },
            set: { (text: String) -> Void in
                chatDrafts[id] = text.isEmpty ? nil : text
            }
        )
    }

    /// Home's Add proof: the chooser (camera or library), or the library at once on a device without a
    /// camera.
    private func addProof(_ id: GroupID) {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            presenter.present(.library(id), from: .screen)
            return
        }
        presenter.confirm(.proofSource(id), from: .screen)
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

    // MARK: - Sheets, covers and dialogs

    /// The only `.sheet`, `.fullScreenCover` and `.confirmationDialog` in the main experience. One slot:
    /// at most one of them is up.
    private var presentations: some View {
        shell
            .sheet(item: presenter.sheetBinding, onDismiss: { presenter.sheetDismissed() }) { (item: MainSheet) in
                sheetContent(item)
            }
            .fullScreenCover(item: presenter.coverBinding, onDismiss: { presenter.sheetDismissed() }) { (item: MainSheet) in
                sheetContent(item)
            }
            .confirmationDialog(dialogTitle,
                                isPresented: presenter.dialogBinding,
                                titleVisibility: .visible,
                                presenting: presenter.dialog) { (d: MainDialog) in
                dialogActions(d)
            } message: { (d: MainDialog) in
                if let text: String = dialogMessage(d) {
                    Text(text)
                }
            }
    }

    /// The content's appearance is the presenter's proof that a presentation really happened, for a cover
    /// as for a sheet.
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
    /// Covers (`isCover`) fill the screen and take no detents.
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
        case .excuse(let id):
            ExcuseSheet(id: id)
                .vowSheet([.medium, .large])
        case .camera(let id):
            CameraPicker(onPicked: { (draft: MediaDraft) in proofPicked(draft, in: id) },
                         onLibrary: { presenter.present(.library(id), from: .sheet) })
        case .library(let id):
            LibraryPicker(onPicked: { (draft: MediaDraft) in proofPicked(draft, in: id) })
                .vowSheet([.large])
        case .proof(let id, let draft):
            ProofSheet(id: id, draft: draft)
                .vowSheet([.large])
        case .media(let id, let postID):
            MediaViewer(id: id, postID: postID)
        case .voteRule(let id):
            VoteRuleSheet(id: id)
                .vowSheet([.medium, .large])
        }
    }

    /// Create → Invite → the new vow's Home: the Create sheet closes, then Invite rises.
    private func groupCreated(_ id: GroupID) {
        select(id)
        presenter.present(.invite(id), from: .sheet)
    }

    /// The camera or the library has a draft ready: it closes, then the proof sheet rises to caption it.
    private func proofPicked(_ draft: MediaDraft, in id: GroupID) {
        presenter.present(.proof(id, draft), from: .sheet)
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
        case .proofSource:
            return "Add proof"
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
        case .proofSource(let id):
            Button("Take photo or video") {
                presenter.present(.camera(id), from: .sheet)
            }
            Button("Choose from library") {
                presenter.present(.library(id), from: .sheet)
            }
        }
        Button("Cancel", role: .cancel) {}
    }

    /// nil: the dialog has no message (the proof chooser's title says it all).
    private func dialogMessage(_ d: MainDialog) -> String? {
        switch d {
        case .leave:
            return "You stop staking from today. Your past days stay in the group's activity."
        case .delete:
            return "This deletes the group and its history for everyone. You can't undo it."
        case .resetTest:
            return "Everyone starts over from day 1. Check-ins, streaks and points are cleared."
        case .proofSource:
            return nil
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
            case .create, .join, .invite, .member, .settings, .profile, .excuse, .camera, .library, .proof, .media,
                 .voteRule:
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
            .task(id: refreshKey) {
                await refreshLoop(refreshKey)
            }
    }

    /// What the presenter and RootView need to know about the shell, and what waited for Home.
    private var shellHooks: some View {
        appearanceHooks
            .onChange(of: stageBusy || sidebarOpen || edgeDrag != nil || swipeOwnsTouch, initial: true) { (_: Bool, busy: Bool) in
                presenter.setBusy(busy)
            }
            .onChange(of: sidebarShown || !presenter.isIdle, initial: true) { (_: Bool, blocked: Bool) in
                toastBlocked = blocked
            }
            .onChange(of: edgeDrag == nil && closeDrag == nil && pageSwipe == nil) { (_: Bool, idle: Bool) in
                if idle {
                    dragsEnded()
                }
            }
            .onChange(of: refreshKey) { (old: RefreshKey, _: RefreshKey) in
                // Chat has gone (another tab or group): nothing of its can still hold the touch, even if its
                // own disappearance came too late to say so.
                if old.isChat {
                    swipeGuard.overlay = false
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
            .onChange(of: holdsUnsavedWork) { (_: Bool, holds: Bool) in
                if !holds {
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

    /// A new group, or Chat shown or left, restarts the loop at its own pace.
    private var refreshKey: RefreshKey {
        RefreshKey(id: shownID, isChat: tab == .chat)
    }

    /// The shown group, every 15 s on every tab but Chat, where it is every 5 s: a fallback for the pushes,
    /// and each poll a small fetch of what changed. A group that has gone is never polled.
    private func refreshLoop(_ key: RefreshKey) async {
        guard let target: GroupID = key.id else { return }
        let pause: UInt64 = key.isChat ? MainView.chatRefreshNanos : MainView.refreshNanos
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: pause)
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
    /// is busy and while unsaved work is up, so nothing you wrote, picked or shot is thrown away.
    private func handleOpenRequest() {
        guard let id: GroupID = reminders.openRequest else { return }
        guard store.snapshots[id] != nil else {
            if store.lastSyncedAt != nil {
                reminders.openRequest = nil
            }
            return
        }
        guard !stageBusy, !holdsUnsavedWork else { return }
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

/// What the refresh loop runs for: the shown group, at Chat's pace or the usual one.
private struct RefreshKey: Equatable {
    let id: GroupID?
    let isChat: Bool
}

/// How a drag on the sidebar, its edge or the page was classified: horizontal only when clearly wider than tall.
private enum DragAxis {
    case horizontal
    case vertical

    static func of(_ translation: CGSize) -> DragAxis {
        return abs(translation.width) > 2 * abs(translation.height) ? DragAxis.horizontal : DragAxis.vertical
    }
}

/// A live drag on the sidebar or its edge: its axis, decided once on the first change, and the finger's
/// horizontal travel, which only a horizontal drag keeps.
private struct ShellDrag: Equatable {
    let axis: DragAxis
    let dx: CGFloat

    /// The travel while it can move the panel; nil for a vertical drag (the group list's scroll).
    var horizontalTravel: CGFloat? {
        axis == .horizontal ? dx : nil
    }

    /// Writes only a change: a vertical drag is written once, not on every frame of the scroll under it.
    static func track(_ state: inout ShellDrag?, translation: CGSize) {
        let axis: DragAxis = state?.axis ?? DragAxis.of(translation)
        let next: ShellDrag = ShellDrag(axis: axis, dx: axis == .horizontal ? translation.width : 0)
        if next != state {
            state = next
        }
    }
}

// MARK: - Swiping between tabs

/// The selected group's page as one swipe surface, alongside the page's own gestures, so its scroll views, the
/// orb's hold and Chat's long presses keep theirs: a drag is decided on its first change, and only a clearly
/// horizontal one that the shell lets start is a swipe. It holds the live drag itself, so the page follows the
/// finger and stands down without the shell rendering, or the page's body (and its Settlement pass) running
/// again: the shell hears only of a swipe taking its touch, turning round and ending, and of every frame of
/// Home's swipe to the right, which moves the sidebar instead of the page.
///
/// While a swipe owns its touch the page is disabled, so a finger let go over a button (a vote, a member row,
/// Next day) doesn't press it too, and a hold the swipe began on the orb lets go. A drag that isn't a swipe
/// (a scroll, or a swipe that couldn't start) leaves the page alone, Chat's keyboard included. The follow
/// springs back as the drag ends, under the slide when it was let go far enough.
private struct SwipeablePage<Content: View>: View {
    let width: CGFloat
    let hasNext: Bool
    let hasPrevious: Bool
    /// Home: a swipe to the right brings the sidebar out, as one from the edge does.
    let opensSidebar: Bool
    /// Home: how long a drag may last and still change the page (`MainView.homeSwipeLimit`); one that lasts
    /// longer may also leave a seal owed (`SwipeHooks.heldLong`).
    let holdLimit: TimeInterval?
    let hooks: SwipeHooks
    let content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion: Bool
    /// What draws: gesture state, so a drag the system cancels resets itself, and the follow springs back.
    @GestureState(resetTransaction: Transaction(animation: Anim.standard))
    private var drag: PageDrag? = nil
    /// The same drag for its release and for what the shell hears (gesture state has reset by then). Cleared
    /// as it ends, and when the drag goes without an end of its own.
    @State private var latch: SwipeLatch? = nil

    init(width: CGFloat,
         hasNext: Bool,
         hasPrevious: Bool,
         opensSidebar: Bool,
         holdLimit: TimeInterval?,
         hooks: SwipeHooks,
         @ViewBuilder content: () -> Content) {
        self.width = width
        self.hasNext = hasNext
        self.hasPrevious = hasPrevious
        self.opensSidebar = opensSidebar
        self.holdLimit = holdLimit
        self.hooks = hooks
        self.content = content()
    }

    var body: some View {
        content
            .offset(x: offset)
            .disabled(drag?.owns == true)
            .simultaneousGesture(gesture)
            .onChange(of: drag == nil) { (_: Bool, idle: Bool) in
                if idle {
                    dropLatch()
                }
            }
            .onDisappear {
                dropLatch()
            }
    }

    /// The page follows a swipe with resistance, and barely toward no page at all (a rubber band). It stays
    /// still under Reduce Motion, and for a swipe toward the sidebar, which moves the panel instead.
    private var offset: CGFloat {
        guard !reduceMotion, let live: PageDrag = drag, live.owns, !live.toSidebar else { return 0 }
        let hasNeighbour: Bool = live.dx < 0 ? hasNext : hasPrevious
        let limit: CGFloat = width * (hasNeighbour ? SwipeMetrics.followShare : SwipeMetrics.bandShare)
        return SwipeMetrics.resisted(live.dx, limit: limit)
    }

    private var gesture: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .updating($drag) { (value: DragGesture.Value, state: inout PageDrag?, transaction: inout Transaction) in
                let next: PageDrag = tracked(state, value: value)
                if state?.owns == true && !next.owns {
                    transaction.animation = Anim.standard
                }
                if next != state {
                    state = next
                }
            }
            .onChanged { (value: DragGesture.Value) in
                dragChanged(value)
            }
            .onEnded { (value: DragGesture.Value) in
                dragEnded(value)
            }
    }

    // MARK: - Deciding

    /// A drag's first change decides it for good: a swipe when clearly horizontal and the shell lets one start;
    /// to the right on Home, one toward the sidebar.
    private func start(_ translation: CGSize) -> (toSidebar: Bool, owns: Bool) {
        return (toSidebar: opensSidebar && translation.width > 0,
                owns: DragAxis.of(translation) == .horizontal && hooks.canStart())
    }

    /// The live drag after `value`: what its first change found, then its travel while it still counts. A swipe
    /// toward the sidebar keeps no travel here, and a scroll is the same value throughout, so neither writes on
    /// every frame.
    private func tracked(_ previous: PageDrag?, value: DragGesture.Value) -> PageDrag {
        guard let live: PageDrag = previous else {
            let first: (toSidebar: Bool, owns: Bool) = start(value.translation)
            return PageDrag(owns: first.owns,
                            toSidebar: first.toSidebar,
                            dx: first.owns && !first.toSidebar ? value.translation.width : 0)
        }
        guard live.owns else { return live }
        guard hooks.canContinue(live.toSidebar) else {
            return PageDrag(owns: false, toSidebar: live.toSidebar, dx: 0)
        }
        return PageDrag(owns: true, toSidebar: live.toSidebar, dx: live.toSidebar ? 0 : value.translation.width)
    }

    /// Mirrors `tracked` for the release, and tells the shell when a swipe takes its touch, turns round or stops
    /// counting; Home's swipe toward the sidebar, on every change.
    private func dragChanged(_ value: DragGesture.Value) {
        let travel: CGFloat = value.translation.width
        guard var current: SwipeLatch = latch else {
            let first: (toSidebar: Bool, owns: Bool) = start(value.translation)
            latch = SwipeLatch(began: value.time, toSidebar: first.toSidebar, forward: travel < 0, blocked: !first.owns)
            if first.owns {
                hooks.changed(first.toSidebar ? PageSwipe.sidebar(travel: travel) : PageSwipe.page(forward: travel < 0))
            }
            return
        }
        guard !current.blocked else { return }
        if !hooks.canContinue(current.toSidebar) {
            current.blocked = true
            latch = current
            hooks.changed(nil)
        } else if current.toSidebar {
            hooks.changed(PageSwipe.sidebar(travel: travel))
        } else if travel != 0 && (travel < 0) != current.forward {
            current.forward = travel < 0
            latch = current
            hooks.changed(PageSwipe.page(forward: current.forward))
        }
    }

    /// Let go: Home's swipe to the right opens the sidebar if it went far enough; any other moves to the
    /// neighbouring page once it has gone far enough. A drag on Home that lasted `holdLimit`, a swipe or not,
    /// tells the shell first.
    private func dragEnded(_ value: DragGesture.Value) {
        guard let current: SwipeLatch = latch else { return }
        latch = nil
        let held: TimeInterval = value.time.timeIntervalSince(current.began)
        if let limit: TimeInterval = holdLimit, held >= limit {
            hooks.heldLong()
        }
        guard !current.blocked else { return }
        if current.toSidebar {
            hooks.releaseToSidebar(value)
        } else if let forward: Bool = target(value, swipe: current, held: held) {
            hooks.commit(forward)
        }
        hooks.changed(nil)
    }

    /// Forward (the next page) or back, once the swipe would carry the page past a third of the width: a slow
    /// one by how far it went, a fling by where it would end, so one flung back stays. nil toward no page,
    /// against the way the slide is set to go, and once it has lasted `holdLimit` (the orb's hold under it).
    private func target(_ value: DragGesture.Value, swipe: SwipeLatch, held: TimeInterval) -> Bool? {
        let travel: CGFloat = value.translation.width
        guard travel != 0, (travel < 0) == swipe.forward, swipe.forward ? hasNext : hasPrevious else { return nil }
        let predicted: CGFloat = swipe.forward ? -value.predictedEndTranslation.width : value.predictedEndTranslation.width
        guard predicted > width / 3 else { return nil }
        if let limit: TimeInterval = holdLimit, held >= limit {
            return nil
        }
        return swipe.forward
    }

    /// The drag went without an end of its own (the system took the touch), or the page left mid-drag: the
    /// shell keeps nothing of it.
    private func dropLatch() {
        guard let current: SwipeLatch = latch else { return }
        latch = nil
        if !current.blocked {
            hooks.changed(nil)
        }
    }
}

/// What the page's swipe asks of the shell, and tells it.
private struct SwipeHooks {
    /// On a drag's first change: may a swipe start now?
    let canStart: () -> Bool
    /// On every later change: does it still count? true: Home's swipe toward the sidebar.
    let canContinue: (Bool) -> Bool
    /// A swipe took its touch, turned round or moved the sidebar; nil once it has let go or stopped counting.
    let changed: (PageSwipe?) -> Void
    /// Let go far enough: the next page (true) or the previous one.
    let commit: (Bool) -> Void
    /// Home's swipe toward the sidebar let go: the panel opens if it went far enough.
    let releaseToSidebar: (DragGesture.Value) -> Void
    /// A drag on Home lasted the hold limit: a hold under it may still owe its seal.
    let heldLong: () -> Void
}

/// A swipe that owns its touch, as the shell needs it.
private enum PageSwipe: Equatable {
    /// Toward the next page (`forward`) or the previous one: the way the slide will go.
    case page(forward: Bool)
    /// Home's swipe to the right, and how far it has gone: the sidebar follows it.
    case sidebar(travel: CGFloat)
}

/// A live drag on the page, as its first change found it: whether it is a swipe that owns the touch (false for a
/// scroll, or a swipe that couldn't start or stopped counting), whether it is Home's swipe toward the sidebar,
/// and the travel the page follows.
private struct PageDrag: Equatable {
    let owns: Bool
    let toSidebar: Bool
    let dx: CGFloat
}

/// A page drag for its release.
private struct SwipeLatch {
    /// When the first change came: a hold on the orb under the drag began shortly before it.
    let began: Date
    /// To the right on Home: it brings the sidebar out rather than moving the page.
    let toSidebar: Bool
    /// Toward the next page: the way the finger last went, and the slide the shell has set up.
    var forward: Bool
    /// Not a swipe (vertical, or begun while one couldn't start), or one that stopped counting.
    var blocked: Bool
}

/// How the page follows a swipe.
private enum SwipeMetrics {
    /// How far the page can follow toward a neighbouring tab, and toward no tab at all (the rubber band at the
    /// first and last), as shares of the screen's width.
    static let followShare: CGFloat = 0.4
    static let bandShare: CGFloat = 0.1
    /// The rubber band's stiffness, as in a scroll view: 100 pt of travel moves the page about 40 pt.
    static let resistance: CGFloat = 0.55

    /// Nears `limit` without reaching it, like a scroll view's rubber band.
    static func resisted(_ travel: CGFloat, limit: CGFloat) -> CGFloat {
        guard limit > 0 else { return 0 }
        let eased: CGFloat = limit * (1 - 1 / (abs(travel) * SwipeMetrics.resistance / limit + 1))
        return travel < 0 ? -eased : eased
    }
}

/// The slide a released swipe started: which way the pages move.
private struct PageSlide: Equatable {
    let forward: Bool
    /// Tells one slide from the next, so a slide that ends late can't clear the one after it.
    let startedAt: TimeInterval
}

/// What stops a swipe from starting, read only then. A reference, so neither Chat's overlays coming and going
/// nor a long drag on Home renders the shell.
@MainActor
private final class SwipeGuard {
    /// Chat's "+" card, reaction picker or keyboard is up (`ChatActions.overlay`): a sideways drag there is
    /// theirs, and standing the page down for a swipe would take the keyboard away.
    var overlay: Bool = false
    /// Uptime until which a hold under a long drag on Home may still owe its seal.
    private var sealOwedUntil: TimeInterval = 0

    /// After this, from the lift, a seal is no longer owed: it comes `OrbTiming.sealDelay` after the hold
    /// completes, which is before the lift.
    private static let margin: TimeInterval = 0.2

    /// A drag on Home lasted `MainView.homeSwipeLimit`. A hold on the orb under it that moved within the dim
    /// gate completes with the room lit, so nothing else keeps Home on screen, and its seal comes
    /// `OrbTiming.sealDelay` later: until then a swipe or a tab would take the orb away, and its teardown drops
    /// the seal.
    func longDragEnded() {
        sealOwedUntil = ProcessInfo.processInfo.systemUptime + OrbTiming.sealDelay + SwipeGuard.margin
    }

    var owesSeal: Bool {
        ProcessInfo.processInfo.systemUptime < sealOwedUntil
    }
}
