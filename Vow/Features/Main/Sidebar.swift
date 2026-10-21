import SwiftUI

/// The left panel: Add group (with its small menu), your groups with today's status, Settings, and you
/// with your total balance. It holds what changes rarely or spans groups; the selected group's pages
/// are one tab away. The shell owns the slide, the scrim, the gestures and the panel's width. It keeps
/// this view mounted, so the panel slides (or, under Reduce Motion, fades) as one and nothing in it
/// appears mid-slide; while closed it is out of sight and hidden from VoiceOver, and each new appearance
/// starts with the Add menu closed.
struct Sidebar: View {
    let all: [GroupID: GroupSummary]
    let selected: GroupID?
    let holdingLightID: GroupID?
    let now: Date
    /// Open or opening: VoiceOver can reach the panel, and it is modal.
    let isOpen: Bool
    /// Open, or following a swipe from the edge. It turns true before the panel shows more than its edge.
    let isShown: Bool
    /// The panel is open, nothing is up or coming and the room is lit: the balance can reveal yesterday.
    let canReveal: Bool
    /// The home indicator's inset, which the footer dips into.
    let bottomInset: CGFloat
    let onSelect: (GroupID) -> Void
    let onCreate: () -> Void
    let onJoin: () -> Void
    let onSettings: () -> Void
    let onProfile: () -> Void
    /// VoiceOver's escape, once the Add menu is closed.
    let onClose: () -> Void

    @Environment(AppStore.self) private var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion: Bool
    @State private var menuOpen: Bool = false
    @AccessibilityFocusState private var addFocused: Bool

    /// How far past its trailing edge the panel's shadow still shows (its offset plus twice its blur): the
    /// shell parks a closed panel that much further out.
    static let shadowReach: CGFloat = Sidebar.shadowX + 2 * Sidebar.shadowRadius
    private static let shadowRadius: CGFloat = 24
    private static let shadowX: CGFloat = 8

    init(all: [GroupID: GroupSummary],
         selected: GroupID?,
         holdingLightID: GroupID?,
         now: Date,
         isOpen: Bool,
         isShown: Bool,
         canReveal: Bool,
         bottomInset: CGFloat,
         onSelect: @escaping (GroupID) -> Void,
         onCreate: @escaping () -> Void,
         onJoin: @escaping () -> Void,
         onSettings: @escaping () -> Void,
         onProfile: @escaping () -> Void,
         onClose: @escaping () -> Void) {
        self.all = all
        self.selected = selected
        self.holdingLightID = holdingLightID
        self.now = now
        self.isOpen = isOpen
        self.isShown = isShown
        self.canReveal = canReveal
        self.bottomInset = bottomInset
        self.onSelect = onSelect
        self.onCreate = onCreate
        self.onJoin = onJoin
        self.onSettings = onSettings
        self.onProfile = onProfile
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 0) {
            addRow
                .padding(.top, Gap.s)
            lower
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea(.container, edges: .bottom)
        .background(panelBackground)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(isOpen ? .isModal : [])
        .accessibilityAction(.escape) {
            escape()
        }
        .accessibilityHidden(!isOpen)
        .onChange(of: isShown) { (_: Bool, shown: Bool) in
            if shown {
                resetMenu()
            }
        }
        .onChange(of: isOpen) { (_: Bool, open: Bool) in
            addFocused = open
        }
    }

