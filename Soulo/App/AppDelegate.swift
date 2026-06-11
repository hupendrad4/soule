import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
        MemoryManager.shared.clearCaches()
    }

    func applicationSignificantTimeChange(_ application: UIApplication) {
        Task { try? await StorageService.shared.reindexTimestamps() }
    }

    func application(
        _ app: UIApplication,
        open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        StripeService.shared.handleCallback(url: url)
        return true
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
