import SwiftUI

/// The selected group's pages as one track that a swipe moves the way iOS pages do: the page under the finger and
/// its neighbour move together, edge to edge, point for point, and only the first and last tab stretch a little
/// past their edge (a rubber band). Let go past a third of the width, or flung there, the track carries on at the
/// finger's speed to the neighbour; otherwise it springs back. Once it has landed the shell selects that tab, and
/// since every page keeps its place in the track (`pagerSlot`: its tab's index times the width), the swap moves
/// nothing on screen. The track is clipped to the page area, so nothing moving ever reaches the bars around it.
///
/// The shell builds the pages: the selected one, the neighbours it keeps mounted beside it once it has rested, and a
/// neighbour a swipe heads for that isn't mounted yet (Home, or one reached before the page has rested), from when the
/// swipe takes its touch until it is over (`PageSwipe`). This wrapper holds the live drag and the landing itself, so
/// following the finger and every frame of a landing re-render only this view: the pages are values the shell built,
/// so no page's body runs again on any frame. The shell hears of a swipe taking its touch, turning round, being let
/// go toward the neighbour (`SwipeHooks.willLand`, for the tab bar) and landing, and renders only to mount a page or
/// change the tab. Mounting and unmounting happen in plain transactions, so nothing inside a page animates or
/// transitions of its own while the track moves.
///
/// It is a swipe surface alongside the pages' own gestures, so their scroll views, pulls to refresh, the orb's hold
/// and Chat's long presses keep theirs: a drag is decided on its first change, and only a clearly horizontal one
/// that the shell lets start is a swipe. On Home a swipe to the right brings the sidebar out instead, and the track
/// stays. While a swipe owns its touch, and until its track has landed, the pages are disabled, so a finger let go
/// over a button doesn't press it and a hold the swipe began on the orb lets go. A drag that begins while the track
/// is still landing lands it at once and starts from the tab it was going to, so a quick second swipe is never
/// lost. A drag that isn't a swipe leaves the pages alone, Chat's keyboard included. Reduce Motion: the track never
/// moves, and a swipe let go far enough crossfades to the neighbour.
struct PagerTrack<Content: View>: View {
    let width: CGFloat
    /// The selected tab's place in the track, and how many places there are.
    let index: Int
    let count: Int
    /// The page whose swipe to the right brings the sidebar out, as one from the edge does (Home).
    let sidebarIndex: Int
    /// How long a drag on that page may last and still change the page (`MainView.homeSwipeLimit`, while Home's
    /// orb can still be held); one that lasts longer may also leave a seal owed (`SwipeHooks.heldLong`).
    let holdLimit: TimeInterval?
    /// Bumped when the tab is chosen another way while a page swipe is under way (a tap, or a reminder sending you
    /// Home): a landing in flight leads nowhere now and is dropped, even one from the very tab chosen. A live drag
    /// stops counting by itself (`SwipeHooks.canContinue`).
    let dropToken: Int
    let hooks: SwipeHooks
    /// The mounted pages, each at its place in the track.
    let content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion: Bool
    /// The live drag. Gesture state, so a drag the system cancels resets itself (the track goes straight back).
    /// Its reset is never animated: a swipe let go hands the track to `landing` as the drag ends.
    @GestureState private var drag: PageDrag? = nil
    /// The same drag for its release and for what the shell hears (gesture state has reset by then). Cleared as
    /// it ends, and when the drag goes without an end of its own.
    @State private var latch: SwipeLatch? = nil
    /// Where the track is going once its swipe has let go or stopped counting, until it has landed.
    @State private var landing: TrackLanding? = nil

    init(width: CGFloat,
         index: Int,
         count: Int,
         sidebarIndex: Int,
         holdLimit: TimeInterval?,
         dropToken: Int,
         hooks: SwipeHooks,
         @ViewBuilder content: () -> Content) {
        self.width = width
        self.index = index
        self.count = count
        self.sidebarIndex = sidebarIndex
        self.holdLimit = holdLimit
        self.dropToken = dropToken
        self.hooks = hooks
        self.content = content()
    }

