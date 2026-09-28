import SwiftUI

struct RootView: View {
    @Environment(VowStore.self) private var store

    private var isOnboarding: Bool {
        store.state == nil
    }

    var body: some View {
        ZStack {
            Theme.bg
                .ignoresSafeArea()
            content
        }
        .animation(.easeInOut(duration: 0.45), value: isOnboarding)
    }

    @ViewBuilder
    private var content: some View {
        if isOnboarding {
            OnboardingView()
                .transition(.opacity)
        } else {
            MainView()
                .transition(.opacity)
        }
    }
}
