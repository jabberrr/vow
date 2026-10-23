import SwiftUI

/// A page's vertical scroll that holds still while the page fits: no bounce and no movement, except a pull down
/// from the top to refresh. The content follows the finger with a scroll view's resistance, a spinner like the
/// system's fades in and turns above it, and past `PageScrollMetrics.trigger` the refresh starts with a light tap,
/// as the system's does. Let go, the page rests below the spinner until the refresh returns, then settles back.
/// A page that doesn't fit (a long history, many members, accessibility sizes) scrolls as usual, with the
/// system's pull to refresh.
///
/// One scroll view in both modes, so a page that grows or shrinks across the edge keeps its state (the calendar's
/// month) and never flashes: only what a drag does changes. Whether it fits is the content's measured height
/// against the viewport's plus `slack`, the page's empty bottom margin, which may go under the tab bar unseen; it is
/// kept here, so a change re-renders this wrapper and never the page's body (and its Settlement pass). The mode
/// holds while a pull owns its touch or its refresh runs. With VoiceOver on, a page that fits scrolls too, so a
/// three-finger swipe down at the top refreshes it as it does any scroll view.
///
/// A pull is decided on its first change, like the shell's tab swipe: only a drag that goes down and is at least
/// as tall as it is wide pulls, while the swipe takes only drags more than twice as wide as they are tall, so the
/// two never share a touch. While a pull owns its touch the content is disabled, so a finger let go over a button
/// (a member row, the calendar's ‹ ›) doesn't press it. Scrolling is disabled while the page fits, and that
/// reaches any scroll view inside the content too.
struct PageScroll<Content: View>: View {
    /// Bumped when the selected tab is tapped again: back to the top (nothing to do while the page fits).
    let topToken: Int
    /// The content is at least as tall as the viewport, for a page that centres itself (`EmptyStage`).
    let fillsHeight: Bool
    /// How far the content may run past the viewport and still hold still: its bottom padding, so only empty
    /// margin is ever out of sight.
    let slack: CGFloat
    let onRefresh: () async -> Void
    let content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion: Bool
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver: Bool
    /// The live pull: gesture state, so a drag the system cancels resets itself, and the page settles back.
    @GestureState(resetTransaction: Transaction(animation: PageScrollMetrics.settle))
    private var pull: PagePull? = nil
    /// The content's laid-out height, against the viewport's: whether the page fits.
    @State private var contentHeight: CGFloat = 0
    /// A refresh a pull started is running: the spinner stays, and the page rests below it once let go.
    @State private var refreshing: Bool = false

    init(topToken: Int = 0,
         fillsHeight: Bool = false,
         slack: CGFloat = 0,
         onRefresh: @escaping () async -> Void,
         @ViewBuilder content: () -> Content) {
        self.topToken = topToken
        self.fillsHeight = fillsHeight
        self.slack = slack
        self.onRefresh = onRefresh
        self.content = content()
    }

    /// A pull arms once, at the trigger: the refresh starts and the light tap comes then, as the system's do.
    var body: some View {
        let armed: Bool = pull?.armed == true
        return GeometryReader { (geometry: GeometryProxy) in
            scroll(viewport: geometry.size.height)
        }
        .onChange(of: armed) { (_: Bool, isArmed: Bool) in
            if isArmed {
                startRefresh()
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: armed) { (_: Bool, isArmed: Bool) -> Bool in
            isArmed
        }
    }

    // MARK: - Scroll

    /// Still while the page fits, where only a pull moves it; a plain scroll, with the system's pull to refresh,
    /// once it doesn't, and always under VoiceOver. Never switched under a live pull or the refresh it started, so
    /// the gesture isn't masked off mid-drag. The gesture is masked rather than removed, so the switch changes no
    /// view's identity.
    private func scroll(viewport: CGFloat) -> some View {
        let fits: Bool = contentHeight <= viewport + slack + PageScrollMetrics.tolerance
        let still: Bool = pull?.owns == true || refreshing || (!voiceOver && fits)
        return ScrollViewReader { (proxy: ScrollViewProxy) in
            ScrollView(.vertical, showsIndicators: false) {
                page(viewport: viewport)
            }
            .scrollDisabled(still)
            .refreshable {
                await onRefresh()
            }
            .onChange(of: topToken) { _, _ in
                withAnimation(Anim.standard) {
                    proxy.scrollTo(PageScrollMetrics.topID, anchor: .top)
                }
            }
        }
        // A pull from below a short page's content counts too.
        .contentShape(Rectangle())
        .simultaneousGesture(pullGesture(viewport: viewport), including: still ? .all : .subviews)
    }

    /// The content as the page lays it out, measured, with the spinner hanging above it; both follow a pull.
    private func page(viewport: CGFloat) -> some View {
        content
            .frame(minHeight: fillsHeight ? viewport : nil)
            .background(heightReader)
            .id(PageScrollMetrics.topID)
            .overlay(alignment: .top) {
                spinner
            }
            .offset(y: offset)
            .disabled(pull?.owns == true)
    }

    private var heightReader: some View {
        GeometryReader { (proxy: GeometryProxy) in
            Color.clear
                .onChange(of: proxy.size.height, initial: true) { (_: CGFloat, height: CGFloat) in
                    contentHeight = height
                }
        }
    }

    /// From where the pull began (below the spinner while a refresh runs) plus its travel; once let go, below the
    /// spinner until the refresh returns, else at the top.
    private var offset: CGFloat {
        guard let live: PagePull = pull, live.owns else {
            return refreshing ? PageScrollMetrics.rest : 0
        }
        return (live.duringRefresh ? PageScrollMetrics.rest : 0) + live.travel
    }

    // MARK: - Spinner

    /// Like the system's: fades in and turns once round on the way to the trigger, so it spins on from where it
    /// stopped, and stays until the refresh returns. Mounted only while it shows, so it never spins unseen.
    @ViewBuilder
    private var spinner: some View {
        let progress: CGFloat = spinnerProgress
        if progress > 0 {
            ProgressView()
                .tint(Ink.text3)
                .opacity(Double(progress))
                .rotationEffect(.degrees(reduceMotion || refreshing ? 0 : Double(progress) * PageScrollMetrics.turn))
                .frame(height: PageScrollMetrics.rest)
                .offset(y: -PageScrollMetrics.rest)
                .accessibilityHidden(true)
        }
    }

    /// 0…1: how near the trigger a pull from the top has come; 1 while refreshing.
    private var spinnerProgress: CGFloat {
        if refreshing {
            return 1
        }
        guard let live: PagePull = pull, live.owns else { return 0 }
        return min(1, live.travel / PageScrollMetrics.trigger)
    }

    // MARK: - Pull

    /// Alongside the page's own gestures and the shell's tab swipe, and only while the page holds still.
    private func pullGesture(viewport: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: PageScrollMetrics.minimumDistance, coordinateSpace: .global)
            .updating($pull) { (value: DragGesture.Value, state: inout PagePull?, _: inout Transaction) in
                let next: PagePull = PagePull.track(state,
                                                    translation: value.translation,
                                                    duringRefresh: refreshing,
                                                    viewport: viewport)
                if next != state {
                    state = next
                }
            }
    }

