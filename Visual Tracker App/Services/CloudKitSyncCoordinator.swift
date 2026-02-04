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
        case reconcile
    }

    private unowned let store: CloudKitStore
    private let service: CloudKitService

    private var isStarted: Bool = false
    private var subscriptionsRegistered: Bool = false

    private var debouncedTask: Task<Void, Never>?
    private var pollingTask: Task<Void, Never>?
    private var reconcileTask: Task<Void, Never>?

    private var notificationToken: NSObjectProtocol?
    private var appActiveToken: NSObjectProtocol?
    
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
            self.logger.info("Received cloudKitRemoteNotificationReceived notification")
            Task { @MainActor in
                await self.handleRemoteNotification(userInfo: userInfo)
            }
        }
        logger.info("Registered for remote notification observer")

        // Trigger sync when app becomes active
        appActiveToken = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.logger.info("App became active, triggering sync")
            Task { @MainActor in
                self.triggerSync(reason: .appBecameActive)
            }
        }
        logger.info("Registered for app activation observer")

        // Start polling fallback (kept lightweight via incremental sync)
        pollingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            self.logger.info("Starting polling task (45s interval)")
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000) // 45s
                if Task.isCancelled {
                    self.logger.info("Polling task cancelled")
                    break
                }
                self.logger.debug("Polling timer fired")
                self.triggerSync(reason: .poll)
            }
        }

        // Periodic reconcile for deletions that polling cannot detect
        reconcileTask = Task { @MainActor [weak self] in
            guard let self else { return }
            self.logger.info("Starting reconcile task (2 min interval)")
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 120_000_000_000) // 2 min (reduced for faster deletion detection)
                if Task.isCancelled {
                    self.logger.info("Reconcile task cancelled")
                    break
                }
                self.logger.debug("Reconcile timer fired")
                self.triggerSync(reason: .reconcile)
            }
        }

        // Kick off initial subscription setup + an initial sync
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.logger.info("Setting up subscriptions and triggering initial sync")
            await self.ensureSubscriptionsIfPossible()
            self.triggerSync(reason: .initial)
        }
    }

    func stop() {
        logger.info("Stopping CloudKit live sync coordinator")
        debouncedTask?.cancel()
        pollingTask?.cancel()
        reconcileTask?.cancel()

        if let token = notificationToken {
            NotificationCenter.default.removeObserver(token)
        }
        if let token = appActiveToken {
            NotificationCenter.default.removeObserver(token)
        }

        notificationToken = nil
        appActiveToken = nil
        isStarted = false
        subscriptionsRegistered = false
        logger.info("CloudKit live sync coordinator stopped")
    }

    func triggerSync(reason: TriggerReason) {
        logger.info("Sync triggered: reason=\(reason.rawValue, privacy: .public)")
        lastSyncTrigger = (reason, Date())
        
        // Debounce bursts of triggers (pushes, multiple writes, etc.)
        debouncedTask?.cancel()
        debouncedTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 800_000_000) // 0.8s debounce
            if Task.isCancelled {
                self.logger.debug("Debounced sync task cancelled")
                return
            }

            self.syncCount += 1
            let syncNumber = self.syncCount
            self.logger.info("Executing sync #\(syncNumber, privacy: .public) for reason: \(reason.rawValue, privacy: .public)")

            switch reason {
            case .reconcile:
                self.logger.info("Performing full reconciliation (additions + deletions)")
                await self.store.reconcileWithServer()
                // Skip incremental sync after full reconcile since we just fetched everything
                self.logger.info("Sync #\(syncNumber, privacy: .public) completed (full reconcile)")
                return
            default:
                break
            }

            await self.store.performIncrementalSync()
            self.logger.info("Sync #\(syncNumber, privacy: .public) completed")
        }
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
        info += "  reconcileTask active: \(reconcileTask != nil && !reconcileTask!.isCancelled)\n"
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
            logger.warning("Some subscriptions failed - push notifications may not work. Polling fallback is active (45s interval).")
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
            // If subscriptions fail (APNs/entitlement/config), polling continues as fallback.
            let errorDesc = service.describe(error)
            logger.error("✗ Failed to save CloudKit subscription: id=\(subscriptionID, privacy: .public) type=\(recordType, privacy: .public) error=\(errorDesc, privacy: .public)")
            return false
        }
    }

    private func handleRemoteNotification(userInfo: [AnyHashable: Any]) async {
        logger.info("Handling remote notification with userInfo keys: \(Array(userInfo.keys).map { String(describing: $0) }.joined(separator: ", "), privacy: .public)")
        
        guard let notification = CKNotification(fromRemoteNotificationDictionary: userInfo) else {
            logger.info("Remote notification missing CKNotification payload; triggering sync anyway")
            triggerSync(reason: .push)
            return
        }

        guard let query = notification as? CKQueryNotification else {
            logger.info("Remote notification is not a CKQueryNotification (type: \(String(describing: type(of: notification)), privacy: .public)); triggering sync")
            triggerSync(reason: .push)
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
            
            logger.info("Remote change detected: type=\(recordType, privacy: .public) id=\(recordID.recordName, privacy: .public) reason=\(reasonStr, privacy: .public)")
            
            switch query.queryNotificationReason {
            case .recordDeleted:
                logger.info("Applying remote deletion for \(recordType, privacy: .public)")
                store.applyRemoteDeletion(recordType: recordType, recordID: recordID)
            case .recordCreated, .recordUpdated:
                logger.info("Fetching and applying remote record for \(recordType, privacy: .public)")
                await store.fetchAndApplyRemoteRecord(recordType: recordType, recordID: recordID)
            @unknown default:
                logger.warning("Unknown query notification reason")
                break
            }
        } else {
            logger.info("Could not extract record info from notification (subscriptionID: \(subscriptionID, privacy: .public))")
        }

        // Always follow up with an incremental sync to catch coalesced/missed changes.
        logger.info("Following up push with incremental sync")
        triggerSync(reason: .push)
    }
}
