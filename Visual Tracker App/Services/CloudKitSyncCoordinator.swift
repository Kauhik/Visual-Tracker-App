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

    private var debouncedTask: Task<Void, Never>?
    private var pollingTask: Task<Void, Never>?
    private var reconcileTask: Task<Void, Never>?

    private var notificationToken: NSObjectProtocol?
    private var appActiveToken: NSObjectProtocol?

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
    }

    func start() {
        guard isStarted == false else { return }
        isStarted = true
        logger.info("Starting CloudKit live sync")

        // Listen for CloudKit pushes forwarded by AppDelegate
        notificationToken = NotificationCenter.default.addObserver(
            forName: .cloudKitRemoteNotificationReceived,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            let userInfo = note.userInfo ?? [:]
            Task { await self.handleRemoteNotification(userInfo: userInfo) }
        }

        // Trigger sync when app becomes active
        appActiveToken = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.triggerSync(reason: .appBecameActive)
        }

        // Start polling fallback (kept lightweight via incremental sync)
        pollingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 45_000_000_000) // 45s
                if Task.isCancelled { break }
                self.triggerSync(reason: .poll)
            }
        }

        // Periodic reconcile for deletions that polling cannot detect
        reconcileTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 600_000_000_000) // 10 min
                if Task.isCancelled { break }
                self.triggerSync(reason: .reconcile)
            }
        }

        // Kick off initial subscription setup + an initial sync
        Task {
            await ensureSubscriptionsIfPossible()
            triggerSync(reason: .initial)
        }
    }

    func stop() {
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
    }

    func triggerSync(reason: TriggerReason) {
        // Debounce bursts of triggers (pushes, multiple writes, etc.)
        debouncedTask?.cancel()
        debouncedTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 800_000_000) // 0.8s debounce
            if Task.isCancelled { return }

            switch reason {
            case .reconcile:
                await self.store.reconcileDeletionsFromServer()
            default:
                break
            }

            await self.store.performIncrementalSync()
        }
    }

    func noteLocalWrite() {
        triggerSync(reason: .localWrite)
    }

    private func ensureSubscriptionsIfPossible() async {
        guard let cohortRecordID = store.currentCohortRecordID else { return }
        let cohortRef = CKRecord.Reference(recordID: cohortRecordID, action: .none)
        let predicate = NSPredicate(format: "cohortRef == %@", cohortRef)

        await createQuerySubscriptionIfPossible(
            subscriptionID: SubscriptionID.group,
            recordType: RecordType.cohortGroup,
            predicate: predicate
        )
        await createQuerySubscriptionIfPossible(
            subscriptionID: SubscriptionID.domain,
            recordType: RecordType.domain,
            predicate: predicate
        )
        await createQuerySubscriptionIfPossible(
            subscriptionID: SubscriptionID.student,
            recordType: RecordType.student,
            predicate: predicate
        )
        await createQuerySubscriptionIfPossible(
            subscriptionID: SubscriptionID.categoryLabel,
            recordType: RecordType.categoryLabel,
            predicate: predicate
        )
        await createQuerySubscriptionIfPossible(
            subscriptionID: SubscriptionID.objectiveProgress,
            recordType: RecordType.objectiveProgress,
            predicate: predicate
        )
        await createQuerySubscriptionIfPossible(
            subscriptionID: SubscriptionID.studentCustomProperty,
            recordType: RecordType.studentCustomProperty,
            predicate: predicate
        )
    }

    private func createQuerySubscriptionIfPossible(
        subscriptionID: String,
        recordType: String,
        predicate: NSPredicate
    ) async {
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
            logger.info("Saved CloudKit subscription. id=\(subscriptionID, privacy: .public) type=\(recordType, privacy: .public)")
        } catch {
            // If subscriptions fail (APNs/entitlement/config), polling continues as fallback.
            // We intentionally don't surface this as a user-facing error.
            logger.error("Failed to save CloudKit subscription. id=\(subscriptionID, privacy: .public) type=\(recordType, privacy: .public) error=\(self.service.describe(error), privacy: .public)")
        }
    }

    private func handleRemoteNotification(userInfo: [AnyHashable: Any]) async {
        logger.info("Handling remote notification")
        guard let notification = CKNotification(fromRemoteNotificationDictionary: userInfo) else {
            logger.info("Remote notification missing CKNotification payload; triggering sync")
            triggerSync(reason: .push)
            return
        }

        guard let query = notification as? CKQueryNotification else {
            logger.info("Remote notification not a CKQueryNotification; triggering sync")
            triggerSync(reason: .push)
            return
        }

        let subscriptionID = query.subscriptionID ?? ""
        let recordType = subscriptionMap[subscriptionID]

        if let recordType, let recordID = query.recordID {
            logger.info("Remote change: type=\(recordType, privacy: .public) id=\(recordID.recordName, privacy: .public) reason=\(String(describing: query.queryNotificationReason), privacy: .public)")
            switch query.queryNotificationReason {
            case .recordDeleted:
                store.applyRemoteDeletion(recordType: recordType, recordID: recordID)
            case .recordCreated, .recordUpdated:
                await store.fetchAndApplyRemoteRecord(recordType: recordType, recordID: recordID)
            @unknown default:
                break
            }
        }

        // Always follow up with an incremental sync to catch coalesced/missed changes.
        triggerSync(reason: .push)
    }
}