    private var panelBackground: some View {
        Ink.sheet
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(Ink.hairline)
                    .frame(width: 1)
            }
            .shadow(color: Color.black.opacity(0.4), radius: Sidebar.shadowRadius, x: Sidebar.shadowX, y: 0)
            .ignoresSafeArea()
    }

    // MARK: - Add group

    private var addRow: some View {
        Button(action: toggleMenu) {
            HStack(spacing: Gap.m) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Ink.text)
                    .frame(width: SidebarMetrics.lead, height: SidebarMetrics.lead)
                    .background(Circle().fill(menuOpen ? Ink.chip : Ink.field))
                    .accessibilityHidden(true)
                Text("Add group")
                    .font(Fonts.headline)
                    .foregroundStyle(Ink.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, Gap.s)
            .frame(minHeight: SidebarMetrics.row)
        }
        .buttonStyle(SidebarRowStyle(highlighted: menuOpen))
        .accessibilityFocused($addFocused)
    }

    /// The groups and the bottom rows. The Add menu drops over them (it never pushes the list), with a
    /// veil over the rest of the panel that closes it.
    private var lower: some View {
        VStack(spacing: 0) {
            groupList
                .padding(.top, Gap.s)
            footer
        }
        .overlay(alignment: .top) {
            menuLayer
        }
    }

    private var menuLayer: some View {
        ZStack(alignment: .top) {
            if menuOpen {
                veil
                    .transition(.opacity)
            }
            if menuOpen {
                AddGroupMenu(onCreate: onCreate, onJoin: onJoin)
                    .padding(.horizontal, Gap.m)
                    .padding(.top, Gap.xs)
                    .transition(menuTransition)
            }
        }
    }

    private var veil: some View {
        Color.black
            .opacity(0.3)
            .contentShape(Rectangle())
            .onTapGesture {
                closeMenu()
            }
            .accessibilityHidden(true)
    }

    private var menuAnimation: Animation {
        reduceMotion ? Anim.fade : Anim.standard
    }

    private var menuTransition: AnyTransition {
        if reduceMotion {
            return AnyTransition.opacity
        }
        return AnyTransition.opacity.combined(with: AnyTransition.scale(scale: 0.96, anchor: .top))
    }

    private func toggleMenu() {
        withAnimation(menuAnimation) {
            menuOpen.toggle()
        }
    }

    private func closeMenu() {
        guard menuOpen else { return }
        withAnimation(menuAnimation) {
            menuOpen = false
        }
    }

    /// A menu left open (New group and Join with a link close the panel under it) slides away with the
    /// panel, and is put away without animation when the panel next shows, before more than its edge is
    /// in sight.
    private func resetMenu() {
        guard menuOpen else { return }
        var reset: Transaction = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) {
            menuOpen = false
        }
    }

    /// The Add menu first, then the panel.
    private func escape() {
        if menuOpen {
            closeMenu()
            addFocused = true
        } else {
            onClose()
        }
    }

    // MARK: - Groups

    /// Every group in store order; scrolls when there are many (the shell's close drag only acts on a
    /// clearly horizontal drag, so this scroll is never stolen).
    private var groupList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                ForEach(store.groupIDs, id: \.self) { (id: GroupID) in
                    groupRow(id)
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    @ViewBuilder
    private func groupRow(_ id: GroupID) -> some View {
        if let group: GroupInfo = store.snapshots[id]?.group, let summary: GroupSummary = all[id] {
            SidebarGroupRow(group: group,
                            summary: summary,
                            status: Overview.status(summary, group: group, now: now, holdingLight: id == holdingLightID),
                            isSelected: id == selected,
                            action: { onSelect(id) })
        }
    }

    // MARK: - Settings and you

    private var footer: some View {
        VStack(spacing: 0) {
            Hairline(leading: 0)
                .padding(.horizontal, Gap.xxl)
                .padding(.bottom, Gap.s)
            settingsRow
            ProfileRow(name: store.profile?.displayName ?? "",
                       total: Overview.balance(all),
                       yesterday: Overview.yesterdayChange(all, tests: store.testGroupIDs),
                       canReveal: canReveal,
                       action: onProfile)
        }
        .padding(.bottom, footerBottom)
    }

    /// From the screen's bottom edge to the profile row, whose centre then sits level with the main
    /// screen's tab-bar items: `VowTabBar` centres them in the bar you see, its `Gap.tabBar` plus the home
    /// indicator's inset. Larger text grows the row upward. With no inset (iPhone SE), `Gap.s` above the edge.
    private var footerBottom: CGFloat {
        max((bottomInset + Gap.tabBar - SidebarMetrics.profile) / 2, Gap.s)
    }

    private var settingsRow: some View {
        Button(action: onSettings) {
            HStack(spacing: Gap.m) {
                Image(systemName: "gearshape")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(Ink.text2)
                    .frame(width: SidebarMetrics.lead, height: SidebarMetrics.lead)
                    .accessibilityHidden(true)
                Text("Settings")
                    .font(Fonts.body)
                    .foregroundStyle(Ink.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, Gap.s)
            .frame(minHeight: SidebarMetrics.row)
        }
        .buttonStyle(SidebarRowStyle(highlighted: false))
    }
}

/// The two ways to add a group, in a card that drops under Add group. Custom rather than a SwiftUI
/// `Menu`: a Menu is a UIKit presentation that is still closing when its item asks for a sheet.
struct AddGroupMenu: View {
    let onCreate: () -> Void
    let onJoin: () -> Void

    @AccessibilityFocusState private var firstFocused: Bool

    private static let rowHeight: CGFloat = 50

    init(onCreate: @escaping () -> Void, onJoin: @escaping () -> Void) {
        self.onCreate = onCreate
        self.onJoin = onJoin
    }

    var body: some View {
        VStack(spacing: 0) {
            row(symbol: "plus", title: "New group", action: onCreate)
                .accessibilityFocused($firstFocused)
            Hairline(leading: 56)
            row(symbol: "link", title: "Join with a link", action: onJoin)
        }
        .background(card)
        .clipShape(RoundedRectangle(cornerRadius: Corner.field, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Corner.field, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .background(shadow)
        .onAppear {
            firstFocused = true
        }
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: Corner.field, style: .continuous)
            .fill(Ink.toast)
    }

    /// Drawn behind the clipped card, like the toast's.
    private var shadow: some View {
        RoundedRectangle(cornerRadius: Corner.field, style: .continuous)
            .fill(Ink.toast)
            .shadow(color: Color.black.opacity(0.45), radius: 20, x: 0, y: 10)
    }

    private func row(symbol: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Gap.m) {
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Ink.text)
                    .frame(width: SidebarMetrics.lead)
                    .accessibilityHidden(true)
                Text(title)
                    .font(Fonts.body)
                    .foregroundStyle(Ink.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, Gap.m)
            .padding(.vertical, Gap.s)
            .frame(minHeight: AddGroupMenu.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
    }
}

/// One group: its status sphere (lit kept, ringed your turn, a flame ring in the last 4 h, dashed when
/// excused, unlit when overruled, not joined or finished), its name and your streak. The selected group has
/// the field fill.
struct SidebarGroupRow: View {
    let group: GroupInfo
    let summary: GroupSummary
    let status: VowStatus
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize: DynamicTypeSize

    init(group: GroupInfo, summary: GroupSummary, status: VowStatus, isSelected: Bool, action: @escaping () -> Void) {
        self.group = group
        self.summary = summary
        self.status = status
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Gap.m) {
                sphere
                name
                Spacer(minLength: Gap.s)
                trailing
            }
            .padding(.vertical, Gap.s)
            .frame(minHeight: SidebarMetrics.row)
        }
        .buttonStyle(SidebarRowStyle(highlighted: isSelected))
        .accessibilityLabel(group.name)
        .accessibilityValue(spokenValue)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var sphere: some View {
        Sphere(theme: Overview.theme(summary),
               state: sphereState,
               size: SidebarMetrics.lead,
               ringColor: status == .atRisk ? Ink.flame : Ink.text,
               glows: false)
            .animation(Anim.light, value: sphereState)
    }

    /// One line with the Test tag beside it; at accessibility sizes the name wraps and the tag goes under it.
    @ViewBuilder
    private var name: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Gap.xs) {
                nameText
                if group.isTest {
                    Tag("Test")
                }
            }
        } else {
            HStack(spacing: Gap.s) {
                nameText
                    .lineLimit(1)
                    .truncationMode(.tail)
                if group.isTest {
                    Tag("Test")
                        .fixedSize()
                }
            }
        }
    }

    private var nameText: some View {
        Text(group.name)
            .font(Fonts.headline)
            .foregroundStyle(Ink.text)
            .multilineTextAlignment(.leading)
    }

    /// Your streak while it counts (a grey 0 beside a ring that already says "your turn" is noise), also
    /// while an excuse pauses it; "Overruled" or "Finished" in words; nothing when not joined.
    @ViewBuilder
    private var trailing: some View {
        switch status {
        case .overruled:
            note("Overruled")
        case .finished:
            note("Finished")
        case .open, .atRisk, .kept, .excused:
            if streak > 0 {
                FlameStreak(count: streak, size: .small)
            }
        case .notJoined:
            EmptyView()
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(Fonts.footnote)
            .foregroundStyle(Ink.text3)
            .lineLimit(1)
    }

    private var streak: Int {
        summary.viewer?.streak ?? 0
    }

    private var sphereState: SphereState {
        switch status {
        case .kept: return .lit
        case .open, .atRisk: return .open
        case .excused: return .excused
        case .overruled, .notJoined, .finished: return .unlit
        }
    }

    /// "Test, Your turn, under 4 hours left, 12-day streak"; "Excused today, 12-day streak".
    private var spokenValue: String {
        var text: String = group.isTest ? "Test, " : ""
        switch status {
        case .open: text += "Your turn"
        case .atRisk: text += "Your turn, under 4 hours left"
        case .kept: text += "Kept today"
        case .excused: text += "Excused today"
        case .overruled: text += "Overruled"
        case .notJoined: text += "Not joined"
        case .finished: text += "Finished"
        }
        let counts: Bool = status == .open || status == .atRisk || status == .kept || status == .excused
        if counts && streak > 0 {
            text += streak == 1 ? ", 1-day streak" : ", \(streak)-day streak"
        }
        return text
    }
}

