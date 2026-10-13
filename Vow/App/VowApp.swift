import SwiftUI

@main
struct VowApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = AppStore()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Before launch finishes, so a reminder tap that launched the app reaches the delegate.
        ReminderCenter.shared.install()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(ReminderCenter.shared)
                .tint(Ink.text)
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
        // Notifications may have been turned off in Settings meanwhile.
        Task { await ReminderCenter.shared.refreshAuthorization() }
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
