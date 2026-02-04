import AppKit
import Foundation
import os.log

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "VisualTrackerApp",
        category: "AppDelegate"
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("Application did finish launching")
        logger.info("Registering for remote notifications...")
        NSApplication.shared.registerForRemoteNotifications()
        
        // Log current notification settings
        let types = NSApplication.shared.enabledRemoteNotificationTypes
        logger.info("Enabled remote notification types: \(String(describing: types), privacy: .public)")
    }

    func application(
        _ application: NSApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        logger.info("✓ Successfully registered for remote notifications")
        logger.info("APNs device token (length=\(deviceToken.count, privacy: .public)): \(token.prefix(16), privacy: .public)...\(token.suffix(16), privacy: .public)")
    }

    func application(
        _ application: NSApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        logger.error("✗ Remote notification registration FAILED: \(error.localizedDescription, privacy: .public)")
        
        // Provide more detailed error information
        let nsError = error as NSError
        logger.error("Error domain: \(nsError.domain, privacy: .public), code: \(nsError.code, privacy: .public)")
        if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            logger.error("Underlying error: \(underlyingError.localizedDescription, privacy: .public)")
        }
        
        // Log common causes
        logger.warning("Common causes for this error:")
        logger.warning("1. 'Push Notifications' capability not enabled in Xcode target")
        logger.warning("2. App not signed with valid provisioning profile")
        logger.warning("3. Running in iOS Simulator (use physical device)")
        logger.warning("4. Network connectivity issues")
    }

    func application(
        _ application: NSApplication,
        didReceiveRemoteNotification userInfo: [String: Any]
    ) {
        logger.info("📬 Received remote notification")
        logger.info("Notification payload keys: \(Array(userInfo.keys).joined(separator: ", "), privacy: .public)")
        
        // Log CloudKit-specific info if present
        if let ck = userInfo["ck"] as? [String: Any] {
            logger.info("CloudKit notification detected")
            if let qry = ck["qry"] as? [String: Any] {
                if let rid = qry["rid"] as? String {
                    logger.info("  Record ID: \(rid, privacy: .public)")
                }
                if let sid = qry["sid"] as? String {
                    logger.info("  Subscription ID: \(sid, privacy: .public)")
                }
            }
        }
        
        NotificationCenter.default.post(
            name: .cloudKitRemoteNotificationReceived,
            object: nil,
            userInfo: userInfo
        )
        logger.info("Posted .cloudKitRemoteNotificationReceived to NotificationCenter")
    }
    
    func applicationDidBecomeActive(_ notification: Notification) {
        logger.info("Application did become active")
    }
    
    func applicationWillResignActive(_ notification: Notification) {
        logger.info("Application will resign active")
    }
}
