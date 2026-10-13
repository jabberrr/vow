import SwiftUI

/// The pinned global row: the main menu (labelled with your total balance) and Settings. Global
/// scope only; everything about one vow lives on its stage below. Only the contents dim during a
/// hold; MainView draws the backing.
struct GlobalBar: View {
    let metrics: StageMetrics
    let balance: Double
    let yesterday: Double
    let dimmed: Bool
    /// No sheet up and the room lit: the bar can be seen, so the morning reveal may play.
    let canReveal: Bool
    let onMenu: () -> Void
    let onSettings: () -> Void

    init(metrics: StageMetrics,
         balance: Double,
         yesterday: Double,
         dimmed: Bool,
         canReveal: Bool,
         onMenu: @escaping () -> Void,
         onSettings: @escaping () -> Void) {
        self.metrics = metrics
        self.balance = balance
        self.yesterday = yesterday
        self.dimmed = dimmed
        self.canReveal = canReveal
        self.onMenu = onMenu
        self.onSettings = onSettings
    }

    var body: some View {
        HStack(alignment: .center, spacing: Gap.m) {
            MenuButton(balance: balance, yesterday: yesterday, canReveal: canReveal, action: onMenu)
                .layoutPriority(1)
            Spacer(minLength: 0)
            SettingsButton(action: onSettings)
        }
        .roomDim(dimmed)
        .padding(.horizontal, Gap.barInset)
        .padding(.vertical, metrics.barPadding)
        .frame(maxWidth: .infinity)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }
}

/// ≡ + "Total balance" over the amount. After the day's first completed sync, once the bar can be
/// seen, it reveals yesterday's real change for 2.5 s, once per local day.
struct MenuButton: View {
    let balance: Double
    let yesterday: Double
    let canReveal: Bool
    let action: () -> Void

    @Environment(AppStore.self) private var store
    /// Yesterday's change while it is revealed.
    @State private var revealAmount: Double? = nil
    private let prefs: Preferences = Preferences()

    init(balance: Double, yesterday: Double, canReveal: Bool, action: @escaping () -> Void) {
        self.balance = balance
        self.yesterday = yesterday
        self.canReveal = canReveal
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            label
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("Menu")
        .accessibilityValue(spokenValue)
        .accessibilityHint("Your vows, balance and settings")
        .task(id: RevealKey(synced: store.lastSyncedAt, visible: canReveal)) {
            guard store.lastSyncedAt != nil, canReveal else { return }
            await revealIfNeeded()
        }
    }

    private var label: some View {
        HStack(spacing: 11) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Ink.text)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(caption)
                    .font(Fonts.caption2Semibold)
                    .foregroundStyle(captionColor)
                amount
            }
        }
        .lineLimit(1)
        .padding(.leading, 14)
        .padding(.trailing, 16)
        .padding(.vertical, 5)
        .frame(minHeight: Gap.hit)
        .background(Capsule().fill(Ink.field))
        .contentShape(Capsule())
    }

    private var amount: some View {
        let parts: (number: String, unit: String) = shownParts
        return HStack(alignment: .firstTextBaseline, spacing: Gap.xs) {
            Text(parts.number)
                .font(Fonts.pill)
                .monospacedDigit()
                .foregroundStyle(numberColor)
                .rollingNumber(shownValue)
            if !parts.unit.isEmpty {
                Text(parts.unit)
                    .font(Fonts.footnoteMedium)
                    .foregroundStyle(unitColor)
            }
        }
        .minimumScaleFactor(0.7)
    }

    // MARK: Values

    private var shownValue: Double {
        revealAmount ?? balance
    }

    /// "+14.5" / "pts" (never "+0"); during the reveal "+1" / "pt".
    private var shownParts: (number: String, unit: String) {
        if let change: Double = revealAmount {
            return PointsText.parts(change, signed: true)
        }
        return PointsText.balanceParts(balance)
    }

    private var caption: String {
        revealAmount == nil ? "Total balance" : "Yesterday"
    }

    private var captionColor: Color {
        if let change: Double = revealAmount {
            return Ink.points(change)
        }
        return Ink.text3
    }

    private var numberColor: Color {
        if let change: Double = revealAmount {
            return Ink.points(change)
        }
        return Ink.text
    }

    private var unitColor: Color {
        if let change: Double = revealAmount {
            return Ink.points(change)
        }
        return Ink.text2
    }

    /// "Total balance, plus 14.5 points" / "Yesterday, plus 1 point".
    private var spokenValue: String {
        if let change: Double = revealAmount {
            return "Yesterday, " + PointsText.spoken(change, signed: true)
        }
        let isZero: Bool = (abs(balance) * 100).rounded() == 0
        return "Total balance, " + PointsText.spoken(balance, signed: !isZero)
    }

    // MARK: Reveal

    /// A sync, or the bar becoming visible, re-runs the reveal check.
    private struct RevealKey: Equatable {
        let synced: Date?
        let visible: Bool
    }

    /// Called only while the bar can be seen. The day key is saved when the check runs, so a day is
    /// revealed at most once. The total always comes back, also when the wait is cancelled by the
    /// next sync or by the bar being covered.
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

/// ⚙ in a 44 pt circle.
struct SettingsButton: View {
    let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: "gearshape")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(Ink.text2)
                .frame(width: Gap.hit, height: Gap.hit)
                .background(Circle().fill(Ink.field))
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("Settings")
        .accessibilityShowsLargeContentViewer {
            Label("Settings", systemImage: "gearshape")
        }
    }
}
