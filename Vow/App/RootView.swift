import SwiftUI

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
            Theme.bg
                .ignoresSafeArea()
            content
        }
        .animation(.easeInOut(duration: 0.45), value: screen)
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
                title: "Couldn't reach iCloud",
                message: message,
                actionTitle: "Retry",
                action: { Task { await store.bootstrap() } }
            )
            .transition(.opacity)
        case .home:
            HomeView()
                .transition(.opacity)
        }
    }

    private var toastOverlay: some View {
        VStack(spacing: 0) {
            if let text = toastText {
                Toast(text: text)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.top, 6)
        .padding(.horizontal, 16)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: toastText)
    }

    private func handleToast(_ value: String?) {
        guard let text = value else { return }
        store.toast = nil
        toastTask?.cancel()
        toastText = text
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if Task.isCancelled { return }
            toastText = nil
        }
    }
}
