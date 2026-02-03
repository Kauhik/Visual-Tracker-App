import AppKit
import Foundation
import os.log

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "VisualTrackerApp",
        category: "AppDelegate"
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("Registering for remote notifications")
        NSApplication.shared.registerForRemoteNotifications()
    }

    func application(
        _ application: NSApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        logger.info("Registered for remote notifications. token=\(token, privacy: .private)")
    }

    func application(
        _ application: NSApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        logger.error("Remote notification registration failed: \(error.localizedDescription, privacy: .public)")
    }

    func application(
        _ application: NSApplication,
        didReceiveRemoteNotification userInfo: [String: Any]
    ) {
        logger.info("Received remote notification. userInfo=\(String(describing: userInfo), privacy: .private)")
        NotificationCenter.default.post(
            name: .cloudKitRemoteNotificationReceived,
            object: nil,
            userInfo: userInfo
        )
    }
}
