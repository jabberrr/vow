import SwiftUI

/// The pinned top bar: ≡ on the app background and the selected group's name, which names the scope of
/// every tab. ≡ carries a flame dot only while another of your vows is in its last 4 h (a real deadline
/// you can't see from here), and pulses once after a keep when another vow is still open. Only the
/// contents dim during a hold; the backing stays. The iCloud banner sits under the row on every tab.
struct TopBar: View {
    let title: String?
    let dot: MenuDot?
    let pulseToken: Int
    let dimmed: Bool
    let metrics: StageMetrics
    let onMenu: () -> Void

    @Environment(AppStore.self) private var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion: Bool
    @Environment(\.dynamicTypeSize) private var typeSize: DynamicTypeSize
    /// The glyph is scaled up by the next-vow pulse.
    @State private var pulsing: Bool = false
    @State private var pulseTask: Task<Void, Never>? = nil

    /// ≡'s 44 pt frame starts here, so the glyph's left edge sits on the 20 pt gutter.
    private static let menuInset: CGFloat = 8
    /// The title keeps clear of ≡ on both sides, so it stays centred on the screen.
    private static let titleInset: CGFloat = 60
    private static let pulseHoldNanos: UInt64 = 250_000_000

    init(title: String?,
         dot: MenuDot?,
         pulseToken: Int,
         dimmed: Bool,
         metrics: StageMetrics,
         onMenu: @escaping () -> Void) {
        self.title = title
        self.dot = dot
        self.pulseToken = pulseToken
        self.dimmed = dimmed
        self.metrics = metrics
        self.onMenu = onMenu
    }

    var body: some View {
        VStack(spacing: 0) {
            row
            banner
        }
        .roomDim(dimmed)
        .frame(maxWidth: .infinity)
        .background(Ink.bg.ignoresSafeArea(edges: .top))
        .onChange(of: pulseToken) {
            pulse()
        }
        .onDisappear {
            pulseTask?.cancel()
            pulseTask = nil
            pulsing = false
        }
    }

    // MARK: - Row

    private var row: some View {
        ZStack {
            titleText
                .padding(.horizontal, TopBar.titleInset)
            HStack(spacing: 0) {
                menuButton
                Spacer(minLength: 0)
            }
            .padding(.leading, TopBar.menuInset)
        }
        .frame(maxWidth: .infinity, minHeight: Gap.hit)
        .padding(.vertical, metrics.barPadding)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    @ViewBuilder
    private var titleText: some View {
        if let name: String = title {
            Text(name)
                .font(Fonts.headline)
                .foregroundStyle(Ink.text)
                .multilineTextAlignment(.center)
                .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                .truncationMode(.tail)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var menuButton: some View {
        Button(action: onMenu) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Ink.text)
                .scaleEffect(pulsing ? 1.15 : 1)
                .frame(width: Gap.hit, height: Gap.hit)
                .overlay(alignment: .topTrailing) {
                    flameDot
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("Menu")
        .accessibilityValue(dot?.spoken ?? "")
        .accessibilityHint("Your groups, balance and settings")
        .accessibilityShowsLargeContentViewer {
            Label("Menu", systemImage: "line.3.horizontal")
        }
    }

    /// An 8 pt flame dot on a disc of the background, so it separates from the lines.
    @ViewBuilder
    private var flameDot: some View {
        if dot?.atRisk == true {
            Circle()
                .fill(Ink.flame)
                .frame(width: 8, height: 8)
                .frame(width: 12, height: 12)
                .background(Circle().fill(Ink.bg))
                .padding(.top, 9)
                .padding(.trailing, 7)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Banner

    /// Only with cached groups (the shell exists); without them RootView shows the problem screen.
    @ViewBuilder
    private var banner: some View {
        if let message: String = failureMessage {
            InlineBanner(systemImage: "exclamationmark.icloud", text: message, actionTitle: "Try again") {
                Task { await store.bootstrap() }
            }
            .padding(.horizontal, Gap.l)
            .padding(.top, Gap.xs)
            .padding(.bottom, Gap.s)
        }
    }

    private var failureMessage: String? {
        if case .failed(let message) = store.phase {
            return message
        }
        return nil
    }

    // MARK: - Pulse

    /// Seal + 2.0 s, when another vow is still open: the glyph scales up once and leaves no mark.
    /// Nothing under Reduce Motion.
    private func pulse() {
        guard !reduceMotion else { return }
        pulseTask?.cancel()
        withAnimation(Anim.pulse) {
            pulsing = true
        }
        pulseTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: TopBar.pulseHoldNanos)
            if Task.isCancelled { return }
            withAnimation(Anim.pulse) {
                pulsing = false
            }
        }
    }
}