    var body: some View {
        ZStack {
            content
        }
        .offset(x: trackOffset)
        .disabled(isMoving)
        .simultaneousGesture(gesture)
        .clipped()
        .onChange(of: drag == nil) { (_: Bool, idle: Bool) in
            if idle {
                dropLatch()
            }
        }
        .onChange(of: index) {
            landing = nil
        }
        .onChange(of: dropToken) {
            landing = nil
        }
        .onDisappear {
            dropLatch()
            dropLanding()
        }
    }

    // MARK: - Track

    /// At rest the selected page sits at the origin: the track is moved back by its place. A landing, then a live
    /// swipe, moves it from there. Either one begun on a tab that has since been chosen another way no longer
    /// counts. Under Reduce Motion every page sits at the origin (`pagerSlot`) and the track never moves, so the
    /// crossfade's change of tab moves nothing either.
    private var trackOffset: CGFloat {
        guard !reduceMotion else { return 0 }
        let rest: CGFloat = -CGFloat(index) * width
        if let current: TrackLanding = landing, current.index == index {
            return rest + current.offset
        }
        if let live: PageDrag = drag, live.owns, !live.toSidebar, live.index == index {
            return rest + follow(live.dx)
        }
        return rest
    }

    /// A swipe owns its touch (Home's toward the sidebar included), or the track is still landing.
    private var isMoving: Bool {
        drag?.owns == true || landing != nil
    }

    /// Point for point toward a neighbour, never past it; toward no page at all, a rubber band.
    private func follow(_ dx: CGFloat) -> CGFloat {
        guard !stretches(dx) else {
            return SwipeMetrics.resisted(dx, limit: width * SwipeMetrics.bandShare)
        }
        return min(max(dx, -width), width)
    }

    /// Toward no page at all: back from the first tab, or on from the last.
    private func stretches(_ dx: CGFloat) -> Bool {
        return dx < 0 ? index + 1 >= count : index == 0
    }

    // MARK: - Gesture

