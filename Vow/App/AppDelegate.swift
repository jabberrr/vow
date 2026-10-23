import CloudKit
import UIKit

/// Installed by VowApp via `@UIApplicationDelegateAdaptor(AppDelegate.self)`. It routes scenes to SceneDelegate, so
/// CloudKit share acceptances reach ShareInbox, and CloudKit's silent pushes to ChangeInbox.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    /// CloudKit pushes to this device only once it is registered. Silent pushes need no permission, so nothing
    /// is asked.
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        if !AppStore.isRunningUnitTests {
            application.registerForRemoteNotifications()
        }
        return true
    }

    /// Something changed in a group (`CloudService.ensureSubscriptions`). A push that isn't CloudKit's isn't ours,
    /// and is answered at once.
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        guard CKNotification(fromRemoteNotificationDictionary: userInfo) != nil else {
            completionHandler(.noData)
            return
        }
        ChangeInbox.deliver { (changed: Bool) in
            completionHandler(changed ? .newData : .noData)
        }
    }

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
