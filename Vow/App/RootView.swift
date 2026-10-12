import SwiftUI
import Accessibility

struct RootView: View {
    @Environment(AppStore.self) private var store
    @State private var toastText: String?
    @State private var toastTask: Task<Void, Never>?

    private enum Screen: Equatable {
        case onboarding
        case loading
        case noAccount(String)
        case failed(String)
        case home
    }

    private var screen: Screen {
        if store.profile == nil {
            return .onboarding
        }
        switch store.phase {
        case .checking:
            return store.groupIDs.isEmpty ? .loading : .home
        case .noAccount(let message):
            return .noAccount(message)
        case .failed(let message):
            // With cached groups, stay on Home (it shows a retry banner).
            return store.groupIDs.isEmpty ? .failed(message) : .home
        case .ready:
            return .home
        }
    }

    var body: some View {
        ZStack {
            Palette.bg
                .ignoresSafeArea()
            content
        }
        .animation(Motion.screen, value: screen)
        .overlay(alignment: .top) {
            toastOverlay
        }
        .onChange(of: store.toast) { _, newValue in
            handleToast(newValue)
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
            OnboardingView()
                .transition(.opacity)
        case .loading:
            LoadingScreen()
                .transition(.opacity)
        case .noAccount(let message):
            PhaseScreen(
                systemImage: "icloud.slash",
                title: "iCloud required",
                message: message,
                actionTitle: "Try again",
                action: { Task { await store.bootstrap() } }
            )
            .transition(.opacity)
        case .failed(let message):
            PhaseScreen(
                systemImage: "exclamationmark.icloud",
                title: "Can't reach iCloud",
                message: message,
                actionTitle: "Try again",
                action: { Task { await store.bootstrap() } }
            )
            .transition(.opacity)
        case .home:
            HomeView()
                .transition(.opacity)
        }
    }

    /// Never takes touches, so a toast can't block Back, the gear or toolbar items.
    private var toastOverlay: some View {
        VStack(spacing: 0) {
            if let text = toastText {
                Toast(text: text)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.top, 6)
        .padding(.horizontal, 16)
        .animation(Motion.toast, value: toastText)
        .allowsHitTesting(false)
    }

    private func handleToast(_ value: String?) {
        guard let text = value else { return }
        store.toast = nil
        toastTask?.cancel()
        toastText = text
        AccessibilityNotification.Announcement(text).post()
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Motion.toastNanos)
            if Task.isCancelled { return }
            toastText = nil
        }
    }
}