    /// Global coordinates, so the track moving under the finger never feeds back into the travel.
    private var gesture: some Gesture {
        DragGesture(minimumDistance: SwipeMetrics.minimumDistance, coordinateSpace: .global)
            .updating($drag) { (value: DragGesture.Value, state: inout PageDrag?, _: inout Transaction) in
                let next: PageDrag = tracked(state, value: value)
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

    /// The tab a drag beginning now starts from: the one the track is landing on, if it still is.
    private var startIndex: Int {
        landing?.target ?? index
    }

    /// A drag's first change decides it for good: a swipe when clearly horizontal and the shell lets one start; to
    /// the right on the sidebar's page, one toward the sidebar.
    private func start(_ translation: CGSize, at base: Int) -> (toSidebar: Bool, owns: Bool) {
        return (toSidebar: base == sidebarIndex && translation.width > 0,
                owns: DragAxis.of(translation) == .horizontal && hooks.canStart())
    }

    /// The live drag after `value`: what its first change found, then its travel from where it was recognised
    /// (so the track doesn't jump by the recognition distance) while it still counts. A swipe toward the sidebar
    /// keeps no travel here, and a scroll is the same value throughout, so neither writes on every frame.
    private func tracked(_ previous: PageDrag?, value: DragGesture.Value) -> PageDrag {
        guard let live: PageDrag = previous else {
            let base: Int = startIndex
            let first: (toSidebar: Bool, owns: Bool) = start(value.translation, at: base)
            return PageDrag(index: base, owns: first.owns, toSidebar: first.toSidebar,
                            origin: value.translation.width, dx: 0)
        }
        guard live.owns else { return live }
        guard live.index == index, hooks.canContinue(live.toSidebar) else {
            return PageDrag(index: live.index, owns: false, toSidebar: live.toSidebar, origin: live.origin, dx: 0)
        }
        guard !live.toSidebar else { return live }
        return PageDrag(index: live.index, owns: true, toSidebar: false, origin: live.origin,
                        dx: value.translation.width - live.origin)
    }

    /// Mirrors `tracked` for the release, and tells the shell when a swipe takes its touch or turns round (past
    /// `SwipeMetrics.turnSlop`, so a finger resting near where it began doesn't send it back and forth between two
    /// neighbours the shell may have to mount); Home's swipe toward the sidebar, on every change. A drag that begins
    /// while the track is landing lands it first, without animation: the track is already at its destination's
    /// place, so only what is left of the spring is skipped.
    private func dragChanged(_ value: DragGesture.Value) {
        guard var current: SwipeLatch = latch else {
            let base: Int = startIndex
            let first: (toSidebar: Bool, owns: Bool) = start(value.translation, at: base)
            let forward: Bool = value.translation.width < 0
            endLanding()
            latch = SwipeLatch(began: value.time, index: base, origin: value.translation.width,
                               toSidebar: first.toSidebar, forward: forward, blocked: !first.owns)
            if first.owns {
                hooks.changed(first.toSidebar ? PageSwipe.sidebar(travel: value.translation.width)
                                              : PageSwipe.page(forward: forward))
            }
            return
        }
        guard !current.blocked else { return }
        let travel: CGFloat = value.translation.width - current.origin
        if current.index != index || !hooks.canContinue(current.toSidebar) {
            current.blocked = true
            latch = current
            stopped(current, travel: travel)
        } else if current.toSidebar {
            hooks.changed(PageSwipe.sidebar(travel: value.translation.width))
        } else if current.forward ? travel > SwipeMetrics.turnSlop : travel < -SwipeMetrics.turnSlop {
            current.forward = !current.forward
            latch = current
            hooks.changed(PageSwipe.page(forward: current.forward))
        }
    }

    /// The swipe stopped counting with the finger still down (the room dimmed, a presentation is coming, the
    /// sidebar opened under it, or the tab was chosen another way): the sidebar springs back, or the track goes
    /// back to rest from where the finger has it.
    private func stopped(_ swipe: SwipeLatch, travel: CGFloat) {
        guard !swipe.toSidebar, swipe.index == index, !reduceMotion else {
            hooks.changed(nil)
            return
        }
        land(from: follow(travel), on: index, velocity: 0)
    }

    /// Let go: Home's swipe to the right opens the sidebar if it went far enough; any other lands on the
    /// neighbour or back on this page. A drag on Home that lasted `holdLimit`, a swipe or not, tells the shell
    /// first. Bound for the neighbour, the shell hears so as the landing starts, and the tab bar moves then.
    private func dragEnded(_ value: DragGesture.Value) {
        guard let current: SwipeLatch = latch else { return }
        latch = nil
        let held: TimeInterval = value.time.timeIntervalSince(current.began)
        if let limit: TimeInterval = dragLimit(for: current.index), held >= limit {
            hooks.heldLong()
        }
        guard !current.blocked else { return }
        guard !current.toSidebar, current.index == index else {
            if current.toSidebar {
                hooks.releaseToSidebar(value)
            }
            hooks.changed(nil)
            return
        }
        let target: Int = landingTab(value, swipe: current, held: held)
        guard !reduceMotion else {
            if target != index {
                withAnimation(Anim.fade) {
                    hooks.landed(index, target)
                }
            } else {
                hooks.landed(index, index)
            }
            return
        }
        if target != index {
            hooks.willLand(target)
        }
        let travel: CGFloat = value.translation.width - current.origin
        land(from: follow(travel), on: target, velocity: stretches(travel) ? 0 : value.velocity.width)
    }

    /// The hold limit for a drag that began on the page at `base`: only the sidebar's page (Home) has one.
    private func dragLimit(for base: Int) -> TimeInterval? {
        return base == sidebarIndex ? holdLimit : nil
    }

    /// The neighbour on the swipe's side once the swipe would carry the track past a third of the width: a slow one
    /// by how far it went, a fling by where it would end, so one flung back stays. Never toward no page, once it has
    /// lasted the hold limit (the orb's hold under it), or when the shell can't change the tab now; this page then.
    private func landingTab(_ value: DragGesture.Value, swipe: SwipeLatch, held: TimeInterval) -> Int {
        let neighbour: Int = swipe.forward ? swipe.index + 1 : swipe.index - 1
        guard neighbour >= 0, neighbour < count else { return swipe.index }
        if let limit: TimeInterval = dragLimit(for: swipe.index), held >= limit {
            return swipe.index
        }
        let predicted: CGFloat = value.predictedEndTranslation.width - swipe.origin
        guard (swipe.forward ? -predicted : predicted) > width * SwipeMetrics.commitShare else { return swipe.index }
        return hooks.canLand() ? neighbour : swipe.index
    }

    // MARK: - Landing

    /// The track carries on from `offset`, where the finger left it, to the place of the tab at `target` (the
    /// neighbour, or this page), starting at the finger's speed. It is held at `offset` without animation, then
    /// set moving with the spring in the same call: SwiftUI applies a plain change and an animated one as two
    /// updates, in order, so the spring starts from the finger whether the drag's state resets before this or
    /// after (the landing takes precedence over the drag). A deadline ends a landing whose completion never comes.
    /// Already there (let go a whole width along, or where it began), it has landed.
    private func land(from offset: CGFloat, on target: Int, velocity: CGFloat) {
        let destination: CGFloat = CGFloat(index - target) * width
        guard abs(destination - offset) >= SwipeMetrics.arrived else {
            hooks.landed(index, target)
            return
        }
        let serial: TimeInterval = ProcessInfo.processInfo.systemUptime
        landing = TrackLanding(index: index, target: target, offset: offset, serial: serial)
        withAnimation(SwipeMetrics.landing(distance: destination - offset, velocity: velocity)) {
            landing = TrackLanding(index: index, target: target, offset: destination, serial: serial)
        } completion: {
            landingDone(serial)
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: SwipeMetrics.landingDeadlineNanos)
            landingDone(serial)
        }
    }

    /// The spring has arrived, or its deadline came first; nothing if a newer landing (or none) has taken its place.
    private func landingDone(_ serial: TimeInterval) {
        guard landing?.serial == serial else { return }
        endLanding()
    }

    /// The shell selects the tab the track was landing on before the landing is cleared, so the track's place is
    /// the same in every update on the way and nothing jumps; the page the track left goes in the same update.
    private func endLanding() {
        guard let current: TrackLanding = landing else { return }
        hooks.landed(current.index, current.target)
        landing = nil
    }

    /// The drag went without an end of its own (the system took the touch), or the track left mid-drag: the track
    /// is back at rest, and the shell keeps nothing of the swipe.
    private func dropLatch() {
        guard let current: SwipeLatch = latch else { return }
        latch = nil
        if !current.blocked {
            hooks.changed(nil)
        }
    }

    /// The track left while landing (another group): its neighbour goes with it.
    private func dropLanding() {
        guard landing != nil else { return }
        landing = nil
        hooks.changed(nil)
    }
}

extension View {
    /// A page's place in a `PagerTrack`: its tab's index times the width, so selecting it moves nothing on screen.
    func pagerSlot(_ index: Int, width: CGFloat) -> some View {
        self.modifier(PagerSlot(index: index, width: width))
    }
}

/// Under Reduce Motion every page sits at the origin, where the track's crossfade swaps them in place.
private struct PagerSlot: ViewModifier {
    let index: Int
    let width: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion: Bool

