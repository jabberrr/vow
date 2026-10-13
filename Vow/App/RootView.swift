import SwiftUI
import Accessibility

/// Picks the screen for the app's state. Owns the room-dim flag (set by the stage during a hold)
/// and the toast, which waits while the room is dimmed and shows when the lights come back.
struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var roomDimmed: Bool = false
    @State private var toastText: String? = nil
    /// A toast that arrived during a hold.
    @State private var heldToast: String? = nil
    @State private var toastTask: Task<Void, Never>? = nil

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
            // With cached groups, stay on the stage (it shows a retry banner).
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
        .onChange(of: roomDimmed) { _, dimmed in
            roomDimChanged(dimmed)
        }
        .onAppear {
            handleToast(store.toast)
        }
        .onDisappear {
            toastTask?.cancel()
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
            MainView(roomDimmed: $roomDimmed)
                .transition(.opacity)
        }
    }

    // MARK: Toast

    /// Under the pinned bar. A tap on the toast dismisses it (and never reaches the title menu
    /// below); the empty overlay takes no touches. Hidden while the room is dimmed.
    private var toastOverlay: some View {
        VStack(spacing: 0) {
            if let text = toastText {
                ToastBanner(text: text)
                    .contentShape(Capsule())
                    .onTapGesture {
                        dismissToast()
                    }
                    .transition(toastTransition)
            }
        }
        .padding(.top, 52)
        .padding(.horizontal, Gap.barInset)
        .opacity(roomDimmed ? 0 : 1)
        .animation(Anim.toast, value: toastText)
    }

    private var toastTransition: AnyTransition {
        if reduceMotion {
            return AnyTransition.opacity
        }
        return AnyTransition.move(edge: .top).combined(with: .opacity)
    }

    private func handleToast(_ value: String?) {
        guard let text: String = value else { return }
        store.toast = nil
        if roomDimmed {
            heldToast = text
            return
        }
        showToast(text)
    }

    private func roomDimChanged(_ dimmed: Bool) {
        guard !dimmed, let text: String = heldToast else { return }
        heldToast = nil
        showToast(text)
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

    private func dismissToast() {
        toastTask?.cancel()
        toastText = nil
    }

    private func retry() {
        Task { await store.bootstrap() }
    }
}
