import AppKit
import CloudKit
import Foundation
import os.log

@MainActor
final class CloudKitSyncCoordinator {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "VisualTrackerApp",
        category: "CloudKitSync"
    )
    
    enum TriggerReason: String {
        case initial
        case localWrite
        case push
        case poll
        case appBecameActive
        case windowFocused
    }

    private unowned let store: CloudKitStore
    private let service: CloudKitService

    private var isStarted: Bool = false
    private var subscriptionsRegistered: Bool = false

    private var debouncedTask: Task<Void, Never>?
    private var pollingTask: Task<Void, Never>?

    private var notificationToken: NSObjectProtocol?
    private var appActiveToken: NSObjectProtocol?
    private var windowFocusToken: NSObjectProtocol?
    
    private var lastSyncTrigger: (reason: TriggerReason, date: Date)?
    private var syncCount: Int = 0

    // Subscription IDs (stable, deterministic)
    private enum SubscriptionID {
        static let group = "vt_sub_cohortGroup"
        static let domain = "vt_sub_domain"
        static let student = "vt_sub_student"
        static let categoryLabel = "vt_sub_categoryLabel"
        static let objectiveProgress = "vt_sub_objectiveProgress"
        static let studentCustomProperty = "vt_sub_studentCustomProperty"
    }

    // Record type names (must match CloudKit schema)
    private enum RecordType {
        static let cohortGroup = "CohortGroup"
        static let domain = "Domain"
        static let categoryLabel = "CategoryLabel"
        static let student = "Student"
        static let studentCustomProperty = "StudentCustomProperty"
        static let objectiveProgress = "ObjectiveProgress"
    }

    private let subscriptionMap: [String: String] = [
        SubscriptionID.group: RecordType.cohortGroup,
        SubscriptionID.domain: RecordType.domain,
        SubscriptionID.student: RecordType.student,
        SubscriptionID.categoryLabel: RecordType.categoryLabel,
        SubscriptionID.objectiveProgress: RecordType.objectiveProgress,
        SubscriptionID.studentCustomProperty: RecordType.studentCustomProperty
    ]

    init(store: CloudKitStore, service: CloudKitService) {
        self.store = store
        self.service = service
        logger.info("CloudKitSyncCoordinator initialized")
    }

    func start() {
        guard isStarted == false else {
            logger.info("CloudKit live sync already started, skipping")
            return
        }
        isStarted = true
        logger.info("Starting CloudKit live sync coordinator")

        // Listen for CloudKit pushes forwarded by AppDelegate
        notificationToken = NotificationCenter.default.addObserver(
            forName: .cloudKitRemoteNotificationReceived,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            let userInfo = note.userInfo ?? [:]
            self.logger.info("📬 Received push notification")
            Task { @MainActor in
                await self.handleRemoteNotification(userInfo: userInfo)
            }
        }
        logger.info("Registered for remote notification observer")

        // Trigger IMMEDIATE sync when app becomes active
        appActiveToken = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.logger.info("App became active, triggering immediate sync")
            Task { @MainActor in
                self.triggerImmediateSync(reason: .appBecameActive)
            }
        }
        logger.info("Registered for app activation observer")
        
        // Trigger sync when any window gains focus (debounced)
        windowFocusToken = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.logger.debug("Window became key (focused), triggering sync")
            Task { @MainActor in
                self.triggerSync(reason: .windowFocused)
            }
        }
        logger.info("Registered for window focus observer")

        // Poll every 10 seconds - full reconciliation catches creates, updates, AND deletions
        pollingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            self.logger.info("Starting polling task (10s interval)")
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
                if Task.isCancelled {
                    self.logger.info("Polling task cancelled")
                    break
                }
                self.logger.debug("Polling timer fired")
                self.triggerSync(reason: .poll)
            }
        }

        // Kick off initial subscription setup + initial sync
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.logger.info("Setting up subscriptions and triggering initial sync")
            await self.ensureSubscriptionsIfPossible()
            self.triggerImmediateSync(reason: .initial)
        }
    }

    func stop() {
        logger.info("Stopping CloudKit live sync coordinator")
        debouncedTask?.cancel()
        pollingTask?.cancel()

        if let token = notificationToken {
            NotificationCenter.default.removeObserver(token)
        }
        if let token = appActiveToken {
            NotificationCenter.default.removeObserver(token)
        }
        if let token = windowFocusToken {
            NotificationCenter.default.removeObserver(token)
        }

        notificationToken = nil
        appActiveToken = nil
        windowFocusToken = nil
        isStarted = false
        subscriptionsRegistered = false
        logger.info("CloudKit live sync coordinator stopped")
    }

    /// Triggers a sync with a short debounce to coalesce rapid events
    func triggerSync(reason: TriggerReason) {
        lastSyncTrigger = (reason, Date())
        
        // Debounce bursts of triggers
        debouncedTask?.cancel()
        debouncedTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s debounce
            if Task.isCancelled {
                self.logger.debug("Debounced sync task cancelled")
                return
            }
            await self.executeSync(reason: reason)
        }
    }
    
    /// Triggers a sync immediately with NO debounce
    func triggerImmediateSync(reason: TriggerReason) {
        logger.info("Sync triggered (immediate): reason=\(reason.rawValue, privacy: .public)")
        lastSyncTrigger = (reason, Date())
        
        debouncedTask?.cancel()
        debouncedTask = nil
        
        Task { @MainActor [weak self] in
            await self?.executeSync(reason: reason)
        }
    }
    
    /// Every sync is a full reconciliation - catches creates, updates, AND deletions
    private func executeSync(reason: TriggerReason) async {
        syncCount += 1
        let syncNumber = syncCount
        logger.info("Executing sync #\(syncNumber, privacy: .public) for reason: \(reason.rawValue, privacy: .public)")
        
        await store.reconcileWithServer()
        
        logger.info("Sync #\(syncNumber, privacy: .public) completed")
    }

    func noteLocalWrite() {
        logger.info("Local write detected, triggering sync")
        triggerSync(reason: .localWrite)
    }
    
    var diagnosticInfo: String {
        var info = "CloudKitSyncCoordinator Status:\n"
        info += "  isStarted: \(isStarted)\n"
        info += "  subscriptionsRegistered: \(subscriptionsRegistered)\n"
        info += "  syncCount: \(syncCount)\n"
        if let trigger = lastSyncTrigger {
            info += "  lastSyncTrigger: \(trigger.reason.rawValue) at \(trigger.date)\n"
        }
        info += "  pollingTask active: \(pollingTask != nil && !pollingTask!.isCancelled)\n"
        return info
    }

    private func ensureSubscriptionsIfPossible() async {
        guard let cohortRecordID = store.currentCohortRecordID else {
            logger.warning("Cannot create subscriptions: cohortRecordID is nil")
            return
        }
        
        logger.info("Setting up CloudKit query subscriptions for cohort: \(cohortRecordID.recordName, privacy: .public)")
        
        let cohortRef = CKRecord.Reference(recordID: cohortRecordID, action: .none)
        let predicate = NSPredicate(format: "cohortRef == %@", cohortRef)

        var successCount = 0
        var failureCount = 0

        if await createQuerySubscriptionIfPossible(
            subscriptionID: SubscriptionID.group,
            recordType: RecordType.cohortGroup,
            predicate: predicate
        ) { successCount += 1 } else { failureCount += 1 }
        
        if await createQuerySubscriptionIfPossible(
            subscriptionID: SubscriptionID.domain,
            recordType: RecordType.domain,
            predicate: predicate
        ) { successCount += 1 } else { failureCount += 1 }
        
        if await createQuerySubscriptionIfPossible(
            subscriptionID: SubscriptionID.student,
            recordType: RecordType.student,
            predicate: predicate
        ) { successCount += 1 } else { failureCount += 1 }
        
        if await createQuerySubscriptionIfPossible(
            subscriptionID: SubscriptionID.categoryLabel,
            recordType: RecordType.categoryLabel,
            predicate: predicate
        ) { successCount += 1 } else { failureCount += 1 }
        
        if await createQuerySubscriptionIfPossible(
            subscriptionID: SubscriptionID.objectiveProgress,
            recordType: RecordType.objectiveProgress,
            predicate: predicate
        ) { successCount += 1 } else { failureCount += 1 }
        
        if await createQuerySubscriptionIfPossible(
            subscriptionID: SubscriptionID.studentCustomProperty,
            recordType: RecordType.studentCustomProperty,
            predicate: predicate
        ) { successCount += 1 } else { failureCount += 1 }
        
        subscriptionsRegistered = failureCount == 0
        logger.info("Subscription setup complete: \(successCount, privacy: .public) succeeded, \(failureCount, privacy: .public) failed")
        
        if failureCount > 0 {
            logger.warning("Some subscriptions failed - push notifications may not work. Polling fallback is active (10s interval).")
        }
    }

    private func createQuerySubscriptionIfPossible(
        subscriptionID: String,
        recordType: String,
        predicate: NSPredicate
    ) async -> Bool {
        let subscription = CKQuerySubscription(
            recordType: recordType,
            predicate: predicate,
            subscriptionID: subscriptionID,
            options: [.firesOnRecordCreation, .firesOnRecordUpdate, .firesOnRecordDeletion]
        )

        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true // silent push
        subscription.notificationInfo = info

        do {
            _ = try await service.saveSubscription(subscription)
            logger.info("✓ Saved CloudKit subscription: id=\(subscriptionID, privacy: .public) type=\(recordType, privacy: .public)")
            return true
        } catch {
            let errorDesc = service.describe(error)
            logger.error("✗ Failed to save CloudKit subscription: id=\(subscriptionID, privacy: .public) type=\(recordType, privacy: .public) error=\(errorDesc, privacy: .public)")
            return false
        }
    }

    private func handleRemoteNotification(userInfo: [AnyHashable: Any]) async {
        logger.info("Handling remote notification")
        
        guard let notification = CKNotification(fromRemoteNotificationDictionary: userInfo) else {
            logger.info("Remote notification missing CKNotification payload; triggering sync")
            triggerImmediateSync(reason: .push)
            return
        }

        guard let query = notification as? CKQueryNotification else {
            logger.info("Remote notification is not a CKQueryNotification; triggering sync")
            triggerImmediateSync(reason: .push)
            return
        }

        let subscriptionID = query.subscriptionID ?? "<unknown>"
        let recordType = subscriptionMap[subscriptionID]

        if let recordType, let recordID = query.recordID {
            let reasonStr: String
            switch query.queryNotificationReason {
            case .recordDeleted: reasonStr = "deleted"
            case .recordCreated: reasonStr = "created"
            case .recordUpdated: reasonStr = "updated"
            @unknown default: reasonStr = "unknown"
            }
            
            logger.info("📬 Remote change: type=\(recordType, privacy: .public) id=\(recordID.recordName.prefix(8), privacy: .public)... reason=\(reasonStr, privacy: .public)")
            
            // Apply the specific change immediately for instant feedback
            switch query.queryNotificationReason {
            case .recordDeleted:
                store.applyRemoteDeletion(recordType: recordType, recordID: recordID)
            case .recordCreated, .recordUpdated:
                await store.fetchAndApplyRemoteRecord(recordType: recordType, recordID: recordID)
            @unknown default:
                break
            }
        }

        // Follow up with full reconciliation to catch anything missed
        triggerImmediateSync(reason: .push)
    }
}
