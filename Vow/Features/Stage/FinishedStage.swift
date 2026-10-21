import SwiftUI

/// Home after the vow's final day: no orb and nothing to do today, only what you did over the whole vow,
/// in real numbers. A calm ending: your vow, a sphere in the final day's colours (lit if you kept that
/// day, dashed if you were excused) and "Kept 26 of 30 days" over your best streak. StageScreen puts the meta line ("Finished ·
/// Oct 30") above it and, for a test owner, the test bar below.
struct FinishedStage: View {
    let summary: GroupSummary
    let metrics: StageMetrics

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize: DynamicTypeSize

    init(summary: GroupSummary, metrics: StageMetrics) {
        self.summary = summary
        self.metrics = metrics
    }

    private static let sphereSize: CGFloat = 150

    var body: some View {
        VStack(spacing: 0) {
            if let viewer: MemberStanding = summary.viewer {
                vow(viewer)
                    .padding(.top, metrics.vowTop)
            }
            sphere
                .padding(.top, metrics.orbTop)
            if let viewer: MemberStanding = summary.viewer {
                totals(viewer)
                    .padding(.top, Gap.s)
            } else {
                line("This vow has ended.")
                    .padding(.top, Gap.s)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Vow (text: nothing is left to edit)

    private func vow(_ viewer: MemberStanding) -> some View {
        StageCenter.vowText(viewer.vow)
            .font(Fonts.vow)
            .multilineTextAlignment(.center)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 36)
            .frame(maxWidth: .infinity)
    }

    // MARK: - Sphere

    /// The final day's index; `currentDay` is the day after it once the vow is finished.
    private var finalDay: Int {
        summary.endDay ?? max(0, summary.currentDay - 1)
    }

    /// The final day as you lived it, by the group's verdict.
    private var finalState: SphereState {
        switch summary.viewer?.history.last {
        case .kept?:
            return .lit
        case .excused?:
            return .excused
        case .missed?, nil:
            return .unlit
        }
    }

    /// Centred in the orb's slot, where the orb used to be.
    private var sphere: some View {
        Sphere(theme: Overview.theme(day: finalDay),
               state: finalState,
               size: FinishedStage.sphereSize,
               showsGlyph: true)
            .frame(width: Gap.orbSlot, height: Gap.orbSlot)
    }

    // MARK: - Totals

    /// Your vow days are the closed days since you joined; kept counts the kept ones among them.
    private func totals(_ viewer: MemberStanding) -> some View {
        VStack(spacing: Gap.xs) {
            Text("Kept \(Digest.daysKept(viewer)) of " + DayText.count(viewer.history.count))
                .font(Fonts.headline)
                .foregroundStyle(Ink.text)
            Text("Best streak " + DayText.count(viewer.bestStreak))
                .font(Fonts.subheadline)
                .foregroundStyle(Ink.text2)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, Gap.gutter)
    }

    private func line(_ text: String) -> some View {
        Text(text)
            .font(Fonts.subheadline)
            .foregroundStyle(Ink.text2)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Gap.gutter)
    }
}
