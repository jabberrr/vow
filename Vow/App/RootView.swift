import SwiftUI
import Accessibility

/// Picks the screen for the app's state. Owns the room-dim flag (set by the stage during a hold) and
/// the toast. A toast waits while the room is dimmed and shows when the lights come back; one that a
/// sheet, a dialog or the sidebar keeps waiting is dropped after a short while, since it would only be
/// seen behind or after them. It sits below the shell's measured top bar and takes no touches.
struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var roomDimmed: Bool = false
    /// From the shell: a sheet, a dialog or the sidebar is up.
    @State private var toastBlocked: Bool = false
    /// From the shell: the top bar's height, its banner included.
    @State private var topBarHeight: CGFloat = RootView.barHeight
    @State private var toastText: String? = nil
    /// A toast waiting for the lights or for the shell to be free.
    @State private var heldToast: String? = nil
    /// Uptime when `heldToast` was raised: a blocked toast waits at most `Anim.toastWaitNanos` from then.
    @State private var heldSince: TimeInterval = 0
    @State private var toastTask: Task<Void, Never>? = nil
    @State private var waitTask: Task<Void, Never>? = nil

    /// The top bar's regular height (a 44 pt row with 4 pt above and below), until the shell measures it.
    private static let barHeight: CGFloat = 52
    /// A blocked toast this close to the end of its wait is dropped now rather than re-checked.
    private static let waitSlack: TimeInterval = 0.01

    private enum Screen: Equatable {
        case onboarding
        case loading
        case noAccount(String)
        case failed(String)
        case main
    }

    private var screen: Screen {
        if store.profile == nil {
            return .onboarding
        }
        switch store.phase {
        case .checking:
            return store.groupIDs.isEmpty ? .loading : .main
        case .noAccount(let message):
            return .noAccount(message)
        case .failed(let message):
            // With cached groups, stay in the app (its top bar shows a retry banner).
            return store.groupIDs.isEmpty ? .failed(message) : .main
        case .ready:
            return .main
        }
    }

    var body: some View {
        ZStack {
            Ink.bg
                .ignoresSafeArea()
            content
        }
        .animation(Anim.screen, value: screen)
        .overlay(alignment: .top) {
            toastOverlay
        }
        .onChange(of: store.toast) { _, newValue in
            handleToast(newValue)
        }
        .onChange(of: roomDimmed) {
            releaseToast()
        }
        .onChange(of: toastBlocked) {
            releaseToast()
        }
        .onAppear {
            handleToast(store.toast)
        }
        .onDisappear {
            toastTask?.cancel()
            waitTask?.cancel()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch screen {
        case .onboarding:
            OnboardingScreen()
                .transition(.opacity)
        case .loading:
            LaunchScreen()
                .transition(.opacity)
        case .noAccount(let message):
            ProblemScreen(systemImage: "icloud.slash",
                          title: "iCloud unavailable",
                          message: message,
                          onRetry: retry)
                .transition(.opacity)
        case .failed(let message):
            ProblemScreen(systemImage: "exclamationmark.icloud",
                          title: "Can't reach iCloud",
                          message: message,
                          onRetry: retry)
                .transition(.opacity)
        case .main:
            MainView(roomDimmed: $roomDimmed, toastBlocked: $toastBlocked, topBarHeight: $topBarHeight)
                .transition(.opacity)
        }
    }

    // MARK: Toast

    /// Below the top bar and its banner, never over the bars; it takes no touches, so nothing under
    /// it is ever blocked. Hidden while the room is dimmed.
    private var toastOverlay: some View {
        VStack(spacing: 0) {
            if let text = toastText {
                ToastBanner(text: text)
                    .transition(toastTransition)
            }
        }
        .padding(.top, topBarHeight + Gap.s)
        .padding(.horizontal, Gap.barInset)
        .opacity(roomDimmed ? 0 : 1)
        .animation(Anim.toast, value: toastText)
        .allowsHitTesting(false)
    }

    private var toastTransition: AnyTransition {
        if reduceMotion {
            return AnyTransition.opacity
        }
        return AnyTransition.move(edge: .top).combined(with: .opacity)
    }

    /// The latest toast wins: it replaces one that is still waiting.
    private func handleToast(_ value: String?) {
        guard let text: String = value else { return }
        store.toast = nil
        heldToast = text
        heldSince = ProcessInfo.processInfo.systemUptime
        releaseToast()
    }

    /// Shows the waiting toast unless something holds it back. Dimmed: it waits for the lights (a hold
    /// is short). Blocked: it waits until `Anim.toastWaitNanos` after it was raised, then it is dropped
    /// ("Group created." under the Invite sheet; a create or join error already shown in its sheet).
    private func releaseToast() {
        waitTask?.cancel()
        waitTask = nil
        guard let text: String = heldToast, !roomDimmed else { return }
        guard toastBlocked else {
            heldToast = nil
            showToast(text)
            return
        }
        let limit: TimeInterval = Double(Anim.toastWaitNanos) / 1_000_000_000
        let left: TimeInterval = heldSince + limit - ProcessInfo.processInfo.systemUptime
        guard left > RootView.waitSlack else {
            heldToast = nil
            return
        }
        waitTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(left * 1_000_000_000))
            if Task.isCancelled { return }
            releaseToast()
        }
    }

    private func showToast(_ text: String) {
        toastTask?.cancel()
        toastText = text
        AccessibilityNotification.Announcement(text).post()
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Anim.toastNanos)
            if Task.isCancelled { return }
            toastText = nil
        }
    }

    private func retry() {
        Task { await store.bootstrap() }
    }
}
