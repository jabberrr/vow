import SwiftUI

/// The selected group's four pages, pinned at the bottom. Custom rather than a `TabView`: it uses the
/// app's tokens, dims with the room during a hold and avoids iOS 26's floating tab bar. Tint and fill
/// carry the selection, as in iOS. The Streak flame lights (in the streak's own gradient) once you have
/// kept today, from the social beat on.
struct VowTabBar: View {
    let selection: MainTab
    let streakLit: Bool
    let dimmed: Bool
    let onSelect: (MainTab) -> Void

    private static let symbolFont: Font = Font.system(size: 22, weight: .medium)
    private static let symbolHeight: CGFloat = 28

    init(selection: MainTab, streakLit: Bool, dimmed: Bool, onSelect: @escaping (MainTab) -> Void) {
        self.selection = selection
        self.streakLit = streakLit
        self.dimmed = dimmed
        self.onSelect = onSelect
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(MainTab.allCases) { (tab: MainTab) in
                item(tab)
            }
        }
        .frame(height: Gap.tabBar)
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

    /// Fixed sizes like the system tab bar; a long press shows the Large Content Viewer instead.
    private func item(_ tab: MainTab) -> some View {
        let selected: Bool = tab == selection
        return Button {
            onSelect(tab)
        } label: {
            VStack(spacing: 3) {
                symbol(tab, selected: selected)
                    .frame(height: VowTabBar.symbolHeight)
                Text(tab.title)
                    .font(Fonts.tabLabel)
                    .foregroundStyle(selected ? Ink.text : Ink.text3)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: Gap.tabBar)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(tab.title)
        .accessibilityValue(tab == .streak && streakLit ? "Kept today" : "")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityShowsLargeContentViewer {
            Label(tab.title, systemImage: selected ? tab.selectedSymbol : tab.symbol)
        }
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
            .font(VowTabBar.symbolFont)
            .foregroundStyle(selected ? Ink.text : Ink.text3)
    }

    /// Both images stay stacked and cross-fade, so the light-up at the social beat is soft (also under
    /// Reduce Motion: it is a fade in place).
    private func streakSymbol(selected: Bool) -> some View {
        ZStack {
            plainSymbol(.streak, selected: selected)
                .opacity(streakLit ? 0 : 1)
            Image(systemName: MainTab.streak.selectedSymbol)
                .font(VowTabBar.symbolFont)
                .foregroundStyle(Ink.flameGradient)
                .opacity(streakLit ? 1 : 0)
        }
        .animation(Anim.light, value: streakLit)
    }
}
