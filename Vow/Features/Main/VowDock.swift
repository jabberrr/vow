import SwiftUI

/// Every vow's status in peripheral vision and one-tap switching (pinned bottom): a chip per vow,
/// lit when kept, ringed when it is your turn (flame ring in the last 4 h), unlit when not joined.
/// Steps when space runs out: every chip full → unselected chips compact (status sphere and
/// initial) → a scrolling row that keeps the selected and the pulsed chip in view.
struct VowDock: View {
    let all: [GroupID: GroupSummary]
    let selected: GroupID?
    let holdingLightID: GroupID?
    let pulseID: GroupID?
    let pulseToken: Int
    let now: Date
    let dimmed: Bool
    let onSelect: (GroupID) -> Void
    let onCreate: () -> Void
    let onJoin: () -> Void

    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The chip scaled up by the next-vow pulse.
    @State private var pulsingID: GroupID? = nil

    private static let nameMaxWidth: CGFloat = 120
    private static let pulseHoldNanos: UInt64 = 250_000_000

    init(all: [GroupID: GroupSummary],
         selected: GroupID?,
         holdingLightID: GroupID?,
         pulseID: GroupID?,
         pulseToken: Int,
         now: Date,
         dimmed: Bool,
         onSelect: @escaping (GroupID) -> Void,
         onCreate: @escaping () -> Void,
         onJoin: @escaping () -> Void) {
        self.all = all
        self.selected = selected
        self.holdingLightID = holdingLightID
        self.pulseID = pulseID
        self.pulseToken = pulseToken
        self.now = now
        self.dimmed = dimmed
        self.onSelect = onSelect
        self.onCreate = onCreate
        self.onJoin = onJoin
    }

    var body: some View {
        let items: [DockChipItem] = chipItems()
        return HStack(spacing: Gap.xs) {
            chips(items)
                .frame(maxWidth: .infinity, alignment: .leading)
            addMenu
        }
        .roomDim(dimmed)
        .padding(.horizontal, Gap.s)
        .frame(height: Gap.dock)
        .background(dockCapsule)
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .onChange(of: pulseToken) {
            runPulse()
        }
    }

    private var dockCapsule: some View {
        Capsule()
            .fill(Ink.field)
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
    }

    // MARK: Steps

    private func chips(_ items: [DockChipItem]) -> some View {
        ViewThatFits(in: .horizontal) {
            chipRow(items, compact: false)
            chipRow(items, compact: true)
            scrollingRow(items)
        }
    }

    /// `compact`: unselected chips become status spheres; the selected chip keeps its name.
    private func chipRow(_ items: [DockChipItem], compact: Bool) -> some View {
        HStack(spacing: Gap.xs) {
            ForEach(items) { item in
                chip(item, compact: compact && !item.selected)
            }
        }
    }

