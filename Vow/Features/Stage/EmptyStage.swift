import SwiftUI

/// No groups yet: a stage waiting for its vow, on the same grid as a real one, with the one first
/// decision where the daily action will be. Centred between the top bar and the bottom edge (there is
/// no tab bar without a group). It holds still when it fits and scrolls when it doesn't, with a pull to
/// refresh either way (`PageScroll`): with no group there is no timed refresh, so that is the only way to
/// sync here.
struct EmptyStage: View {
    let metrics: StageMetrics
    let onCreate: () -> Void
    let onJoin: () -> Void

    @Environment(AppStore.self) private var store

    init(metrics: StageMetrics, onCreate: @escaping () -> Void, onJoin: @escaping () -> Void) {
        self.metrics = metrics
        self.onCreate = onCreate
        self.onJoin = onJoin
    }

    private static let theme: DailyTheme = DailyTheme.make(cycle: 1, day: 22)
    private static let sphereSize: CGFloat = 150
    /// Same tap padding around the vow line as the member stage.
    private static let vowTapPadding: CGFloat = 8

    var body: some View {
        PageScroll(fillsHeight: true, onRefresh: { await store.refreshAll() }) {
            VStack(spacing: 0) {
                Spacer(minLength: Gap.s)
                block
                Spacer(minLength: Gap.xxl)
            }
            .frame(maxWidth: .infinity)
        }
        .vowBackground()
    }

    private var block: some View {
        VStack(spacing: 0) {
            Text("Your first vow")
                .font(Fonts.footnoteMedium)
                .foregroundStyle(Ink.text2)
            vowButton
                .padding(.top, metrics.vowTop - EmptyStage.vowTapPadding)
            Sphere(theme: EmptyStage.theme, state: .unlit, size: EmptyStage.sphereSize, showsGlyph: true)
                .frame(width: Gap.orbSlot, height: Gap.orbSlot)
                .padding(.top, metrics.orbTop - EmptyStage.vowTapPadding)
            PillButton("New group", systemImage: "plus", action: onCreate)
                .padding(.horizontal, Gap.gutter)
                .padding(.top, metrics.streakTop)
            joinButton
                .padding(.top, Gap.m)
        }
        .frame(maxWidth: .infinity)
    }

    private var vowButton: some View {
        Button(action: onCreate) {
            Text("I will …")
                .font(Fonts.vow)
                .foregroundStyle(Ink.text3)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
                .padding(.vertical, EmptyStage.vowTapPadding)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        // "New group" below is the accessible path; this would only repeat it.
        .accessibilityHidden(true)
    }

    private var joinButton: some View {
        Button(action: onJoin) {
            HStack(spacing: Gap.s) {
                Image(systemName: "link")
                    .font(.system(size: 17, weight: .semibold))
                    .accessibilityHidden(true)
                Text("Join with a link")
                    .font(Fonts.subheadlineSemibold)
            }
            .foregroundStyle(Ink.text)
            .padding(.horizontal, Gap.l)
            .frame(minHeight: Gap.hit)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
    }
}