    init(index: Int, width: CGFloat) {
        self.index = index
        self.width = width
    }

    func body(content: Content) -> some View {
        content
            .offset(x: reduceMotion ? 0 : CGFloat(index) * width)
    }
}

/// What the track's swipe asks of the shell, and tells it.
struct SwipeHooks {
    /// On a drag's first change: may a swipe start now?
    let canStart: () -> Bool
    /// On every later change: does it still count? true: Home's swipe toward the sidebar.
    let canContinue: (Bool) -> Bool
    /// A swipe took its touch, turned round or moved the sidebar; nil once Home's swipe toward the sidebar has let
    /// go or stopped counting, or a swipe has gone without landing (the system took the touch, the track left).
    let changed: (PageSwipe?) -> Void
    /// Let go far enough: may the tab change now?
    let canLand: () -> Bool
    /// Let go toward the neighbour: the track is on its way to the tab at this place, and lands there unless the tab
    /// is chosen another way first. The tab bar shows it selected from now.
    let willLand: (Int) -> Void
    /// The track has landed: the place of the tab its swipe began on, and of the tab it landed on (the same one
    /// when it sprang back). The shell selects it at once; either way the swipe is over.
    let landed: (Int, Int) -> Void
    /// Home's swipe toward the sidebar let go: the panel opens if it went far enough.
    let releaseToSidebar: (DragGesture.Value) -> Void
    /// A drag on Home lasted the hold limit: a hold under it may still owe its seal.
    let heldLong: () -> Void
}

/// A swipe under way, as the shell needs it: from taking its touch until its track has landed.
enum PageSwipe: Equatable {
    /// Toward the next page (`forward`) or the previous one: the neighbour the shell mounts if it isn't already.
    case page(forward: Bool)
    /// Home's swipe to the right, and how far it has gone: the sidebar follows it.
    case sidebar(travel: CGFloat)
}

/// A live drag on the track, as its first change found it: the tab it began on, whether it is a swipe that owns the
/// touch (false for a scroll, a pull, or a swipe that couldn't start or stopped counting), whether it is Home's
/// swipe toward the sidebar, where the finger was when it was recognised, and how far it has come since.
private struct PageDrag: Equatable {
    let index: Int
    let owns: Bool
    let toSidebar: Bool
    let origin: CGFloat
    let dx: CGFloat
}

/// A drag on the track, for its release.
private struct SwipeLatch {
    /// When the first change came: a hold on the orb under the drag began shortly before it.
    let began: Date
    /// The tab's place it began on: a tab chosen another way meanwhile ends the swipe.
    let index: Int
    /// The finger's travel when the swipe was recognised: the track follows it from there.
    let origin: CGFloat
    /// To the right on Home: it brings the sidebar out rather than moving the track.
    let toSidebar: Bool
    /// Toward the next page: the neighbour it heads for.
    var forward: Bool
    /// Not a swipe (vertical, or begun while one couldn't start), or one that stopped counting.
    var blocked: Bool
}

/// The track after its swipe, until it lands.
private struct TrackLanding {
    /// The place of the tab the swipe began on, and of the tab it is landing on (the same one to spring back).
    let index: Int
    let target: Int
    /// From the first tab's rest: where the finger left the track, then where it is going.
    let offset: CGFloat
    /// Tells one landing from the next, so a late completion or deadline can't end a newer one.
    let serial: TimeInterval
}

/// How the track follows a swipe and lands.
private enum SwipeMetrics {
    /// As `PageScroll`'s pull and the sidebar's drags, so all of them decide on the same first change.
    static let minimumDistance: CGFloat = 10
    /// Let go past this share of the width (by where the swipe would end), the track goes to the neighbour.
    static let commitShare: CGFloat = 1.0 / 3.0
    /// How far back past where the swipe began the finger must come before the swipe heads for the other neighbour.
    static let turnSlop: CGFloat = 12
    /// The rubber band at the first and last tab: it nears this share of the width without reaching it.
    static let bandShare: CGFloat = 0.1
    /// The rubber band's stiffness, as in a scroll view.
    static let resistance: CGFloat = 0.55
    /// The landing spring's pace, about how long a landing from a standstill takes.
    static let landingSeconds: Double = 0.38
    /// A landing whose completion hasn't come by then ends anyway.
    static let landingDeadlineNanos: UInt64 = 1_000_000_000
    /// Closer than this to where it is going, the track has arrived: nothing is left to animate.
    static let arrived: CGFloat = 0.5

    /// Nears `limit` without reaching it, like a scroll view's rubber band.
    static func resisted(_ travel: CGFloat, limit: CGFloat) -> CGFloat {
        guard limit > 0 else { return 0 }
        let eased: CGFloat = limit * (1 - 1 / (abs(travel) * SwipeMetrics.resistance / limit + 1))
        return travel < 0 ? -eased : eased
    }

    /// A critically damped spring at the landing's pace that starts at the finger's speed: `velocity` in points a
    /// second, `distance` the way left to go. SwiftUI takes the initial velocity as a share of the distance a
    /// second; it is capped at the spring's natural frequency, past which it would overshoot, so the track never
    /// passes its destination.
    static func landing(distance: CGFloat, velocity: CGFloat) -> Animation {
        let omega: Double = 2 * Double.pi / SwipeMetrics.landingSeconds
        var share: Double = 0
        if abs(distance) >= 1 {
            share = min(max(Double(velocity / distance), -omega), omega)
        }
        return Animation.interpolatingSpring(mass: 1, stiffness: omega * omega, damping: 2 * omega,
                                             initialVelocity: share)
    }
}
