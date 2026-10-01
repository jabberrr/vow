import CloudKit
import UIKit

/// Installed by VowApp via `@UIApplicationDelegateAdaptor(AppDelegate.self)`.
/// Its only job is to route scenes to SceneDelegate so CloudKit share acceptances reach ShareInbox.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}

/// SwiftUI still owns the window; this delegate only forwards share invitations.
@MainActor
final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        if let metadata = connectionOptions.cloudKitShareMetadata {
            ShareInbox.deliver(metadata)
        }
    }

    func windowScene(_ windowScene: UIWindowScene,
                     userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        ShareInbox.deliver(cloudKitShareMetadata)
    }
}
