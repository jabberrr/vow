import SwiftUI

/// The main menu: you, your total balance and its supporting numbers, your vows, add a vow, Settings.
struct MenuSheet: View {
    let onSelectVow: (GroupID) -> Void
    let onCreate: () -> Void
    let onJoin: () -> Void
    let onSettings: () -> Void

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize: DynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var balanceSize: CGFloat = 48

    init(onSelectVow: @escaping (GroupID) -> Void,
         onCreate: @escaping () -> Void,
         onJoin: @escaping () -> Void,
         onSettings: @escaping () -> Void) {
        self.onSelectVow = onSelectVow
        self.onCreate = onCreate
        self.onJoin = onJoin
        self.onSettings = onSettings
    }

    var body: some View {
        content(all: store.summaries(), tests: store.testGroupIDs, now: Date())
    }

    /// One Settlement pass per body (`all`), shared by every number on the sheet.
    private func content(all: [GroupID: GroupSummary], tests: Set<GroupID>, now: Date) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                closeRow
                profile
                    .padding(.top, -14)
                balance(Overview.balance(all))
                    .padding(.top, 22)
                stats(all: all, tests: tests)
                    .padding(.top, 18)
                vowsHeader(all: all)
                    .padding(.top, Gap.xxl)
                vowsCard(items(all: all, now: now))
            }
            .padding(.horizontal, Gap.gutter)
            .padding(.top, Gap.l)
            .padding(.bottom, Gap.section)
        }
        .background(Ink.sheet.ignoresSafeArea())
    }

    // MARK: - You

    private var closeRow: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            SheetCloseButton(action: { dismiss() })
                .padding(.trailing, -8)
        }
    }

    private var displayName: String {
        store.profile?.displayName ?? ""
    }

    private var profile: some View {
        VStack(spacing: 0) {
            Text(NameFormat.initial(displayName))
                .font(.system(size: 27, weight: .heavy, design: .rounded))
                .foregroundStyle(Ink.text)
                .frame(width: 64, height: 64)
                .background(Circle().fill(Ink.avatar))
                .accessibilityHidden(true)
            Text(displayName)
                .font(Fonts.title2)
                .foregroundStyle(Ink.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
                .accessibilityAddTraits(.isHeader)
            PillButton("Settings", systemImage: "gearshape", kind: .secondary, compact: true, action: onSettings)
                .padding(.top, 10)
        }
    }

    // MARK: - Balance

    private func balance(_ total: Double) -> some View {
        let parts: (number: String, unit: String) = PointsText.balanceParts(total)
        return VStack(spacing: Gap.xs) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(parts.number)
                    .font(.system(size: balanceSize, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Ink.text)
                    .rollingNumber(total)
                if !parts.unit.isEmpty {
                    Text(parts.unit)
                        .font(Fonts.numberMedium)
                        .foregroundStyle(Ink.text2)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            Text("Total balance")
                .font(Fonts.footnote)
                .foregroundStyle(Ink.text2)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Total balance")
        .accessibilityValue(MenuSheet.spokenPoints(total))
    }

    private func stats(all: [GroupID: GroupSummary], tests: Set<GroupID>) -> some View {
        let yesterday: Double = Overview.yesterdayChange(all, tests: tests)
        let kept: Int = Overview.daysKept(all, tests: tests)
        let best: Int = Overview.bestStreak(all, tests: tests)
        return HStack(spacing: 0) {
            statColumn(value: MenuSheet.pointsText(yesterday), color: Ink.points(yesterday),
                       label: "Yesterday", spoken: MenuSheet.spokenPoints(yesterday))
            statDivider
            statColumn(value: "\(kept)", color: Ink.text, label: "Days kept", spoken: "\(kept)")
            statDivider
            statColumn(value: "\(best)", color: Ink.text, label: "Best streak", spoken: "\(best)")
        }
        .padding(.vertical, Gap.m)
        .fixedSize(horizontal: false, vertical: true)
        .cardSurface()
    }

    /// Plain numbers (a flame here would read as a current streak).
    private func statColumn(value: String, color: Color, label: String, spoken: String) -> some View {
        VStack(spacing: Gap.xxs) {
            Text(value)
                .font(Fonts.stat)
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(Fonts.footnote)
                .foregroundStyle(Ink.text2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Gap.xs)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(spoken)
    }

    private var statDivider: some View {
        Rectangle()
            .fill(Ink.hairline)
            .frame(width: 1)
            .accessibilityHidden(true)
    }

    // MARK: - Your vows

    private func vowsHeader(all: [GroupID: GroupSummary]) -> some View {
        let total: Int = Overview.vowCount(all)
        let kept: Int = Overview.keptTodayCount(all)
        return HStack(alignment: .firstTextBaseline, spacing: Gap.s) {
            Text("Your vows")
                .font(Fonts.headline)
                .foregroundStyle(Ink.text)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Gap.s)
            if total > 0 {
                Text("\(kept) of \(total) kept today")
                    .font(Fonts.subheadlineMedium)
                    .foregroundStyle(Ink.text2)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, Gap.xs)
        .padding(.bottom, 10)
    }

    /// Your vows in store order, then the two ways to add one.
    private func vowsCard(_ items: [MenuVowItem]) -> some View {
        VStack(spacing: 0) {
            ForEach(items) { item in
                vowRow(item)
                Hairline(leading: 70)
            }
            addRow(symbol: "plus", title: "New group", action: onCreate)
            Hairline(leading: 70)
            addRow(symbol: "link", title: "Join with a link", action: onJoin)
        }
        .cardSurface()
    }

    private func vowRow(_ item: MenuVowItem) -> some View {
        Button {
            onSelectVow(item.id)
        } label: {
            HStack(spacing: 14) {
                Sphere(theme: item.theme, state: item.state, size: 40, showsGlyph: true, ringColor: item.ringColor)
                vowText(item)
                if let streak = item.streak, let net = item.net {
                    vowNumbers(streak: streak, net: net)
                }
                chevron
            }
            .padding(.horizontal, Gap.l)
            .padding(.vertical, Gap.m)
            .frame(minHeight: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityLabel(item.name)
        .accessibilityValue(item.spoken)
    }

    private func vowText(_ item: MenuVowItem) -> some View {
        VStack(alignment: .leading, spacing: Gap.xxs) {
            HStack(spacing: Gap.s) {
                Text(item.name)
                    .font(Fonts.headline)
                    .foregroundStyle(Ink.text)
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                if item.isTest {
                    Tag("Test")
                }
            }
            if !item.subtitle.isEmpty {
                Text(item.subtitle)
                    .font(Fonts.footnote)
                    .foregroundStyle(Ink.text2)
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
            }
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func vowNumbers(streak: Int, net: Double) -> some View {
        VStack(alignment: .trailing, spacing: 3) {
            FlameStreak(count: streak, size: .small)
            Text(MenuSheet.pointsText(net))
                .font(Fonts.footnote)
                .monospacedDigit()
                .foregroundStyle(Ink.points(net))
                .lineLimit(1)
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Ink.text3)
            .accessibilityHidden(true)
    }

    private func addRow(symbol: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Ink.text)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Ink.field))
                    .accessibilityHidden(true)
                Text(title)
                    .font(Fonts.headline)
                    .foregroundStyle(Ink.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, Gap.l)
            .padding(.vertical, 10)
            .frame(minHeight: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
    }

    // MARK: - Data

    private func items(all: [GroupID: GroupSummary], now: Date) -> [MenuVowItem] {
        var out: [MenuVowItem] = []
        for id in store.groupIDs {
            guard let group: GroupInfo = store.snapshots[id]?.group, let summary: GroupSummary = all[id] else { continue }
            out.append(MenuSheet.item(id: id, group: group, summary: summary, now: now))
        }
        return out
    }

    private static func item(id: GroupID, group: GroupInfo, summary: GroupSummary, now: Date) -> MenuVowItem {
        let viewer: MemberStanding? = summary.viewer
        var state: SphereState = .unlit
        var status: String = "Not joined"
        var subtitle: String = "Write your vow to join"
        var streak: Int? = nil
        var net: Double? = nil
        if let me: MemberStanding = viewer {
            state = me.checkedInToday ? .lit : .open
            status = me.checkedInToday ? "Kept today" : "Your turn"
            subtitle = VowFormat.short(me.vow)
            streak = me.streak
            net = me.net
        }
        let atRisk: Bool = state == .open && DayWindow.isAtRisk(group, now: now)
        var spoken: String = group.isTest ? "Test, " + status : status
        if let me: MemberStanding = viewer {
            spoken += me.streak == 1 ? ", 1-day streak" : ", \(me.streak)-day streak"
            spoken += ", " + MenuSheet.spokenPoints(me.net)
        }
        return MenuVowItem(id: id,
                           name: group.name,
                           isTest: group.isTest,
                           theme: Overview.theme(summary),
                           state: state,
                           ringColor: atRisk ? Ink.flame : Ink.text,
                           subtitle: subtitle,
                           streak: streak,
                           net: net,
                           spoken: spoken)
    }

    private static func isZero(_ value: Double) -> Bool {
        (abs(value) * 100).rounded() == 0
    }

    /// "+1 pt", "−2 pts", "0 pts" (never "+0").
    private static func pointsText(_ value: Double) -> String {
        let parts: (number: String, unit: String) = PointsText.balanceParts(value)
        return parts.unit.isEmpty ? parts.number : parts.number + " " + parts.unit
    }

    private static func spokenPoints(_ value: Double) -> String {
        PointsText.spoken(value, signed: !MenuSheet.isZero(value))
    }
}

/// One row of "Your vows", computed once per body.
private struct MenuVowItem: Identifiable {
    let id: GroupID
    let name: String
    let isTest: Bool
    let theme: DailyTheme
    let state: SphereState
    let ringColor: Color
    let subtitle: String
    let streak: Int?
    let net: Double?
    let spoken: String
}
