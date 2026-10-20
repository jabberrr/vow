import SwiftUI

/// You: your letter and name, your total balance with its supporting numbers, and your name to edit.
/// Opened from your row at the bottom of the sidebar. The name saves on Return and when the sheet closes.
struct ProfileSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .largeTitle) private var balanceSize: CGFloat = 48

    @State private var name: String = ""
    @State private var didLoad: Bool = false
    /// A name was saved during this visit. The toast waits for the sheet to close (it would sit behind it).
    @State private var savedName: Bool = false

    init() {}

    private var displayName: String {
        store.profile?.displayName ?? ""
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSaveName: Bool {
        !trimmedName.isEmpty && trimmedName != displayName
    }

    var body: some View {
        content(all: store.summaries(), tests: store.testGroupIDs)
            .onAppear(perform: load)
            .onDisappear(perform: finish)
    }

    /// One Settlement pass per body (`all`), shared by every number on the sheet.
    private func content(all: [GroupID: GroupSummary], tests: Set<GroupID>) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                closeRow
                profile
                    .padding(.top, -14)
                balance(Overview.balance(all))
                    .padding(.top, 22)
                stats(all: all, tests: tests)
                    .padding(.top, 18)
                nameSection
                    .padding(.top, Gap.xxl)
            }
            .padding(.horizontal, Gap.gutter)
            .padding(.top, Gap.l)
            .padding(.bottom, Gap.section)
        }
        .scrollDismissesKeyboard(.interactively)
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
        }
    }

    // MARK: - Balance

    /// Neutral, like every total: only your own change (Yesterday) is coloured.
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
        .accessibilityValue(ProfileSheet.spokenPoints(total))
    }

    /// Real groups only: test days are moved by hand, so they say nothing about the days you kept.
    private func stats(all: [GroupID: GroupSummary], tests: Set<GroupID>) -> some View {
        let yesterday: Double = Overview.yesterdayChange(all, tests: tests)
        let kept: Int = Overview.daysKept(all, tests: tests)
        let best: Int = Overview.bestStreak(all, tests: tests)
        return HStack(spacing: 0) {
            statColumn(value: ProfileSheet.pointsText(yesterday), color: Ink.points(yesterday),
                       label: "Yesterday", spoken: ProfileSheet.spokenPoints(yesterday))
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

    // MARK: - Name

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldLabel("Name")
            VowTextField("Name", text: $name, capitalization: .words)
                .onSubmit(saveName)
            FieldFooter("Your groups see this.")
        }
    }

    // MARK: - Actions

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        name = displayName
    }

    private func saveName() {
        guard canSaveName else { return }
        store.saveProfile(displayName: trimmedName)
        savedName = true
    }

    /// On the way out: save a changed name, then confirm any save made during this visit.
    private func finish() {
        saveName()
        if savedName {
            store.toast = "Name saved."
        }
    }

    // MARK: - Points text

    private static func isZero(_ value: Double) -> Bool {
        return (abs(value) * 100).rounded() == 0
    }

    /// "+1 pt", "−2 pts", "0 pts" (never "+0").
    private static func pointsText(_ value: Double) -> String {
        let parts: (number: String, unit: String) = PointsText.balanceParts(value)
        return parts.unit.isEmpty ? parts.number : parts.number + " " + parts.unit
    }

    private static func spokenPoints(_ value: Double) -> String {
        return PointsText.spoken(value, signed: !ProfileSheet.isZero(value))
    }
}