    /// Past the trigger: the refresh starts at once, while the finger is still down. A pull only arms when it
    /// began with no refresh running, so this never starts a second.
    private func startRefresh() {
        guard !refreshing else { return }
        refreshing = true
        Task { @MainActor in
            await onRefresh()
            withAnimation(PageScrollMetrics.settle) {
                refreshing = false
            }
        }
    }
}

/// A live pull, as its first change found it.
private struct PagePull: Equatable {
    /// Down, and at least as tall as it is wide. Anything else (up, or sideways for the tab swipe) is the page's,
    /// for the whole drag.
    let owns: Bool
    /// Begun while a refresh runs: it starts from below the spinner, and only moves the page.
    let duringRefresh: Bool
    /// The finger's travel at the first change, so the page starts from where it was instead of jumping.
    let origin: CGFloat
    /// How far the page has come down, after resistance.
    let travel: CGFloat
    /// It has come past the trigger: sticky, so one pull refreshes once.
    let armed: Bool

    /// Not a pull: written once, so a scroll or a swipe never re-renders the page on every frame.
    static let ignored: PagePull = PagePull(owns: false, duringRefresh: false, origin: 0, travel: 0, armed: false)

    static func track(_ previous: PagePull?, translation: CGSize, duringRefresh: Bool, viewport: CGFloat) -> PagePull {
        guard let live: PagePull = previous else {
            let owns: Bool = translation.height > 0 && translation.height >= abs(translation.width)
            guard owns else { return PagePull.ignored }
            return PagePull(owns: true, duringRefresh: duringRefresh, origin: translation.height, travel: 0, armed: false)
        }
        guard live.owns else { return live }
        let travel: CGFloat = PageScrollMetrics.resisted(translation.height - live.origin, reach: viewport)
        let armed: Bool = live.armed || (!live.duringRefresh && travel >= PageScrollMetrics.trigger)
        return PagePull(owns: true, duringRefresh: live.duringRefresh, origin: live.origin, travel: travel, armed: armed)
    }
}

/// How a page that holds still answers a pull.
private enum PageScrollMetrics {
    static let topID: String = "page-scroll-top"
    /// Layout rounding: content this much taller than the viewport still fits.
    static let tolerance: CGFloat = 0.5
    /// As for the shell's tab swipe, so both decide on the same first change.
    static let minimumDistance: CGFloat = 10
    /// How far the page comes down before it refreshes: about 140 pt of pull on any phone, like the system's.
    static let trigger: CGFloat = 70
    /// Where the page rests while it refreshes, with the spinner centred in the gap above it.
    static let rest: CGFloat = 56
    /// The rubber band's stiffness, as in a scroll view: 100 pt of pull moves a 650 pt page about 50 pt.
    static let resistance: CGFloat = 0.55
    /// The spinner's turn on the way to the trigger, in degrees.
    static let turn: Double = 360
    /// Back in place without overshoot, so Reduce Motion needs nothing else: a critically damped spring.
    static let settle: Animation = Animation.spring(response: 0.35, dampingFraction: 1)

    /// A scroll view's rubber band over `reach` (the viewport's height): nears it without reaching it, never up.
    static func resisted(_ travel: CGFloat, reach: CGFloat) -> CGFloat {
        guard travel > 0, reach > 0 else { return 0 }
        return reach * (1 - 1 / (travel * PageScrollMetrics.resistance / reach + 1))
    }
}