    private func scrollingRow(_ items: [DockChipItem]) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                chipRow(items, compact: true)
                    .padding(.vertical, 2)
            }
            .onAppear {
                reveal(selected, proxy: proxy, animated: false)
            }
            .onChange(of: selected) { _, id in
                reveal(id, proxy: proxy, animated: true)
            }
            .onChange(of: pulseToken) {
                reveal(pulseID, proxy: proxy, animated: true)
            }
        }
    }

    private func reveal(_ id: GroupID?, proxy: ScrollViewProxy, animated: Bool) {
        guard let target: GroupID = id else { return }
        if animated && !reduceMotion {
            withAnimation(Anim.standard) {
                proxy.scrollTo(target, anchor: .center)
            }
        } else {
            proxy.scrollTo(target, anchor: .center)
        }
    }

    // MARK: Chips

    private func chip(_ item: DockChipItem, compact: Bool) -> some View {
        chipButton(item, compact: compact)
            .scaleEffect(pulsingID == item.id ? 1.08 : 1)
            .id(item.id)
            .accessibilityLabel(item.name)
            .accessibilityValue(item.statusText)
            .accessibilityAddTraits(item.selected ? .isSelected : [])
            .accessibilityShowsLargeContentViewer {
                Label(item.name, systemImage: "circle.fill")
            }
    }

    private func chipButton(_ item: DockChipItem, compact: Bool) -> some View {
        Button {
            onSelect(item.id)
        } label: {
            chipLabel(item, compact: compact)
        }
        .buttonStyle(PressStyle())
    }

    @ViewBuilder
    private func chipLabel(_ item: DockChipItem, compact: Bool) -> some View {
        if compact {
            compactChip(item)
        } else {
            fullChip(item)
        }
    }

    private func fullChip(_ item: DockChipItem) -> some View {
        HStack(spacing: 9) {
            sphere(item, size: 24, initial: nil)
            nameLabel(item)
        }
        .padding(.leading, 9)
        .padding(.trailing, 14)
        .frame(height: Gap.hit)
        .background(Capsule().fill(item.selected ? Ink.chip : Color.clear))
        .overlay(testBorder(item))
        .contentShape(Capsule())
    }

    /// 44 × 44: the status sphere with the vow's initial.
    private func compactChip(_ item: DockChipItem) -> some View {
        sphere(item, size: 28, initial: item.initial)
            .frame(width: Gap.hit, height: Gap.hit)
            .overlay(testBorder(item))
            .contentShape(Circle())
    }

    private func nameLabel(_ item: DockChipItem) -> some View {
        let layout: DockLabelWidth = DockLabelWidth(maxWidth: VowDock.nameMaxWidth)
        return layout {
            Text(item.name)
                .font(item.selected ? Fonts.subheadlineSemibold : Fonts.subheadlineMedium)
                .foregroundStyle(item.selected ? Ink.text : Ink.text2)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private func sphere(_ item: DockChipItem, size: CGFloat, initial: String?) -> some View {
        Sphere(theme: item.theme,
               state: item.state,
               size: size,
               initial: initial,
               showsGlyph: false,
               ringColor: item.ringColor,
               glows: false)
            .animation(Anim.light, value: item.state)
    }

    /// Test groups: a dashed outline.
    @ViewBuilder
    private func testBorder(_ item: DockChipItem) -> some View {
        if item.isTest {
            Capsule()
                .strokeBorder(Color.white.opacity(0.28), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .allowsHitTesting(false)
        }
    }

    private var addMenu: some View {
        Menu {
            Button(action: onCreate) {
                Label("New group", systemImage: "plus")
            }
            Button(action: onJoin) {
                Label("Join with a link", systemImage: "link")
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Ink.text2)
                .frame(width: Gap.hit, height: Gap.hit)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Add a group")
    }

    // MARK: Pulse

    /// Seal + 2.0 s: the next open vow scales once (not when Reduce Motion is on; the scroll
    /// into view still happens).
    private func runPulse() {
        guard let id: GroupID = pulseID, !reduceMotion else { return }
        withAnimation(Anim.pulse) {
            pulsingID = id
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: VowDock.pulseHoldNanos)
            withAnimation(Anim.pulse) {
                pulsingID = nil
            }
        }
    }

    // MARK: Items

    private func chipItems() -> [DockChipItem] {
        var groups: [GroupInfo] = []
        for id in store.groupIDs {
            if let group: GroupInfo = store.snapshots[id]?.group {
                groups.append(group)
            }
        }
        let initials: [String] = VowDock.chipInitials(groups.map { $0.name })
        var out: [DockChipItem] = []
        for (index, group) in groups.enumerated() {
            out.append(chipItem(group, initial: initials[index]))
        }
        return out
    }

    private func chipItem(_ group: GroupInfo, initial: String) -> DockChipItem {
        let id: GroupID = group.id
        let summary: GroupSummary? = all[id]
        let state: SphereState = chipState(id, summary: summary)
        let atRisk: Bool = state == .open && DayWindow.isAtRisk(group, now: now)
        let theme: DailyTheme
        if let s: GroupSummary = summary {
            theme = Overview.theme(s)
        } else {
            theme = DailyTheme.make(cycle: 1, day: 1)
        }
        return DockChipItem(id: id,
                            name: group.name,
                            initial: initial,
                            theme: theme,
                            state: state,
                            ringColor: atRisk ? Ink.flame : Ink.text,
                            isTest: group.isTest,
                            selected: id == selected)
    }

    /// Not a member → unlit; kept (and not held back for the social beat) → lit; else your turn.
    private func chipState(_ id: GroupID, summary: GroupSummary?) -> SphereState {
        guard let viewer: MemberStanding = summary?.viewer else { return .unlit }
        if viewer.checkedInToday && id != holdingLightID {
            return .lit
        }
        return .open
    }

    /// ["Morning Run", "Meditate", "Read"] -> ["MR", "Me", "R"]: one letter unless first letters collide.
    static func chipInitials(_ names: [String]) -> [String] {
        var firsts: [String] = []
        var counts: [String: Int] = [:]
        for name in names {
            let f: String = NameFormat.initial(name)
            firsts.append(f)
            counts[f, default: 0] += 1
        }
        var out: [String] = []
        for (index, name) in names.enumerated() {
            let f: String = firsts[index]
            guard (counts[f] ?? 0) > 1 else {
                out.append(f)
                continue
            }
            let words: [Substring] = name.split(separator: " ")
            if words.count > 1, let second: Character = words[1].first {
                out.append(f + String(second).uppercased())
            } else {
                let trimmed: String = name.trimmingCharacters(in: .whitespacesAndNewlines)
                out.append(f + String(trimmed.dropFirst().prefix(1)).lowercased())
            }
        }
        return out
    }
}

private struct DockChipItem: Identifiable {
    let id: GroupID
    let name: String
    let initial: String
    let theme: DailyTheme
    let state: SphereState
    let ringColor: Color
    let isTest: Bool
    let selected: Bool

    /// VoiceOver value.
    var statusText: String {
        switch state {
        case .lit: return "Kept today"
        case .open: return "Your turn"
        case .unlit, .missed: return "Not joined"
        }
    }
}

/// Hugs its one child but never offers it more than `maxWidth`, so a long vow name truncates at
/// that width instead of stretching the chip (a flexible frame would always fill its maximum).
private struct DockLabelWidth: Layout {
    let maxWidth: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child: LayoutSubview = subviews.first else { return CGSize.zero }
        return child.sizeThatFits(childProposal(proposal))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let child: LayoutSubview = subviews.first else { return }
        child.place(at: CGPoint(x: bounds.minX, y: bounds.midY),
                    anchor: .leading,
                    proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
    }

    private func childProposal(_ proposal: ProposedViewSize) -> ProposedViewSize {
        let offered: CGFloat = proposal.width ?? maxWidth
        return ProposedViewSize(width: min(offered, maxWidth), height: proposal.height)
    }
}
