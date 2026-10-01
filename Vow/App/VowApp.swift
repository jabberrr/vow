import SwiftUI

@main
struct VowApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = AppStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .tint(Theme.cyan)
                .preferredColorScheme(.dark)
                .task {
                    if !isRunningTests {
                        await store.bootstrap()
                    }
                }
                .onChange(of: scenePhase) { _, newPhase in
                    handleScenePhase(newPhase)
                }
                .onOpenURL { url in
                    Task { _ = await store.join(url: url) }
                }
        }
    }

    /// Unit tests run hosted in Vow.app without entitlements: never touch CloudKit then.
    private var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    @MainActor
    private func handleScenePhase(_ newPhase: ScenePhase) {
        guard newPhase == .active, !isRunningTests else { return }
        switch store.phase {
        case .ready:
            Task { await store.refreshAll() }
        case .noAccount, .failed:
            // Coming back from Settings (e.g. after signing in to iCloud): try again.
            Task { await store.bootstrap() }
        case .checking:
            break
        }
    }
}