/// You: your letter, your name and your total balance (neutral: it is the sum of your nets). On one line
/// when it fits; otherwise, and always at accessibility sizes, the balance goes under the name rather than
/// shrinking. The first time it is seen after the day's first sync, it reveals yesterday's real change
/// for 2.5 s, once per local day.
struct ProfileRow: View {
    let name: String
    let total: Double
    let yesterday: Double
    let canReveal: Bool
    let action: () -> Void

    @Environment(AppStore.self) private var store: AppStore
    @Environment(\.dynamicTypeSize) private var typeSize: DynamicTypeSize
    /// Yesterday's change while it is revealed.
    @State private var revealAmount: Double? = nil
    private let prefs: Preferences = Preferences()

    /// The panel's slide (about 0.35 s), then 300 ms: the reveal plays once the panel has settled.
    private static let revealDelayNanos: UInt64 = 650_000_000
    private static let avatarSize: CGFloat = 32

    init(name: String, total: Double, yesterday: Double, canReveal: Bool, action: @escaping () -> Void) {
        self.name = name
        self.total = total
        self.yesterday = yesterday
        self.canReveal = canReveal
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            content
                .padding(.vertical, Gap.s)
                .frame(minHeight: SidebarMetrics.profile)
        }
        .buttonStyle(SidebarRowStyle(highlighted: false))
        .accessibilityLabel(name)
        .accessibilityValue(spokenValue)
        .task(id: RevealKey(synced: store.lastSyncedAt, visible: canReveal)) {
            guard store.lastSyncedAt != nil, canReveal else { return }
            try? await Task.sleep(nanoseconds: ProfileRow.revealDelayNanos)
            if Task.isCancelled { return }
            await revealIfNeeded()
        }
    }

    @ViewBuilder
    private var content: some View {
        if typeSize.isAccessibilitySize {
            stacked
        } else {
            ViewThatFits(in: .horizontal) {
                inline
                stacked
            }
        }
    }

    private var inline: some View {
        HStack(spacing: Gap.m) {
            avatar
            nameText
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: Gap.s)
            balance
                .layoutPriority(1)
        }
    }

    private var stacked: some View {
        HStack(alignment: .top, spacing: Gap.m) {
            avatar
            VStack(alignment: .leading, spacing: Gap.xxs) {
                nameText
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                balance
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Fixed size, like the group spheres in the column above.
    private var avatar: some View {
        Text(NameFormat.initial(name))
            .font(.system(size: 14, weight: .heavy, design: .rounded))
            .foregroundStyle(Ink.text)
            .frame(width: ProfileRow.avatarSize, height: ProfileRow.avatarSize)
            .background(Circle().fill(Ink.avatar))
            .accessibilityHidden(true)
    }

    private var nameText: some View {
        Text(name)
            .font(Fonts.headline)
            .foregroundStyle(Ink.text)
            .multilineTextAlignment(.leading)
    }

    @ViewBuilder
    private var balance: some View {
        if let change: Double = revealAmount {
            revealed(change)
        } else {
            totalView
        }
    }

    /// "+14.5 pts" (never "+0"), one line, never truncated.
    private var totalView: some View {
        let parts: (number: String, unit: String) = PointsText.balanceParts(total)
        return HStack(alignment: .firstTextBaseline, spacing: Gap.xs) {
            Text(parts.number)
                .font(Fonts.pill)
                .monospacedDigit()
                .foregroundStyle(Ink.text)
                .rollingNumber(total)
            if !parts.unit.isEmpty {
                Text(parts.unit)
                    .font(Fonts.footnoteMedium)
                    .foregroundStyle(Ink.text2)
            }
        }
        .lineLimit(1)
        .fixedSize()
    }

    /// "Yesterday +1 pt", all in the colour of the change: the one coloured moment of the total.
    private func revealed(_ change: Double) -> some View {
        let parts: (number: String, unit: String) = PointsText.parts(change, signed: true)
        return HStack(alignment: .firstTextBaseline, spacing: Gap.s) {
            Text("Yesterday")
                .font(Fonts.footnoteMedium)
            HStack(alignment: .firstTextBaseline, spacing: Gap.xs) {
                Text(parts.number)
                    .font(Fonts.pill)
                    .monospacedDigit()
                if !parts.unit.isEmpty {
                    Text(parts.unit)
                        .font(Fonts.footnoteMedium)
                }
            }
        }
        .foregroundStyle(Ink.points(change))
        .lineLimit(1)
        .fixedSize()
    }

    /// "Total balance, plus 14.5 points" / "Yesterday, plus 1 point".
    private var spokenValue: String {
        if let change: Double = revealAmount {
            return "Yesterday, " + PointsText.spoken(change, signed: true)
        }
        let isZero: Bool = (abs(total) * 100).rounded() == 0
        return "Total balance, " + PointsText.spoken(total, signed: !isZero)
    }

    // MARK: - Reveal

    /// A sync, or the row becoming visible, re-runs the reveal check.
    private struct RevealKey: Equatable {
        let synced: Date?
        let visible: Bool
    }

    /// Called only while the row can be seen. The day is saved when the check runs, so a day is revealed
    /// at most once; never from cache. The total always comes back, also when closing the sidebar
    /// cancels the wait.
    @MainActor
    private func revealIfNeeded() async {
        let today: String = ReminderPlan.dayKey(Date(), calendar: Calendar.current)
        guard prefs.loadRevealDay() != today else { return }
        prefs.saveRevealDay(today)
        let change: Double = yesterday
        guard (abs(change) * 100).rounded() != 0 else { return }
        withAnimation(Anim.fade) {
            revealAmount = change
        }
        try? await Task.sleep(nanoseconds: Anim.revealNanos)
        withAnimation(Anim.fade) {
            revealAmount = nil
        }
    }
}

/// Shared geometry: every leading element is 32 wide, so all text starts at the same x.
private enum SidebarMetrics {
    static let lead: CGFloat = 32
    static let row: CGFloat = 52
    /// The profile row, at default text sizes: the footer centres it on the tab bar's items.
    static let profile: CGFloat = 60
}

/// Sidebar rows: inset 12 from the panel edges with 12 inside, the field fill when pressed or
/// highlighted (the selected group, Add group while its menu is open).
private struct SidebarRowStyle: ButtonStyle {
    let highlighted: Bool

    func makeBody(configuration: Configuration) -> some View {
        let shape: RoundedRectangle = RoundedRectangle(cornerRadius: Corner.field, style: .continuous)
        return configuration.label
            .padding(.horizontal, Gap.m)
            .background(shape.fill(configuration.isPressed || highlighted ? Ink.field : Color.clear))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .contentShape(shape)
            .padding(.horizontal, Gap.m)
            .animation(Anim.press, value: configuration.isPressed)
    }
}
