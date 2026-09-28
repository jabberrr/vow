import SwiftUI

@main
struct VowApp: App {
    @State private var store = VowStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .tint(Theme.cyan)
                .preferredColorScheme(.dark)
        }
    }
}
