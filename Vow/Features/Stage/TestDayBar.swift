import SwiftUI
import UIKit

/// Test controls for the owner of a test group in testing mode, and the only place they live: Next day
/// (fills) and Reset (the shell asks first). StageScreen owns Next day's busy guard. A finished test vow
/// keeps the bar with Next day disabled, so it can still be reset. Sits in the content under the strip,
/// so it can never cover who kept today.
struct TestDayBar: View {
    let metrics: StageMetrics
    let busy: Bool
    /// False once the vow is finished: nothing follows the final day.
    let canAdvance: Bool
    let onNextDay: () -> Void
    let onReset: () -> Void

    init(metrics: StageMetrics, busy: Bool, canAdvance: Bool, onNextDay: @escaping () -> Void, onReset: @escaping () -> Void) {
        self.metrics = metrics
        self.busy = busy
        self.canAdvance = canAdvance
        self.onNextDay = onNextDay
        self.onReset = onReset
    }

    /// Inner padding of the bar; it is part of each button's target, so the targets fill the bar.
    private static let inset: CGFloat = 6
    private static let resetWidth: CGFloat = 100
    private static let disabledOpacity: Double = 0.35

    private var buttonHeight: CGFloat {
        metrics.testBarHeight - 2 * TestDayBar.inset
    }

    var body: some View {
        HStack(spacing: TestDayBar.inset) {
            nextButton
            resetButton
        }
        .padding(.horizontal, TestDayBar.inset)
        .frame(minHeight: metrics.testBarHeight)
        .background(Capsule().fill(Ink.card))
        .overlay(Capsule().strokeBorder(Ink.hairline, lineWidth: 1))
        .padding(.horizontal, Gap.barInset)
    }

    private var nextButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onNextDay()
        } label: {
            nextLabel
                .frame(maxWidth: .infinity, minHeight: buttonHeight)
                .background(Capsule().fill(Ink.primary))
                .opacity(canAdvance ? 1 : TestDayBar.disabledOpacity)
                .padding(.vertical, TestDayBar.inset)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .disabled(busy || !canAdvance)
        .accessibilityLabel("Next day")
    }

    private var nextLabel: some View {
        ZStack {
            HStack(spacing: Gap.s) {
                Image(systemName: "forward.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .accessibilityHidden(true)
                Text("Next day")
            }
            .opacity(busy ? 0 : 1)
            if busy {
                ProgressView()
                    .tint(Ink.onPrimary)
            }
        }
        .font(Fonts.headline)
        .foregroundStyle(Ink.onPrimary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.horizontal, Gap.l)
    }

    private var resetButton: some View {
        Button(action: onReset) {
            Text("Reset")
                .font(Fonts.headline)
                .foregroundStyle(Ink.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, Gap.l)
                .frame(minWidth: TestDayBar.resetWidth, minHeight: buttonHeight)
                .background(Capsule().fill(Ink.field))
                .padding(.vertical, TestDayBar.inset)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .disabled(busy)
        .opacity(busy ? 0.5 : 1)
        .accessibilityLabel("Reset group")
    }
}
