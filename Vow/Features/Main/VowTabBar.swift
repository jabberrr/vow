import Observation
import SwiftUI

/// The selected group's five pages, pinned at the bottom. Custom rather than a `TabView`: it uses the
/// app's tokens, dims with the room during a hold and avoids iOS 26's floating tab bar. Tint and fill
/// carry the selection, as in iOS. A swipe let go toward a page shows that page selected at once
/// (`TabHighlight`), while its track is still on the way, so the bar keeps pace with the page rather than
/// with the end of its spring. The Streak flame lights (in the streak's own gradient) once your check-in
/// today stands, from the social beat on. Chat carries the app's one unread-style mark, a small white dot:
/// never a count, never red, and never while Chat shows selected. The items sit centred in the bar you see,
/// which runs on into the home-indicator inset, rather than in its top 49 pt.
struct VowTabBar: View {
    let selection: MainTab
    /// Read only here: the tab a swipe is landing on, shown selected in place of `selection`.
    let highlight: TabHighlight
    let streakLit: Bool
    /// Something new in the group's Chat since you last looked (the shell clears it while Chat is the page).
    let chatDot: Bool
    let dimmed: Bool
    /// The home-indicator inset under the bar (0 on phones without one).
    let bottomInset: CGFloat
    let onSelect: (MainTab) -> Void

    /// Heavier than the flame's, whose outline already reads strongly at this size.
    private static let symbolFont: Font = Font.system(size: 22, weight: .semibold)
    private static let streakFont: Font = Font.system(size: 22, weight: .medium)
    private static let symbolHeight: CGFloat = 28
    private static let dotSize: CGFloat = 7
    /// The bar's colour around the dot, so it reads apart from the symbol it overlaps.
    private static let dotRim: CGFloat = 11

    init(selection: MainTab,
         highlight: TabHighlight,
         streakLit: Bool,
         chatDot: Bool,
         dimmed: Bool,
         bottomInset: CGFloat,
         onSelect: @escaping (MainTab) -> Void) {
        self.selection = selection
        self.highlight = highlight
        self.streakLit = streakLit
        self.chatDot = chatDot
        self.dimmed = dimmed
        self.bottomInset = bottomInset
        self.onSelect = onSelect
    }

    /// The tab drawn selected, which VoiceOver hears as selected too: the one a swipe is landing on, else the page.
    var body: some View {
        let shown: MainTab = highlight.target ?? selection
        return HStack(spacing: 0) {
            ForEach(MainTab.allCases) { (tab: MainTab) in
                item(tab, selected: tab == shown, dot: tab == .chat && chatDot && shown != .chat)
            }
        }
        .frame(height: Gap.tabBar)
        .offset(y: bottomInset / 2)
        .roomDim(dimmed)
        .frame(maxWidth: .infinity)
        .background(backing)
        .dynamicTypeSize(.large)
        .accessibilityElement(children: .contain)
    }

    /// The backing and its hairline never dim.
    private var backing: some View {
        Ink.bg
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Ink.hairline)
                    .frame(height: 1)
            }
            .ignoresSafeArea(edges: .bottom)
    }

    // MARK: - Items

    /// Fixed sizes like the system tab bar; a long press shows the Large Content Viewer instead. Each item is
    /// as tall as the bar you see, inset included (the row overhangs its 49 pt frame and is offset down
    /// into the inset), so it can be tapped anywhere from the hairline to the screen's edge.
    private func item(_ tab: MainTab, selected: Bool, dot showsDot: Bool) -> some View {
        return Button {
            onSelect(tab)
        } label: {
            VStack(spacing: 3) {
                symbol(tab, selected: selected)
                    .frame(height: VowTabBar.symbolHeight)
                    .overlay(alignment: .topTrailing) {
                        if showsDot {
                            dot
                        }
                    }
                Text(tab.title)
                    .font(Fonts.tabLabel)
                    .foregroundStyle(selected ? Ink.text : Ink.text3)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: Gap.tabBar + bottomInset)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(tab.title)
        .accessibilityValue(value(tab, dot: showsDot))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityShowsLargeContentViewer {
            Label(tab.title, systemImage: selected ? tab.selectedSymbol : tab.symbol)
        }
    }

    /// "New messages" only while the dot shows.
    private func value(_ tab: MainTab, dot showsDot: Bool) -> String {
        if tab == .streak && streakLit {
            return "Kept today"
        }
        if showsDot {
            return "New messages"
        }
        return ""
    }

    /// Over the symbol's top trailing corner; it takes no touches and dims with the bar's contents.
    private var dot: some View {
        Circle()
            .fill(Ink.text)
            .frame(width: VowTabBar.dotSize, height: VowTabBar.dotSize)
            .padding((VowTabBar.dotRim - VowTabBar.dotSize) / 2)
            .background(Circle().fill(Ink.bg))
            .offset(x: 4, y: 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func symbol(_ tab: MainTab, selected: Bool) -> some View {
        if tab == .streak {
            streakSymbol(selected: selected)
        } else {
            plainSymbol(tab, selected: selected)
        }
    }

    private func plainSymbol(_ tab: MainTab, selected: Bool) -> some View {
        Image(systemName: selected ? tab.selectedSymbol : tab.symbol)
            .font(VowTabBar.font(tab))
            .foregroundStyle(selected ? Ink.text : Ink.text3)
    }

    private static func font(_ tab: MainTab) -> Font {
        return tab == .streak ? VowTabBar.streakFont : VowTabBar.symbolFont
    }

    /// Both images stay stacked and cross-fade, so the light-up at the social beat is soft (also under
    /// Reduce Motion: it is a fade in place).
    private func streakSymbol(selected: Bool) -> some View {
        ZStack {
            plainSymbol(.streak, selected: selected)
                .opacity(streakLit ? 0 : 1)
            Image(systemName: MainTab.streak.selectedSymbol)
                .font(VowTabBar.streakFont)
                .foregroundStyle(Ink.flameGradient)
                .opacity(streakLit ? 1 : 0)
        }
        .animation(Anim.light, value: streakLit)
    }
}

/// The tab a swipe between pages was let go toward, from that moment until its track has landed and the shell
/// selects it (or the swipe ends another way). Only the tab bar's body reads it, so setting it renders the bar alone,
/// never the shell, in the frame the landing starts.
@MainActor
@Observable
final class TabHighlight {
    var target: MainTab? = nil
}
