import AppKit
import CloudKit
import Combine
import Foundation
import os.log

struct ResetProgress: Equatable {
    let message: String
    let step: Int
    let totalSteps: Int
}

extension CloudKitStoreSnapshot.Group: Equatable {
    static func == (lhs: CloudKitStoreSnapshot.Group, rhs: CloudKitStoreSnapshot.Group) -> Bool {
        lhs.id == rhs.id
            && lhs.name == rhs.name
            && lhs.colorHex == rhs.colorHex
            && lhs.recordName == rhs.recordName
    }
}

extension CloudKitStoreSnapshot.Domain: Equatable {
    static func == (lhs: CloudKitStoreSnapshot.Domain, rhs: CloudKitStoreSnapshot.Domain) -> Bool {
        lhs.id == rhs.id
            && lhs.name == rhs.name
            && lhs.colorHex == rhs.colorHex
            && lhs.overallModeRaw == rhs.overallModeRaw
            && lhs.recordName == rhs.recordName
    }
}

extension CloudKitStoreSnapshot.LearningObjective: Equatable {
    static func == (lhs: CloudKitStoreSnapshot.LearningObjective, rhs: CloudKitStoreSnapshot.LearningObjective) -> Bool {
        lhs.id == rhs.id
            && lhs.code == rhs.code
            && lhs.title == rhs.title
            && lhs.objectiveDescription == rhs.objectiveDescription
            && lhs.isQuantitative == rhs.isQuantitative
            && lhs.parentCode == rhs.parentCode
            && lhs.parentId == rhs.parentId
            && lhs.sortOrder == rhs.sortOrder
            && lhs.isArchived == rhs.isArchived
            && lhs.recordName == rhs.recordName
    }
}

extension CloudKitStoreSnapshot.Student: Equatable {
    static func == (lhs: CloudKitStoreSnapshot.Student, rhs: CloudKitStoreSnapshot.Student) -> Bool {
        lhs.id == rhs.id
            && lhs.name == rhs.name
            && lhs.createdAt == rhs.createdAt
            && lhs.sessionRawValue == rhs.sessionRawValue
            && lhs.groupID == rhs.groupID
            && lhs.domainID == rhs.domainID
            && lhs.recordName == rhs.recordName
    }
}

extension CloudKitStoreSnapshot.Membership: Equatable {
    static func == (lhs: CloudKitStoreSnapshot.Membership, rhs: CloudKitStoreSnapshot.Membership) -> Bool {
        lhs.id == rhs.id
            && lhs.studentID == rhs.studentID
            && lhs.groupID == rhs.groupID
            && lhs.createdAt == rhs.createdAt
            && lhs.updatedAt == rhs.updatedAt
            && lhs.recordName == rhs.recordName
    }
}

extension CloudKitStoreSnapshot.ObjectiveProgress: Equatable {
    static func == (lhs: CloudKitStoreSnapshot.ObjectiveProgress, rhs: CloudKitStoreSnapshot.ObjectiveProgress) -> Bool {
        lhs.id == rhs.id
            && lhs.studentID == rhs.studentID
            && lhs.objectiveId == rhs.objectiveId
            && lhs.objectiveCode == rhs.objectiveCode
            && lhs.value == rhs.value
            && lhs.notes == rhs.notes
            && lhs.lastUpdated == rhs.lastUpdated
            && lhs.statusRawValue == rhs.statusRawValue
            && lhs.recordName == rhs.recordName
    }
}

extension CloudKitStoreSnapshot.ExpertiseCheckObjectiveScore: Equatable {
    static func == (
        lhs: CloudKitStoreSnapshot.ExpertiseCheckObjectiveScore,
        rhs: CloudKitStoreSnapshot.ExpertiseCheckObjectiveScore
    ) -> Bool {
        lhs.id == rhs.id
            && lhs.expertiseCheckID == rhs.expertiseCheckID
            && lhs.objectiveId == rhs.objectiveId
            && lhs.objectiveCode == rhs.objectiveCode
            && lhs.value == rhs.value
            && lhs.statusRawValue == rhs.statusRawValue
            && lhs.createdAt == rhs.createdAt
            && lhs.updatedAt == rhs.updatedAt
            && lhs.lastEditedByDisplayName == rhs.lastEditedByDisplayName
            && lhs.recordName == rhs.recordName
    }
}

private struct UndoCustomPropertySnapshot: Equatable {
    let id: UUID
    let studentID: UUID
    let key: String
    let value: String
    let sortOrder: Int
    let recordName: String
}

private struct StudentUndoBundle: Equatable {
    let student: CloudKitStoreSnapshot.Student
    let memberships: [CloudKitStoreSnapshot.Membership]
    let progress: [CloudKitStoreSnapshot.ObjectiveProgress]
    let customProperties: [UndoCustomPropertySnapshot]
}

private struct GroupUndoBundle: Equatable {
    let group: CloudKitStoreSnapshot.Group
    let memberships: [CloudKitStoreSnapshot.Membership]
    let affectedStudentIDs: [UUID]
}

private struct DomainUndoBundle: Equatable {
    let domain: CloudKitStoreSnapshot.Domain
    let affectedStudentIDs: [UUID]
}

private struct UndoOperation {
    let id: UUID
    let timestamp: Date
    let label: String
    let undo: @MainActor (CloudKitStore) async -> Bool
    let redo: @MainActor (CloudKitStore) async -> Bool
}

@MainActor
final class CloudKitStore: ObservableObject {
    @Published var isLoading: Bool = false
    @Published var lastErrorMessage: String?
    @Published var requiresICloudLogin: Bool = false
    @Published var resetProgress: ResetProgress?

    @Published var students: [Student] = []
    @Published var groups: [CohortGroup] = []
    @Published var domains: [Domain] = []
    @Published var categoryLabels: [CategoryLabel] = []
    @Published var learningObjectives: [LearningObjective] = LearningObjectiveCatalog.defaultObjectives()
    @Published var memberships: [StudentGroupMembership] = []
    @Published var selectedStudentId: UUID?
    @Published var selectedScope: StudentFilterScope = .overall
    @Published private(set) var hasCachedSnapshotData: Bool = false
    @Published private(set) var isShowingStaleSnapshot: Bool = false
    @Published private(set) var isOfflineUsingSnapshot: Bool = false
    @Published private(set) var cachedSnapshotDate: Date?
    @Published private(set) var canUndo: Bool = false
    @Published private(set) var canRedo: Bool = false
    @Published private(set) var nextUndoActionLabel: String?
    @Published private(set) var nextRedoActionLabel: String?
    @Published private(set) var isUndoRedoInProgress: Bool = false
    @Published private(set) var sheets: [CohortSheet] = []
    @Published private(set) var activeSheet: CohortSheet?
    @Published private(set) var isSheetMutationInProgress: Bool = false

    private let service: CloudKitService
    private let isPreviewData: Bool
    private let defaultCohortId: String = "main"
    private let activeCohortDefaultsKey: String = "VisualTrackerApp.activeCohortId"
    private var cohortRecordID: CKRecord.ID?
    private var hasLoaded: Bool = false

    private var progressLoadedStudentIDs: Set<UUID> = []
    private var customPropertiesLoadedStudentIDs: Set<UUID> = []

    private var groupRecordNameByID: [UUID: String] = [:]
    private var domainRecordNameByID: [UUID: String] = [:]
    private var learningObjectiveRecordNameByID: [UUID: String] = [:]
    private var studentRecordNameByID: [UUID: String] = [:]
    private var membershipRecordNameByID: [UUID: String] = [:]
    private var progressRecordNameByID: [UUID: String] = [:]
    private var customPropertyRecordNameByID: [UUID: String] = [:]
    private var expertiseCheckScoreRecordNameByID: [UUID: String] = [:]
    private var allLearningObjectives: [LearningObjective] = []
    private var expertiseCheckObjectiveScores: [ExpertiseCheckObjectiveScore] = []
    private var pendingGroupCreateIDs: Set<UUID> = []
    private var pendingDomainCreateIDs: Set<UUID> = []
    private var pendingExpertiseCheckModeUpdateIDs: Set<UUID> = []
    private var pendingLearningObjectiveCreateIDs: Set<UUID> = []
    private var pendingCategoryLabelCreateKeys: Set<String> = []
    private var categoryLabelRecordNameByCode: [String: String] = [:]
    private var unconfirmedGroupRecordNames: Set<String> = []
    private var unconfirmedDomainRecordNames: Set<String> = []
    private var unconfirmedLearningObjectiveRecordNames: Set<String> = []
    private var unconfirmedCategoryLabelRecordNames: Set<String> = []
    private var recentLocalWriteRecordKeys: [String: Date] = [:]
    private let reconcileDeletionGraceInterval: TimeInterval = 120
    private var objectiveRefMigrationRecordNames: Set<String> = []
    private var isSeedingLearningObjectives: Bool = false
    private var isMigratingLegacyMemberships: Bool = false
    private var rootCategoryObjectivesCache: [LearningObjective] = []
    private var objectiveChildrenByParentID: [UUID: [LearningObjective]] = [:]
    private var objectiveByCodeCache: [String: LearningObjective] = [:]
    private var groupsByStudentIDCache: [UUID: [CohortGroup]] = [:]
    private var progressValuesByStudentObjectiveID: [UUID: [UUID: Int]] = [:]
    private var progressValuesByStudentObjectiveCode: [UUID: [String: Int]] = [:]
    private var objectiveAggregateByStudentID: [UUID: [UUID: Int]] = [:]
    private var studentOverallProgressByID: [UUID: Int] = [:]
    private var cohortOverallProgressCache: Int = 0
    private var expertiseCheckScoreByDomainObjectiveID: [UUID: [UUID: ExpertiseCheckObjectiveScore]] = [:]
    private var expertiseCheckScoreByDomainObjectiveCode: [UUID: [String: ExpertiseCheckObjectiveScore]] = [:]
    private let maxUndoHistorySize: Int = 50
    private var undoStack: [UndoOperation] = []
    private var redoStack: [UndoOperation] = []
    private var undoRedoExecutionTask: Task<Void, Never>?
    private var undoCaptureSuppressionDepth: Int = 0
    private var isApplyingRemoteChanges: Bool = false

    private var syncCoordinator: CloudKitSyncCoordinator?
    private var progressRebuildTask: Task<Void, Never>?
    private var snapshotPersistTask: Task<Void, Never>?
    private let progressRebuildDebounceNanoseconds: UInt64 = 300_000_000
    private let snapshotPersistDebounceNanoseconds: UInt64 = 400_000_000
    private var activeCohortId: String {
        activeSheet?.cohortId
            ?? UserDefaults.standard.string(forKey: activeCohortDefaultsKey)
            ?? defaultCohortId
    }

    private func lastSyncDateDefaultsKey(for cohortId: String) -> String {
        "VisualTrackerApp.lastSyncDate.\(cohortId)"
    }

    private var lastSyncDateDefaultsKey: String { lastSyncDateDefaultsKey(for: activeCohortId) }

    private var lastSyncDate: Date {
        get {
            let value = UserDefaults.standard.double(forKey: lastSyncDateDefaultsKey)
            return value > 0 ? Date(timeIntervalSince1970: value) : .distantPast
        }
        set {
            UserDefaults.standard.set(newValue.timeIntervalSince1970, forKey: lastSyncDateDefaultsKey)
        }
    }

    // Exposed to the sync coordinator (read-only)
    var currentCohortRecordID: CKRecord.ID? { cohortRecordID }
    var shouldShowBlockingLoadingUI: Bool { isLoading && hasCachedSnapshotData == false }
    var cacheStatusMessage: String? {
        guard hasCachedSnapshotData else { return nil }
        let date = cachedSnapshotDate
        let prefix: String
        if isOfflineUsingSnapshot {
            prefix = "Offline"
        } else if isShowingStaleSnapshot {
            prefix = "Showing cached data"
        } else {
            return nil
        }

        guard let date else { return prefix }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        let relative = formatter.localizedString(for: date, relativeTo: Date())
        if isOfflineUsingSnapshot {
            return "\(prefix) • last updated \(relative)"
        }
        return "\(prefix) • refreshing (\(relative))"
    }

    func undoLastAction() {
        enqueueUndoRedoExecution { [weak self] in
            guard let self else { return }
            await self.performUndoNow()
        }
    }

    func redoLastAction() {
        enqueueUndoRedoExecution { [weak self] in
            guard let self else { return }
            await self.performRedoNow()
        }
    }

    private func enqueueUndoRedoExecution(_ block: @escaping () async -> Void) {
        let previous = undoRedoExecutionTask
        undoRedoExecutionTask = Task { [weak self] in
            _ = await previous?.result
            guard self != nil else { return }
            await block()
        }
    }

    private func performUndoNow() async {
        guard let operation = undoStack.popLast() else {
            refreshUndoState()
            return
        }

        isUndoRedoInProgress = true
        refreshUndoState()
        defer {
            isUndoRedoInProgress = false
            refreshUndoState()
        }

        let succeeded = await operation.undo(self)
        if succeeded {
            redoStack.append(operation)
            if redoStack.count > maxUndoHistorySize {
                redoStack.removeFirst(redoStack.count - maxUndoHistorySize)
            }
        } else {
            undoStack.append(operation)
        }
    }

    private func performRedoNow() async {
        guard let operation = redoStack.popLast() else {
            refreshUndoState()
            return
        }

        isUndoRedoInProgress = true
        refreshUndoState()
        defer {
            isUndoRedoInProgress = false
            refreshUndoState()
        }

        let succeeded = await operation.redo(self)
        if succeeded {
            undoStack.append(operation)
            if undoStack.count > maxUndoHistorySize {
                undoStack.removeFirst(undoStack.count - maxUndoHistorySize)
            }
        } else {
            redoStack.append(operation)
        }
    }

    private var shouldCaptureUndoOperations: Bool {
        isUndoRedoInProgress == false
        && isApplyingRemoteChanges == false
        && undoCaptureSuppressionDepth == 0
    }

    private func withUndoCaptureSuppressed<T>(_ body: () async throws -> T) async rethrows -> T {
        undoCaptureSuppressionDepth += 1
        defer { undoCaptureSuppressionDepth = max(0, undoCaptureSuppressionDepth - 1) }
        return try await body()
    }

    private func recordUndoOperation(
        label: String,
        undo: @escaping @MainActor (CloudKitStore) async -> Bool,
        redo: @escaping @MainActor (CloudKitStore) async -> Bool
    ) {
        guard shouldCaptureUndoOperations else { return }
        let operation = UndoOperation(
            id: UUID(),
            timestamp: Date(),
            label: label,
            undo: undo,
            redo: redo
        )
        undoStack.append(operation)
        if undoStack.count > maxUndoHistorySize {
            undoStack.removeFirst(undoStack.count - maxUndoHistorySize)
        }
        redoStack.removeAll()
        refreshUndoState()
    }

    private func clearUndoHistory() {
        undoStack.removeAll()
        redoStack.removeAll()
        refreshUndoState()
    }

    private func refreshUndoState() {
        canUndo = undoStack.isEmpty == false && isUndoRedoInProgress == false
        canRedo = redoStack.isEmpty == false && isUndoRedoInProgress == false
        nextUndoActionLabel = undoStack.last?.label
        nextRedoActionLabel = redoStack.last?.label
    }

    init(service: CloudKitService = CloudKitService(), usePreviewData: Bool = false) {
        self.service = service
        self.isPreviewData = usePreviewData
        setLearningObjectives(defaultLearningObjectivesWithResolvedParents())

        if usePreviewData {
            let previewGroup = CohortGroup(name: "Preview Group", colorHex: "#3B82F6")
            let previewDomain = Domain(name: "Preview Domain", colorHex: "#10B981")
            let previewStudent = Student(name: "Preview Student", group: previewGroup, session: .morning, domain: previewDomain)

            let progress = ObjectiveProgress(objectiveCode: "A.1", completionPercentage: 75)
            progress.student = previewStudent
            previewStudent.progressRecords = [progress]

            groups = [previewGroup]
            domains = [previewDomain]
            students = [previewStudent]
            categoryLabels = [
                CategoryLabel(code: "A", title: "Able to apply 100% of core LOs for chosen path")
            ]
            setLearningObjectives(defaultLearningObjectivesWithResolvedParents())
            rebuildAllDerivedCaches()
            hasLoaded = true
            hasCachedSnapshotData = true
            cachedSnapshotDate = Date()
        }
    }

    func loadIfNeeded() async {
        guard hasLoaded == false else { return }
        await loadSheets()
        if restoreSnapshotIfAvailable() {
            hasLoaded = true
            hasCachedSnapshotData = true
            isShowingStaleSnapshot = true
            isOfflineUsingSnapshot = false
            startLiveSyncIfNeeded()
            Task { [weak self] in
                guard let self else { return }
                await self.ensureLearningObjectivesSeededIfNeeded()
                await self.migrateLegacyGroupMembershipsIfNeeded()
            }
            if syncCoordinator == nil {
                Task { [weak self] in
                    guard let self else { return }
                    await self.reloadAllData(force: true, showLoadingUI: false, suppressErrorsWhenUsingSnapshot: true)
                }
            }
            return
        }
        await reloadAllData()
    }

    func reloadAllData(force: Bool = false) async {
        await reloadAllData(force: force, showLoadingUI: true, suppressErrorsWhenUsingSnapshot: false)
    }

    private func reloadAllData(
        force: Bool,
        showLoadingUI: Bool,
        suppressErrorsWhenUsingSnapshot: Bool
    ) async {
        if isLoading {
            guard force else { return }
        }

        if showLoadingUI {
            isLoading = true
        }
        lastErrorMessage = nil
        defer {
            if showLoadingUI {
                isLoading = false
            }
        }

        do {
            let status = try await service.accountStatus()
            if status != .available {
                requiresICloudLogin = true
                if hasCachedSnapshotData {
                    isOfflineUsingSnapshot = true
                    isShowingStaleSnapshot = true
                } else {
                    lastErrorMessage = "iCloud account not available (\(status.rawValue)). Sign in to iCloud on this Mac, then relaunch the app."
                }
                return
            }
            requiresICloudLogin = false

            let cohortRecord = try await ensureCohortRecord()
            cohortRecordID = cohortRecord.recordID

            let cohortRef = CKRecord.Reference(recordID: cohortRecord.recordID, action: .none)

            async let groupRecords = service.queryRecords(
                ofType: RecordType.cohortGroup,
                predicate: NSPredicate(format: "cohortRef == %@", cohortRef),
                sortDescriptors: [NSSortDescriptor(key: Field.name, ascending: true)]
            )
            async let domainRecords = service.queryRecords(
                ofType: RecordType.domain,
                predicate: NSPredicate(format: "cohortRef == %@", cohortRef),
                sortDescriptors: [NSSortDescriptor(key: Field.name, ascending: true)]
            )
            async let labelRecords = service.queryRecords(
                ofType: RecordType.categoryLabel,
                predicate: NSPredicate(format: "cohortRef == %@", cohortRef),
                sortDescriptors: [NSSortDescriptor(key: Field.key, ascending: true)]
            )
            async let learningObjectiveRecords = service.queryRecords(
                ofType: RecordType.learningObjective,
                predicate: NSPredicate(format: "cohortRef == %@", cohortRef),
                sortDescriptors: [NSSortDescriptor(key: Field.sortOrder, ascending: true)]
            )
            async let membershipRecords = service.queryRecords(
                ofType: RecordType.studentGroupMembership,
                predicate: NSPredicate(format: "cohortRef == %@", cohortRef),
                sortDescriptors: [NSSortDescriptor(key: Field.createdAt, ascending: true)]
            )
            async let studentRecords = service.queryRecords(
                ofType: RecordType.student,
                predicate: NSPredicate(format: "cohortRef == %@", cohortRef),
                sortDescriptors: [NSSortDescriptor(key: Field.createdAt, ascending: true)]
            )
            async let progressRecords = service.queryRecords(
                ofType: RecordType.objectiveProgress,
                predicate: NSPredicate(format: "cohortRef == %@", cohortRef)
            )
            async let expertiseCheckScoreRecords = service.queryRecords(
                ofType: RecordType.expertiseCheckObjectiveScore,
                predicate: NSPredicate(format: "cohortRef == %@", cohortRef)
            )

            let (
                fetchedGroupRecords,
                fetchedDomainRecords,
                fetchedLabelRecords,
                fetchedLearningObjectiveRecords,
                fetchedMembershipRecords,
                fetchedStudentRecords,
                fetchedProgressRecords,
                fetchedExpertiseCheckScoreRecords
            ) = try await (
                groupRecords,
                domainRecords,
                labelRecords,
                learningObjectiveRecords,
                membershipRecords,
                studentRecords,
                progressRecords,
                expertiseCheckScoreRecords
            )

            clearRecordTrackingStateForFullReload()

            let mappedGroups = fetchedGroupRecords.map { mapGroup(from: $0) }
            let mappedDomains = fetchedDomainRecords.map { mapDomain(from: $0) }
            let mappedLearningObjectives = mapLearningObjectives(from: fetchedLearningObjectiveRecords)
            let mappedLabels = fetchedLabelRecords.map { mapCategoryLabel(from: $0) }
            let mappedExpertiseCheckScores = fetchedExpertiseCheckScoreRecords.compactMap {
                mapExpertiseCheckObjectiveScore(from: $0)
            }

            let groupMap = dictionaryByRecordName(items: mappedGroups, recordNameLookup: groupRecordNameByID)
            let domainMap = dictionaryByRecordName(items: mappedDomains, recordNameLookup: domainRecordNameByID)
            let mappedStudents = fetchedStudentRecords.map { mapStudent(from: $0, groupMap: groupMap, domainMap: domainMap) }
            let studentMap = dictionaryByRecordName(items: mappedStudents, recordNameLookup: studentRecordNameByID)
            let mappedMemberships = fetchedMembershipRecords.compactMap { record in
                mapMembership(from: record, studentMap: studentMap, groupMap: groupMap)
            }

            let progressByStudentRecordName = Dictionary(grouping: fetchedProgressRecords) { record in
                studentReference(from: record)?.recordID.recordName ?? ""
            }
            for student in mappedStudents {
                let studentRecordName = studentRecordNameByID[student.id] ?? student.id.uuidString
                let studentProgressRecords = progressByStudentRecordName[studentRecordName] ?? []
                let mappedProgress = studentProgressRecords.map { mapProgress(from: $0, student: student) }
                student.progressRecords = deduplicatedProgress(mappedProgress).sorted { $0.objectiveCode < $1.objectiveCode }
            }

            mergeFetchedGroups(mappedGroups)
            mergeFetchedDomains(mappedDomains)
            mergeFetchedCategoryLabels(mappedLabels)
            memberships = uniqueMemberships(mappedMemberships)
            students = mappedStudents.sorted { $0.createdAt < $1.createdAt }
            applyExpertiseCheckScores(mappedExpertiseCheckScores)
            if mappedLearningObjectives.isEmpty {
                setLearningObjectives(defaultLearningObjectivesWithResolvedParents())
            } else {
                setLearningObjectives(mappedLearningObjectives)
            }
            refreshLegacyGroupConvenience()
            rebuildAllDerivedCaches()

            progressLoadedStudentIDs = Set(students.map(\.id))
            customPropertiesLoadedStudentIDs.removeAll()

            // Full reload is authoritative; move the incremental sync cursor forward.
            let syncDate = Date()
            lastSyncDate = syncDate
            hasLoaded = true
            hasCachedSnapshotData = true
            isShowingStaleSnapshot = false
            isOfflineUsingSnapshot = false
            cachedSnapshotDate = syncDate

            startLiveSyncIfNeeded()
            scheduleSnapshotPersistence()
            Task { [weak self] in
                guard let self else { return }
                await self.ensureLearningObjectivesSeededIfNeeded()
                await self.migrateLegacyGroupMembershipsIfNeeded()
            }
        } catch {
            let detail = service.describe(error)
            if hasCachedSnapshotData && suppressErrorsWhenUsingSnapshot {
                isOfflineUsingSnapshot = true
                isShowingStaleSnapshot = true
            } else {
                lastErrorMessage = friendlyMessage(for: error, detail: detail)
            }
        }
    }

    func hardRefreshFromCloudKit() async {
        await reloadAllData(force: true)
    }

    func addGroup(name: String, colorHex: String?) async {
        lastErrorMessage = nil
        guard await requireWriteAccess() else { return }
        guard let cohortRecordID else {
            await reloadAllData()
            return
        }

        let group = CohortGroup(name: name, colorHex: colorHex)
        groups.append(group)
        groups.sort { $0.name < $1.name }
        pendingGroupCreateIDs.insert(group.id)

        let recordID = CKRecord.ID(recordName: group.id.uuidString)
        groupRecordNameByID[group.id] = recordID.recordName
        unconfirmedGroupRecordNames.insert(recordID.recordName)
        markRecordRecentlyWritten(recordType: RecordType.cohortGroup, recordName: recordID.recordName)

        let record = CKRecord(recordType: RecordType.cohortGroup, recordID: recordID)
        record[Field.cohortRef] = CKRecord.Reference(recordID: cohortRecordID, action: .none)
        record[Field.name] = group.name
        record[Field.colorHex] = group.colorHex
        applyAuditFields(to: record, createdAt: Date())

        do {
            let saved = try await service.save(record: record)
            groupRecordNameByID[group.id] = saved.recordID.recordName
            pendingGroupCreateIDs.remove(group.id)
            unconfirmedGroupRecordNames.remove(recordID.recordName)
            unconfirmedGroupRecordNames.insert(saved.recordID.recordName)
            markRecordRecentlyWritten(recordType: RecordType.cohortGroup, recordName: saved.recordID.recordName)
            syncCoordinator?.noteLocalWrite()
            let snapshot = snapshotGroup(group)
            recordUndoOperation(
                label: "Create Group",
                undo: { store in await store.deleteGroupByID(snapshot.id) },
                redo: { store in await store.restoreGroupSnapshot(snapshot) }
            )
        } catch {
            pendingGroupCreateIDs.remove(group.id)
            unconfirmedGroupRecordNames.remove(recordID.recordName)
            lastErrorMessage = "Failed to save group: \(error.localizedDescription)"
        }
    }

    func renameGroup(_ group: CohortGroup, newName: String) async {
        lastErrorMessage = nil
        guard await requireWriteAccess() else { return }
        let previousSnapshot = snapshotGroup(group)
        let previousName = group.name
        group.name = newName
        groups.sort { $0.name < $1.name }

        do {
            try await saveGroupRecord(group)
            rebuildGroupMembershipCaches()
            let nextSnapshot = snapshotGroup(group)
            recordUndoOperation(
                label: "Rename Group",
                undo: { store in await store.restoreGroupSnapshot(previousSnapshot) },
                redo: { store in await store.restoreGroupSnapshot(nextSnapshot) }
            )
        } catch {
            group.name = previousName
            groups.sort { $0.name < $1.name }
            rebuildGroupMembershipCaches()
            lastErrorMessage = "Failed to rename group: \(error.localizedDescription)"
        }
    }

    func deleteGroup(_ group: CohortGroup) async {
        lastErrorMessage = nil
        guard await requireWriteAccess() else { return }
        let undoBundle = snapshotGroupDeleteBundle(group)
        let recordID = recordID(for: group, lookup: groupRecordNameByID)

        let affectedStudentIDs = Set(
            memberships
                .filter { $0.group?.id == group.id }
                .compactMap { $0.student?.id }
        )
        let affected = students.filter { affectedStudentIDs.contains($0.id) || $0.group?.id == group.id }

        groups.removeAll { $0.id == group.id }
        rebuildGroupMembershipCaches()

        do {
            try await deleteMemberships(forGroupID: group.id)
            try await service.delete(recordID: recordID)
            refreshLegacyGroupConvenience()
            for student in affected {
                try await saveStudentRecord(student)
            }
            syncCoordinator?.noteLocalWrite()
            recordUndoOperation(
                label: "Delete Group",
                undo: { store in await store.restoreDeletedGroup(undoBundle) },
                redo: { store in await store.deleteGroupByID(undoBundle.group.id) }
            )
        } catch {
            lastErrorMessage = "Failed to delete group: \(error.localizedDescription)"
            await reloadAllData()
        }
    }

    func addDomain(name: String, colorHex: String?, recordUndo: Bool = true) async {
        lastErrorMessage = nil
        guard await requireWriteAccess() else { return }
        guard let cohortRecordID else {
            await reloadAllData()
            return
        }

        let domain = Domain(name: name, colorHex: colorHex)
        domains.append(domain)
        domains.sort { $0.name < $1.name }
        pendingDomainCreateIDs.insert(domain.id)

        let recordID = CKRecord.ID(recordName: domain.id.uuidString)
        domainRecordNameByID[domain.id] = recordID.recordName
        unconfirmedDomainRecordNames.insert(recordID.recordName)
        markRecordRecentlyWritten(recordType: RecordType.domain, recordName: recordID.recordName)

        let record = CKRecord(recordType: RecordType.domain, recordID: recordID)
        record[Field.cohortRef] = CKRecord.Reference(recordID: cohortRecordID, action: .none)
        record[Field.name] = domain.name
        record[Field.colorHex] = domain.colorHex
        record[Field.overallMode] = domain.overallMode.rawValue
        applyAuditFields(to: record, createdAt: Date())

        do {
            let saved = try await service.save(record: record)
            domainRecordNameByID[domain.id] = saved.recordID.recordName
            pendingDomainCreateIDs.remove(domain.id)
            unconfirmedDomainRecordNames.remove(recordID.recordName)
            unconfirmedDomainRecordNames.insert(saved.recordID.recordName)
            markRecordRecentlyWritten(recordType: RecordType.domain, recordName: saved.recordID.recordName)
            syncCoordinator?.noteLocalWrite()
            if recordUndo {
                let snapshot = snapshotDomain(domain)
                recordUndoOperation(
                    label: "Create Expertise Check",
                    undo: { store in await store.deleteDomainByID(snapshot.id) },
                    redo: { store in await store.restoreDomainSnapshot(snapshot) }
                )
            }
        } catch {
            pendingDomainCreateIDs.remove(domain.id)
            unconfirmedDomainRecordNames.remove(recordID.recordName)
            domains.removeAll { $0.id == domain.id }
            domainRecordNameByID.removeValue(forKey: domain.id)
            lastErrorMessage = "Failed to add domain: \(error.localizedDescription)"
        }
    }

    func ensurePresetDomains() async {
        lastErrorMessage = nil
        guard await requireWriteAccess() else { return }

        let presets = ["Tech", "Design", "Domain Expert"]
        var existing = Set(domains.map { normalizedDomainName($0.name) })

        for preset in presets {
            let normalized = normalizedDomainName(preset)
            guard existing.contains(normalized) == false else { continue }
            await addDomain(name: preset, colorHex: nil, recordUndo: false)
            existing.insert(normalized)
        }
    }

    func renameDomain(_ domain: Domain, newName: String) async {
        lastErrorMessage = nil
        guard await requireWriteAccess() else { return }
        let previousSnapshot = snapshotDomain(domain)
        let previousName = domain.name
        domain.name = newName
        domains.sort { $0.name < $1.name }

        do {
            try await saveDomainRecord(domain)
            let nextSnapshot = snapshotDomain(domain)
            recordUndoOperation(
                label: "Rename Expertise Check",
                undo: { store in await store.restoreDomainSnapshot(previousSnapshot) },
                redo: { store in await store.restoreDomainSnapshot(nextSnapshot) }
            )
        } catch {
            domain.name = previousName
            domains.sort { $0.name < $1.name }
            lastErrorMessage = "Failed to rename domain: \(error.localizedDescription)"
        }
    }

    func deleteDomain(_ domain: Domain) async {
        lastErrorMessage = nil
        guard await requireWriteAccess() else { return }
        let undoBundle = snapshotDomainDeleteBundle(domain)
        let recordID = recordID(for: domain, lookup: domainRecordNameByID)

        let affected = students.filter { $0.domain?.id == domain.id }
        affected.forEach { $0.domain = nil }
        domains.removeAll { $0.id == domain.id }

        do {
            try await deleteExpertiseCheckScores(for: domain)
            try await service.delete(recordID: recordID)
            for student in affected {
                try await saveStudentRecord(student)
            }
            syncCoordinator?.noteLocalWrite()
            recordUndoOperation(
                label: "Delete Expertise Check",
                undo: { store in await store.restoreDeletedDomain(undoBundle) },
                redo: { store in await store.deleteDomainByID(undoBundle.domain.id) }
            )
        } catch {
            lastErrorMessage = "Failed to delete domain: \(error.localizedDescription)"
            await reloadAllData()
        }
    }

    func addStudent(
        name: String,
        group: CohortGroup?,
        session: Session,
        domain: Domain?,
        customProperties: [CustomPropertyRow]
    ) async -> Student? {
        await addStudent(
            name: name,
            groups: group.map { [$0] } ?? [],
            session: session,
            domain: domain,
            customProperties: customProperties
        )
    }

    func addStudent(
        name: String,
        groups: [CohortGroup],
        session: Session,
        domain: Domain?,
        customProperties: [CustomPropertyRow]
    ) async -> Student? {
        lastErrorMessage = nil
        guard await requireWriteAccess() else { return nil }
        guard let cohortRecordID else {
            await reloadAllData()
            return nil
        }

        let student = Student(name: name, group: nil, session: session, domain: domain)
        students.append(student)
        students.sort { $0.createdAt < $1.createdAt }
        rebuildProgressCaches()

        let recordID = CKRecord.ID(recordName: student.id.uuidString)
        studentRecordNameByID[student.id] = recordID.recordName
        markRecordRecentlyWritten(recordType: RecordType.student, recordName: recordID.recordName)

        let record = CKRecord(recordType: RecordType.student, recordID: recordID)
        applyStudentFields(student, to: record, cohortRecordID: cohortRecordID)

        do {
            let saved = try await service.save(record: record)
            studentRecordNameByID[student.id] = saved.recordID.recordName
            markRecordRecentlyWritten(recordType: RecordType.student, recordName: saved.recordID.recordName)

            if customProperties.isEmpty == false {
                try await replaceCustomProperties(for: student, rows: customProperties)
            }
            if groups.isEmpty == false {
                try await setGroupsInternal(for: student, groups: groups, updateLegacyGroupField: true)
            }

            syncCoordinator?.noteLocalWrite()
            let createdBundle = snapshotStudentUndoBundle(student)
            recordUndoOperation(
                label: "Create Student",
                undo: { store in await store.deleteStudentByID(createdBundle.student.id) },
                redo: { store in await store.restoreDeletedStudent(createdBundle) }
            )
            return student
        } catch {
            students.removeAll { $0.id == student.id }
            lastErrorMessage = "Failed to add student: \(error.localizedDescription)"
            return nil
        }
    }

    func updateStudent(
        _ student: Student,
        name: String,
        group: CohortGroup?,
        session: Session,
        domain: Domain?,
        customProperties: [CustomPropertyRow]
    ) async {
        let resolvedGroups: [CohortGroup]
        if let group {
            resolvedGroups = [group]
        } else {
            let existingExplicitGroups = explicitGroups(for: student)
            if existingExplicitGroups.count > 1 {
                resolvedGroups = existingExplicitGroups
            } else {
                resolvedGroups = []
            }
        }

        await updateStudent(
            student,
            name: name,
            groups: resolvedGroups,
            session: session,
            domain: domain,
            customProperties: customProperties
        )
    }

    func updateStudent(
        _ student: Student,
        name: String,
        groups: [CohortGroup],
        session: Session,
        domain: Domain?,
        customProperties: [CustomPropertyRow]
    ) async {
        lastErrorMessage = nil
        guard await requireWriteAccess() else { return }
        let previousBundle = snapshotStudentUndoBundle(student)
        student.name = name
        student.session = session
        student.domain = domain

        do {
            try await saveStudentRecord(student)
            try await setGroupsInternal(for: student, groups: groups, updateLegacyGroupField: true)
            try await replaceCustomProperties(for: student, rows: customProperties)
            let updatedBundle = snapshotStudentUndoBundle(student)
            if previousBundle != updatedBundle {
                recordUndoOperation(
                    label: "Edit Student",
                    undo: { store in await store.restoreStudentEditableState(previousBundle) },
                    redo: { store in await store.restoreStudentEditableState(updatedBundle) }
                )
            }
        } catch {
            lastErrorMessage = "Failed to update student: \(error.localizedDescription)"
            await reloadAllData()
        }
    }

    func renameStudent(_ student: Student, newName: String) async {
        lastErrorMessage = nil
        guard await requireWriteAccess() else { return }
        let previousBundle = snapshotStudentUndoBundle(student)
        let previousName = student.name
        student.name = newName

        do {
            try await saveStudentRecord(student)
            let updatedBundle = snapshotStudentUndoBundle(student)
            if previousBundle != updatedBundle {
                recordUndoOperation(
                    label: "Rename Student",
                    undo: { store in await store.restoreStudentEditableState(previousBundle) },
                    redo: { store in await store.restoreStudentEditableState(updatedBundle) }
                )
            }
        } catch {
            student.name = previousName
            lastErrorMessage = "Failed to rename student: \(error.localizedDescription)"
        }
    }

    func moveStudent(_ student: Student, to group: CohortGroup?) async {
        lastErrorMessage = nil
        guard await requireWriteAccess() else { return }
        let previousGroupIDs = explicitGroupIDs(for: student)

        do {
            try await setGroupsInternal(for: student, groups: group.map { [$0] } ?? [], updateLegacyGroupField: true)
            let newGroupIDs = explicitGroupIDs(for: student)
            if previousGroupIDs != newGroupIDs {
                let studentID = student.id
                recordUndoOperation(
                    label: "Move Student",
                    undo: { store in await store.applyStudentGroupSelection(studentID: studentID, groupIDs: previousGroupIDs) },
                    redo: { store in await store.applyStudentGroupSelection(studentID: studentID, groupIDs: newGroupIDs) }
                )
            }
        } catch {
            lastErrorMessage = "Failed to move student: \(error.localizedDescription)"
        }
    }

    func deleteStudent(_ student: Student) async {
        lastErrorMessage = nil
        guard await requireWriteAccess() else { return }
        let undoBundle = await snapshotDeletedStudentBundle(student)
        let recordID = recordID(for: student, lookup: studentRecordNameByID)

        students.removeAll { $0.id == student.id }
        rebuildProgressCaches()
        rebuildGroupMembershipCaches()

        do {
            try await service.delete(recordID: recordID)
            try await deleteMemberships(forStudentID: student.id)
            try await deleteProgress(for: student)
            try await deleteCustomProperties(for: student)
            syncCoordinator?.noteLocalWrite()
            recordUndoOperation(
                label: "Delete Student",
                undo: { store in await store.restoreDeletedStudent(undoBundle) },
                redo: { store in await store.deleteStudentByID(undoBundle.student.id) }
            )
        } catch {
            lastErrorMessage = "Failed to delete student: \(error.localizedDescription)"
            await reloadAllData()
        }
    }

    func groups(for student: Student) -> [CohortGroup] {
        let explicitGroups = groupsByStudentIDCache[student.id] ?? []
        if explicitGroups.isEmpty {
            if let legacyGroup = student.group {
                return [legacyGroup]
            }
            return []
        }
        return explicitGroups
    }

    func primaryGroup(for student: Student) -> CohortGroup? {
        let assignedGroups = groups(for: student)
        guard assignedGroups.count == 1 else { return nil }
        return assignedGroups.first
    }

    func isUngrouped(student: Student) -> Bool {
        let explicitGroups = groupsByStudentIDCache[student.id] ?? []
        if explicitGroups.isEmpty == false {
            return false
        }
        return student.group == nil
    }

    func setGroups(
        for student: Student,
        groups: [CohortGroup],
        updateLegacyGroupField: Bool = true
    ) async {
        lastErrorMessage = nil
        guard await requireWriteAccess() else { return }
        let previousGroupIDs = explicitGroupIDs(for: student)
        do {
            try await setGroupsInternal(
                for: student,
                groups: groups,
                updateLegacyGroupField: updateLegacyGroupField
            )
            let updatedGroupIDs = explicitGroupIDs(for: student)
            if previousGroupIDs != updatedGroupIDs {
                let studentID = student.id
                recordUndoOperation(
                    label: "Update Group Memberships",
                    undo: { store in await store.applyStudentGroupSelection(studentID: studentID, groupIDs: previousGroupIDs) },
                    redo: { store in await store.applyStudentGroupSelection(studentID: studentID, groupIDs: updatedGroupIDs) }
                )
            }
        } catch {
            lastErrorMessage = "Failed to update student groups: \(error.localizedDescription)"
            await reloadAllData()
        }
    }

    func addStudentToGroup(_ student: Student, group: CohortGroup) async {
        lastErrorMessage = nil
        guard await requireWriteAccess() else { return }
        let previousGroupIDs = explicitGroupIDs(for: student)
        do {
            try await addStudentToGroupInternal(student, group: group, updateLegacyGroupField: true)
            let updatedGroupIDs = explicitGroupIDs(for: student)
            if previousGroupIDs != updatedGroupIDs {
                let studentID = student.id
                recordUndoOperation(
                    label: "Add Student to Group",
                    undo: { store in await store.applyStudentGroupSelection(studentID: studentID, groupIDs: previousGroupIDs) },
                    redo: { store in await store.applyStudentGroupSelection(studentID: studentID, groupIDs: updatedGroupIDs) }
                )
            }
        } catch {
            lastErrorMessage = "Failed to add student to group: \(error.localizedDescription)"
            await reloadAllData()
        }
    }

    func removeStudentFromGroup(_ student: Student, group: CohortGroup) async {
        lastErrorMessage = nil
        guard await requireWriteAccess() else { return }
        let previousGroupIDs = explicitGroupIDs(for: student)
        do {
            try await removeStudentFromGroupInternal(student, group: group, updateLegacyGroupField: true)
            let updatedGroupIDs = explicitGroupIDs(for: student)
            if previousGroupIDs != updatedGroupIDs {
                let studentID = student.id
                recordUndoOperation(
                    label: "Remove Student from Group",
                    undo: { store in await store.applyStudentGroupSelection(studentID: studentID, groupIDs: previousGroupIDs) },
                    redo: { store in await store.applyStudentGroupSelection(studentID: studentID, groupIDs: updatedGroupIDs) }
                )
            }
        } catch {
            lastErrorMessage = "Failed to remove student from group: \(error.localizedDescription)"
            await reloadAllData()
        }
    }

    func createLearningObjective(
        code: String,
        title: String,
        description: String = "",
        isQuantitative: Bool = false,
        parent: LearningObjective? = nil,
        sortOrder: Int? = nil
    ) async -> LearningObjective? {
        lastErrorMessage = nil
        guard await requireWriteAccess() else { return nil }
        let normalizedCode = normalizedObjectiveCode(code)
        guard normalizedCode.isEmpty == false else {
            lastErrorMessage = "Learning objective code cannot be empty."
            return nil
        }
        guard hasObjectiveCodeConflict(normalizedCode, excluding: nil) == false else {
            lastErrorMessage = "A learning objective with code '\(normalizedCode)' already exists."
            return nil
        }

        let objective = LearningObjective(
            code: normalizedCode,
            title: title,
            description: description,
            isQuantitative: isQuantitative,
            parentCode: parent?.code,
            parentId: parent?.id,
            sortOrder: sortOrder ?? ((allLearningObjectives.map(\.sortOrder).max() ?? 0) + 1),
            isArchived: false
        )

        allLearningObjectives.append(objective)
        setLearningObjectives(allLearningObjectives)
        pendingLearningObjectiveCreateIDs.insert(objective.id)
        let localRecordName = objective.id.uuidString
        unconfirmedLearningObjectiveRecordNames.insert(localRecordName)

        do {
            try await saveLearningObjectiveRecord(objective)
            unconfirmedLearningObjectiveRecordNames.remove(localRecordName)
            let createdSnapshot = snapshotLearningObjective(objective)
            let archivedSnapshot = snapshotLearningObjective(objective, isArchivedOverride: true)
            let label = objective.isRootCategory ? "Create Success Criterion" : "Create Milestone"
            recordUndoOperation(
                label: label,
                undo: { store in await store.restoreLearningObjectiveSnapshot(archivedSnapshot) },
                redo: { store in await store.restoreLearningObjectiveSnapshot(createdSnapshot) }
            )
            return objective
        } catch {
            pendingLearningObjectiveCreateIDs.remove(objective.id)
            unconfirmedLearningObjectiveRecordNames.remove(localRecordName)
            allLearningObjectives.removeAll { $0.id == objective.id }
            setLearningObjectives(allLearningObjectives)
            lastErrorMessage = "Failed to create learning objective: \(error.localizedDescription)"
            return nil
        }
    }

    func updateLearningObjective(
        _ objective: LearningObjective,
        code: String,
        title: String,
        description: String,
        isQuantitative: Bool,
        parent: LearningObjective?,
        sortOrder: Int,
        isArchived: Bool
    ) async {
        lastErrorMessage = nil
        guard await requireWriteAccess() else { return }
        let previousSnapshot = snapshotLearningObjective(objective)
        let normalizedCode = normalizedObjectiveCode(code)
        guard normalizedCode.isEmpty == false else {
            lastErrorMessage = "Learning objective code cannot be empty."
            return
        }
        guard hasObjectiveCodeConflict(normalizedCode, excluding: objective.id) == false else {
            lastErrorMessage = "Another learning objective already uses code '\(normalizedCode)'."
            return
        }

        let previousCode = objective.code
        let previousTitle = objective.title
        let previousDescription = objective.objectiveDescription
        let previousIsQuantitative = objective.isQuantitative
        let previousParentId = objective.parentId
        let previousParentCode = objective.parentCode
        let previousSortOrder = objective.sortOrder
        let previousIsArchived = objective.isArchived

        objective.code = normalizedCode
        objective.title = title
        objective.objectiveDescription = description
        objective.isQuantitative = isQuantitative
        objective.parentId = parent?.id
        objective.parentCode = parent?.code
        objective.sortOrder = sortOrder
        objective.isArchived = isArchived
        setLearningObjectives(allLearningObjectives)

        do {
            try await saveLearningObjectiveRecord(objective)
            let updatedSnapshot = snapshotLearningObjective(objective)
            if previousSnapshot != updatedSnapshot {
                let label = objective.isRootCategory ? "Edit Success Criterion" : "Edit Milestone"
                recordUndoOperation(
                    label: label,
                    undo: { store in await store.restoreLearningObjectiveSnapshot(previousSnapshot) },
                    redo: { store in await store.restoreLearningObjectiveSnapshot(updatedSnapshot) }
                )
            }
        } catch {
            objective.code = previousCode
            objective.title = previousTitle
            objective.objectiveDescription = previousDescription
            objective.isQuantitative = previousIsQuantitative
            objective.parentId = previousParentId
            objective.parentCode = previousParentCode
            objective.sortOrder = previousSortOrder
            objective.isArchived = previousIsArchived
            setLearningObjectives(allLearningObjectives)
            lastErrorMessage = "Failed to update learning objective: \(error.localizedDescription)"
        }
    }

    func archiveLearningObjective(_ objective: LearningObjective) async {
        lastErrorMessage = nil
        guard await requireWriteAccess() else { return }
        guard objective.isArchived == false else { return }
        let previousSnapshot = snapshotLearningObjective(objective)
        objective.isArchived = true
        setLearningObjectives(allLearningObjectives)

        do {
            try await saveLearningObjectiveRecord(objective)
            let archivedSnapshot = snapshotLearningObjective(objective)
            let label = objective.isRootCategory ? "Archive Success Criterion" : "Archive Milestone"
            recordUndoOperation(
                label: label,
                undo: { store in await store.restoreLearningObjectiveSnapshot(previousSnapshot) },
                redo: { store in await store.restoreLearningObjectiveSnapshot(archivedSnapshot) }
            )
        } catch {
            objective.isArchived = false
            setLearningObjectives(allLearningObjectives)
            lastErrorMessage = "Failed to archive learning objective: \(error.localizedDescription)"
        }
    }

    func updateCategoryLabel(code: String, title: String) async {
        lastErrorMessage = nil
        let normalizedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedCode.isEmpty == false else { return }
        // Success Criteria (root categories) titles are read-only from UI pathways.
        if objectiveByCode(normalizedCode)?.isRootCategory == true {
            return
        }

        guard await requireWriteAccess() else { return }
        guard let cohortRecordID else {
            await reloadAllData()
            return
        }

        let label: CategoryLabel
        let isNewLabel: Bool
        if let existing = categoryLabels.first(where: { $0.key == normalizedCode }) {
            label = existing
            isNewLabel = false
            label.title = title
        } else {
            label = CategoryLabel(code: normalizedCode, title: title)
            isNewLabel = true
            categoryLabels.append(label)
            pendingCategoryLabelCreateKeys.insert(normalizedCode)
        }
        categoryLabels.sort { $0.key < $1.key }

        let activeCohortRecordName = cohortRecordID.recordName
        let recordID = CKRecord.ID(recordName: "\(activeCohortRecordName)::\(normalizedCode)")
        if isNewLabel {
            unconfirmedCategoryLabelRecordNames.insert(recordID.recordName)
        }
        markRecordRecentlyWritten(recordType: RecordType.categoryLabel, recordName: recordID.recordName)
        let record = CKRecord(recordType: RecordType.categoryLabel, recordID: recordID)
        record[Field.cohortRef] = CKRecord.Reference(recordID: cohortRecordID, action: .none)
        record[Field.key] = label.key
        record[Field.code] = label.code
        record[Field.title] = label.title
        applyAuditFields(to: record, createdAt: Date())

        do {
            try await service.save(record: record)
            pendingCategoryLabelCreateKeys.remove(normalizedCode)
            unconfirmedCategoryLabelRecordNames.remove(recordID.recordName)
            categoryLabelRecordNameByCode[normalizedCode] = recordID.recordName
            markRecordRecentlyWritten(recordType: RecordType.categoryLabel, recordName: recordID.recordName)
            syncCoordinator?.noteLocalWrite()
        } catch {
            pendingCategoryLabelCreateKeys.remove(normalizedCode)
            unconfirmedCategoryLabelRecordNames.remove(recordID.recordName)
            lastErrorMessage = "Failed to update category label: \(error.localizedDescription)"
        }
    }

    func loadProgressIfNeeded(for student: Student) async {
        lastErrorMessage = nil
        guard progressLoadedStudentIDs.contains(student.id) == false else { return }
        guard let cohortRecordID else { return }
        let studentRecordID = recordID(for: student, lookup: studentRecordNameByID)

        let cohortRef = CKRecord.Reference(recordID: cohortRecordID, action: .none)

        do {
            let records = try await queryProgressRecords(cohortRef: cohortRef, studentRecordID: studentRecordID)
            let mapped = records.map { mapProgress(from: $0, student: student) }
            student.progressRecords = mapped.sorted { $0.objectiveCode < $1.objectiveCode }
            progressLoadedStudentIDs.insert(student.id)
            scheduleObjectiveRefMigrationIfNeeded(records: records, studentRecordID: studentRecordID)
            rebuildProgressCaches()
        } catch {
            lastErrorMessage = "Failed to load progress: \(error.localizedDescription)"
        }
    }

    func setProgress(student: Student, objective: LearningObjective, value: Int) async {
        await setProgressInternal(student: student, objectiveCode: objective.code, objective: objective, value: value, notes: nil)
    }

    func setProgress(student: Student, objectiveCode: String, value: Int) async {
        await setProgressInternal(student: student, objectiveCode: objectiveCode, objective: nil, value: value, notes: nil)
    }

    func setProgress(student: Student, objective: LearningObjective, value: Int, notes: String) async {
        await setProgressInternal(
            student: student,
            objectiveCode: objective.code,
            objective: objective,
            value: value,
            notes: notes
        )
    }

    private func setProgressInternal(
        student: Student,
        objectiveCode: String,
        objective explicitObjective: LearningObjective?,
        value: Int,
        notes: String?
    ) async {
        lastErrorMessage = nil
        guard await requireWriteAccess() else { return }
        guard let cohortRecordID else { return }
        let studentRecordID = recordID(for: student, lookup: studentRecordNameByID)
        let objective = explicitObjective ?? objectiveByCode(objectiveCode)
        let canonicalObjectiveCode = objective?.code ?? objectiveCode
        let previousProgress = student.progressRecords.first(where: { existing in
            if let objective {
                return existing.objectiveId == objective.id || existing.objectiveCode == objective.code
            }
            return existing.objectiveCode == objectiveCode
        })
        let previousSnapshot = previousProgress.map { snapshotProgress($0, studentID: student.id) }

        let progress: ObjectiveProgress
        if let existing = student.progressRecords.first(where: { existing in
            if let objective {
                return existing.objectiveId == objective.id || existing.objectiveCode == objective.code
            }
            return existing.objectiveCode == objectiveCode
        }) {
            progress = existing
            progress.objectiveId = objective?.id
            progress.objectiveCode = canonicalObjectiveCode
            progress.updateCompletion(value)
            if let notes {
                progress.notes = notes
            }
        } else {
            progress = ObjectiveProgress(
                objectiveCode: canonicalObjectiveCode,
                completionPercentage: value,
                notes: notes ?? "",
                objectiveId: objective?.id,
                value: value
            )
            progress.student = student
            student.progressRecords.append(progress)
        }

        let duplicateProgress = student.progressRecords.filter { candidate in
            guard candidate.id != progress.id else { return false }
            if let objective {
                return candidate.objectiveId == objective.id || candidate.objectiveCode == objective.code
            }
            return candidate.objectiveCode == objectiveCode
        }
        for duplicate in duplicateProgress {
            student.progressRecords.removeAll { $0.id == duplicate.id }
            if let duplicateRecordName = progressRecordNameByID[duplicate.id] {
                do {
                    try await service.delete(recordID: CKRecord.ID(recordName: duplicateRecordName))
                } catch {
                    syncLogger.error("Failed to delete duplicate ObjectiveProgress record \(duplicateRecordName, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
            progressRecordNameByID.removeValue(forKey: duplicate.id)
        }
        rebuildProgressCaches()

        let progressRecordID = recordID(for: progress, lookup: progressRecordNameByID)
        markRecordRecentlyWritten(recordType: RecordType.objectiveProgress, recordName: progressRecordID.recordName)
        let record = CKRecord(recordType: RecordType.objectiveProgress, recordID: progressRecordID)
        record[Field.cohortRef] = CKRecord.Reference(recordID: cohortRecordID, action: .none)
        let studentRef = CKRecord.Reference(recordID: studentRecordID, action: .none)
        record[Field.studentRef] = studentRef
        record[Field.student] = CKRecord.Reference(recordID: studentRecordID, action: .none)
        record[Field.objectiveCode] = progress.objectiveCode
        record[Field.value] = progress.value
        record[Field.completionPercentage] = progress.completionPercentage
        record[Field.status] = progress.status.rawValue
        record[Field.notes] = progress.notes
        record[Field.lastUpdated] = progress.lastUpdated
        if let objective {
            let objectiveRecordID = recordID(for: objective, lookup: learningObjectiveRecordNameByID)
            record[Field.objectiveRef] = CKRecord.Reference(recordID: objectiveRecordID, action: .none)
        } else {
            record[Field.objectiveRef] = nil
        }
        applyAuditFields(to: record, createdAt: progress.lastUpdated)

        do {
            let saved = try await service.save(record: record)
            progressRecordNameByID[progress.id] = saved.recordID.recordName
            progressLoadedStudentIDs.insert(student.id)
            markRecordRecentlyWritten(recordType: RecordType.objectiveProgress, recordName: saved.recordID.recordName)
            rebuildProgressCaches()
            let updatedSnapshot = snapshotProgress(progress, studentID: student.id)
            if previousSnapshot != updatedSnapshot {
                let label = "Update Progress"
                recordUndoOperation(
                    label: label,
                    undo: { store in
                        if let previousSnapshot {
                            return await store.restoreProgressSnapshot(previousSnapshot)
                        }
                        return await store.deleteProgressBySnapshot(updatedSnapshot)
                    },
                    redo: { store in await store.restoreProgressSnapshot(updatedSnapshot) }
                )
            }
        } catch {
            lastErrorMessage = "Failed to save progress: \(error.localizedDescription)"
        }
    }

    func loadCustomPropertiesIfNeeded(for student: Student) async {
        lastErrorMessage = nil
        guard customPropertiesLoadedStudentIDs.contains(student.id) == false else { return }
        guard let cohortRecordID else { return }
        let studentRecordID = recordID(for: student, lookup: studentRecordNameByID)

        let cohortRef = CKRecord.Reference(recordID: cohortRecordID, action: .none)
        let studentRef = CKRecord.Reference(recordID: studentRecordID, action: .none)

        do {
            let predicate = NSPredicate(format: "cohortRef == %@ AND student == %@", cohortRef, studentRef)
            let records = try await service.queryRecords(ofType: RecordType.studentCustomProperty, predicate: predicate)
            let mapped = records.map { mapCustomProperty(from: $0, student: student) }
            student.customProperties = mapped.sorted { $0.sortOrder < $1.sortOrder }
            customPropertiesLoadedStudentIDs.insert(student.id)
        } catch {
            lastErrorMessage = "Failed to load custom properties: \(error.localizedDescription)"
        }
    }

    func resetLearningObjectivesToDefaultTemplate() async {
        lastErrorMessage = nil
        guard await requireWriteAccess() else { return }
        clearUndoHistory()
        isLoading = true
        resetProgress = ResetProgress(message: "Resetting data to base template...", step: 0, totalSteps: 11)
        defer {
            isLoading = false
            resetProgress = nil
        }

        do {
            let cohortRecordID = try await ensureCohortRecordIDForWrite()

            resetProgress = ResetProgress(message: "Deleting objective progress...", step: 1, totalSteps: 11)
            try await deleteAllRecords(ofType: RecordType.objectiveProgress, cohortRecordID: cohortRecordID)
            clearLocalObjectiveProgressState()

            resetProgress = ResetProgress(message: "Deleting custom properties...", step: 2, totalSteps: 11)
            try await deleteAllRecords(ofType: RecordType.studentCustomProperty, cohortRecordID: cohortRecordID)
            clearLocalCustomPropertyState()

            resetProgress = ResetProgress(message: "Deleting memberships...", step: 3, totalSteps: 11)
            try await deleteAllRecords(ofType: RecordType.studentGroupMembership, cohortRecordID: cohortRecordID)
            clearLocalMembershipState()

            resetProgress = ResetProgress(message: "Deleting students...", step: 4, totalSteps: 11)
            try await deleteAllRecords(ofType: RecordType.student, cohortRecordID: cohortRecordID)
            clearLocalStudentState()

            resetProgress = ResetProgress(message: "Deleting groups...", step: 5, totalSteps: 11)
            try await deleteAllRecords(ofType: RecordType.cohortGroup, cohortRecordID: cohortRecordID)
            clearLocalGroupState()

            resetProgress = ResetProgress(message: "Deleting category labels...", step: 6, totalSteps: 11)
            try await deleteAllRecords(ofType: RecordType.categoryLabel, cohortRecordID: cohortRecordID)
            clearLocalCategoryLabelState()

            resetProgress = ResetProgress(message: "Deleting Expertise Check review scores...", step: 7, totalSteps: 11)
            try await deleteAllRecords(ofType: RecordType.expertiseCheckObjectiveScore, cohortRecordID: cohortRecordID)

            resetProgress = ResetProgress(message: "Resetting Expertise Check to base defaults...", step: 8, totalSteps: 11)
            try await deleteAllRecords(ofType: RecordType.domain, cohortRecordID: cohortRecordID)
            clearLocalDomainState()

            resetProgress = ResetProgress(message: "Deleting Success Criteria and Milestones...", step: 9, totalSteps: 11)
            try await deleteAllRecords(ofType: RecordType.learningObjective, cohortRecordID: cohortRecordID)
            clearLocalLearningObjectiveState()

            resetProgress = ResetProgress(message: "Restoring default Success Criteria and Milestones...", step: 10, totalSteps: 11)
            let defaults = defaultLearningObjectivesWithResolvedParents()
            try await seedLearningObjectives(defaults)

            resetProgress = ResetProgress(message: "Restoring base Expertise Check defaults...", step: 11, totalSteps: 11)
            await ensurePresetDomains()

            setLearningObjectives(defaults)
            syncCoordinator?.noteLocalWrite()
        } catch {
            lastErrorMessage = "Failed to reset data to base template: \(error.localizedDescription)"
        }
    }

    func resetAllData() async {
        lastErrorMessage = nil
        guard await requireWriteAccess() else { return }
        clearUndoHistory()
        isLoading = true
        resetProgress = ResetProgress(message: "Resetting...", step: 0, totalSteps: 8)
        defer {
            isLoading = false
            resetProgress = nil
        }

        do {
            let cohortRecordID = try await ensureCohortRecordIDForWrite()

            resetProgress = ResetProgress(message: "Deleting progress...", step: 1, totalSteps: 8)
            try await deleteAllRecords(ofType: RecordType.objectiveProgress, cohortRecordID: cohortRecordID)
            resetProgress = ResetProgress(message: "Deleting custom properties...", step: 2, totalSteps: 8)
            try await deleteAllRecords(ofType: RecordType.studentCustomProperty, cohortRecordID: cohortRecordID)
            resetProgress = ResetProgress(message: "Deleting students...", step: 3, totalSteps: 8)
            try await deleteAllRecords(ofType: RecordType.student, cohortRecordID: cohortRecordID)
            resetProgress = ResetProgress(message: "Deleting category labels...", step: 4, totalSteps: 8)
            try await deleteAllRecords(ofType: RecordType.categoryLabel, cohortRecordID: cohortRecordID)
            resetProgress = ResetProgress(message: "Deleting memberships...", step: 5, totalSteps: 8)
            try await deleteAllRecords(ofType: RecordType.studentGroupMembership, cohortRecordID: cohortRecordID)
            resetProgress = ResetProgress(message: "Deleting groups...", step: 6, totalSteps: 8)
            try await deleteAllRecords(ofType: RecordType.cohortGroup, cohortRecordID: cohortRecordID)
            resetProgress = ResetProgress(message: "Deleting review scores...", step: 7, totalSteps: 8)
            try await deleteAllRecords(ofType: RecordType.expertiseCheckObjectiveScore, cohortRecordID: cohortRecordID)
            resetProgress = ResetProgress(message: "Deleting domains...", step: 8, totalSteps: 8)
            try await deleteAllRecords(ofType: RecordType.domain, cohortRecordID: cohortRecordID)

            resetProgress = ResetProgress(message: "Reloading data...", step: 8, totalSteps: 8)
            await reloadAllData()
            await ensurePresetDomains()
            syncCoordinator?.noteLocalWrite()
        } catch {
            lastErrorMessage = "Failed to reset data: \(error.localizedDescription)"
        }
    }

    func loadSheets() async {
        do {
            // Avoid TRUEPREDICATE on public DB cohorts because CloudKit may route that
            // through implicit recordName indexing, which is not guaranteed to be queryable
            // for this record type in development schemas.
            let records = try await service.queryRecords(
                ofType: RecordType.cohort,
                predicate: NSPredicate(format: "%K != %@", Field.cohortId, ""),
                sortDescriptors: [NSSortDescriptor(key: Field.createdAt, ascending: true)]
            )
            var mapped = records.map { mapSheet(from: $0) }
            if mapped.isEmpty {
                _ = try await ensureCohortRecord(for: defaultCohortId)
                let created = try await service.queryRecords(
                    ofType: RecordType.cohort,
                    predicate: NSPredicate(format: "cohortId == %@", defaultCohortId),
                    sortDescriptors: [NSSortDescriptor(key: Field.createdAt, ascending: true)]
                )
                mapped = created.map { mapSheet(from: $0) }
            }

            sheets = mapped.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            if let active = sheets.first(where: { $0.cohortId == activeCohortId }) ?? sheets.first(where: { $0.cohortId == defaultCohortId }) ?? sheets.first {
                activeSheet = active
                UserDefaults.standard.set(active.cohortId, forKey: activeCohortDefaultsKey)
            }
        } catch {
            lastErrorMessage = "Failed to load sheets: \(error.localizedDescription)"
        }
    }

    func createSheet(name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        guard beginSheetMutation() else { return }
        defer { endSheetMutation() }

        do {
            let cohortId = UUID().uuidString.lowercased()
            let record = try await ensureCohortRecord(for: cohortId, name: trimmed)
            await loadSheets()
            let mapped = mapSheet(from: record)
            await switchSheetInternal(to: mapped)
            await ensureLearningObjectivesSeededIfNeeded()
            await ensurePresetDomains()
        } catch {
            lastErrorMessage = "Failed to create sheet: \(error.localizedDescription)"
        }
    }

    func renameSheet(sheet: CohortSheet, name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        guard beginSheetMutation() else { return }
        defer { endSheetMutation() }

        do {
            let recordID = CKRecord.ID(recordName: sheet.id)
            let record = try await service.fetchRecord(with: recordID)
            record[Field.name] = trimmed
            applyAuditFields(to: record, createdAt: (record[Field.createdAt] as? Date) ?? Date())
            let saved = try await service.save(record: record)
            var updated = mapSheet(from: saved)
            if updated.cohortId.isEmpty {
                updated.cohortId = sheet.cohortId
            }
            sheets = sheets.map { $0.id == updated.id ? updated : $0 }
            if activeSheet?.id == updated.id {
                activeSheet = updated
            }
            sheets.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            lastErrorMessage = "Failed to rename sheet: \(error.localizedDescription)"
        }
    }

    func switchSheet(to sheet: CohortSheet) async {
        guard activeSheet?.id != sheet.id else { return }
        guard beginSheetMutation() else { return }
        defer { endSheetMutation() }
        await switchSheetInternal(to: sheet)
    }

    func deleteSheet(sheet: CohortSheet) async {
        guard beginSheetMutation() else { return }
        defer { endSheetMutation() }

        guard sheet.cohortId != defaultCohortId else {
            lastErrorMessage = "The main sheet cannot be deleted."
            return
        }
        guard activeSheet?.id != sheet.id else {
            lastErrorMessage = "Switch sheets before deleting this sheet."
            return
        }
        guard await requireWriteAccess() else { return }

        isLoading = true
        resetProgress = ResetProgress(message: "Deleting sheet...", step: 0, totalSteps: 10)
        defer {
            isLoading = false
            resetProgress = nil
        }

        do {
            let sheetRecordID = CKRecord.ID(recordName: sheet.id)

            resetProgress = ResetProgress(message: "Deleting objective progress...", step: 1, totalSteps: 10)
            try await deleteAllRecords(ofType: RecordType.objectiveProgress, cohortRecordID: sheetRecordID)
            resetProgress = ResetProgress(message: "Deleting custom properties...", step: 2, totalSteps: 10)
            try await deleteAllRecords(ofType: RecordType.studentCustomProperty, cohortRecordID: sheetRecordID)
            resetProgress = ResetProgress(message: "Deleting memberships...", step: 3, totalSteps: 10)
            try await deleteAllRecords(ofType: RecordType.studentGroupMembership, cohortRecordID: sheetRecordID)
            resetProgress = ResetProgress(message: "Deleting review scores...", step: 4, totalSteps: 10)
            try await deleteAllRecords(ofType: RecordType.expertiseCheckObjectiveScore, cohortRecordID: sheetRecordID)
            resetProgress = ResetProgress(message: "Deleting students...", step: 5, totalSteps: 10)
            try await deleteAllRecords(ofType: RecordType.student, cohortRecordID: sheetRecordID)
            resetProgress = ResetProgress(message: "Deleting groups...", step: 6, totalSteps: 10)
            try await deleteAllRecords(ofType: RecordType.cohortGroup, cohortRecordID: sheetRecordID)
            resetProgress = ResetProgress(message: "Deleting success criteria and milestones...", step: 7, totalSteps: 10)
            try await deleteAllRecords(ofType: RecordType.learningObjective, cohortRecordID: sheetRecordID)
            resetProgress = ResetProgress(message: "Deleting category labels...", step: 8, totalSteps: 10)
            try await deleteAllRecords(ofType: RecordType.categoryLabel, cohortRecordID: sheetRecordID)
            resetProgress = ResetProgress(message: "Deleting expertise checks...", step: 9, totalSteps: 10)
            try await deleteAllRecords(ofType: RecordType.domain, cohortRecordID: sheetRecordID)
            resetProgress = ResetProgress(message: "Deleting sheet record...", step: 10, totalSteps: 10)
            try await service.delete(recordID: sheetRecordID)

            try? CloudKitStoreSnapshotCache.remove(cohortId: sheet.cohortId)
            UserDefaults.standard.removeObject(forKey: lastSyncDateDefaultsKey(for: sheet.cohortId))

            if UserDefaults.standard.string(forKey: activeCohortDefaultsKey) == sheet.cohortId {
                UserDefaults.standard.set(defaultCohortId, forKey: activeCohortDefaultsKey)
            }

            sheets.removeAll { $0.id == sheet.id }
            await loadSheets()
        } catch {
            lastErrorMessage = "Failed to delete sheet: \(error.localizedDescription)"
        }
    }

    private func switchSheetInternal(to sheet: CohortSheet) async {
        syncCoordinator?.stop()
        syncCoordinator = nil

        activeSheet = sheet
        UserDefaults.standard.set(sheet.cohortId, forKey: activeCohortDefaultsKey)
        cohortRecordID = nil
        clearInMemoryDataForSheetSwitch()
        _ = restoreSnapshotIfAvailable()
        await reloadAllData(force: true)
    }

    private func beginSheetMutation() -> Bool {
        guard isSheetMutationInProgress == false else { return false }
        isSheetMutationInProgress = true
        return true
    }

    private func endSheetMutation() {
        isSheetMutationInProgress = false
    }

    private func ensureCohortRecord() async throws -> CKRecord {
        try await ensureCohortRecord(for: activeCohortId)
    }

    private func ensureCohortRecord(for cohortId: String, name: String? = nil) async throws -> CKRecord {
        if let cohortRecordID {
            let record = try await service.fetchRecord(with: cohortRecordID)
            if (record[Field.cohortId] as? String) == cohortId {
                return record
            }
        }

        let predicate = NSPredicate(format: "cohortId == %@", cohortId)
        let records = try await service.queryRecords(ofType: RecordType.cohort, predicate: predicate)

        if let existing = records.first {
            return existing
        }

        let recordID = CKRecord.ID(recordName: cohortId)
        let record = CKRecord(recordType: RecordType.cohort, recordID: recordID)
        record[Field.cohortId] = cohortId
        record[Field.name] = name ?? "Main Cohort"
        applyAuditFields(to: record, createdAt: Date())
        return try await service.save(record: record)
    }

    private func saveGroupRecord(_ group: CohortGroup) async throws {
        guard let cohortRecordID else { return }
        let recordID = recordID(for: group, lookup: groupRecordNameByID)
        markRecordRecentlyWritten(recordType: RecordType.cohortGroup, recordName: recordID.recordName)
        let record = CKRecord(recordType: RecordType.cohortGroup, recordID: recordID)
        record[Field.cohortRef] = CKRecord.Reference(recordID: cohortRecordID, action: .none)
        record[Field.name] = group.name
        record[Field.colorHex] = group.colorHex
        applyAuditFields(to: record, createdAt: Date())
        let saved = try await service.save(record: record)
        groupRecordNameByID[group.id] = saved.recordID.recordName
        pendingGroupCreateIDs.remove(group.id)
        unconfirmedGroupRecordNames.insert(saved.recordID.recordName)
        markRecordRecentlyWritten(recordType: RecordType.cohortGroup, recordName: saved.recordID.recordName)
        syncCoordinator?.noteLocalWrite()
        rebuildGroupMembershipCaches()
    }

    private func saveDomainRecord(_ domain: Domain) async throws {
        guard let cohortRecordID else { return }
        let recordID = recordID(for: domain, lookup: domainRecordNameByID)
        markRecordRecentlyWritten(recordType: RecordType.domain, recordName: recordID.recordName)
        let record = CKRecord(recordType: RecordType.domain, recordID: recordID)
        record[Field.cohortRef] = CKRecord.Reference(recordID: cohortRecordID, action: .none)
        record[Field.name] = domain.name
        record[Field.colorHex] = domain.colorHex
        record[Field.overallMode] = domain.overallMode.rawValue
        applyAuditFields(to: record, createdAt: Date())
        let saved = try await service.save(record: record)
        domainRecordNameByID[domain.id] = saved.recordID.recordName
        pendingDomainCreateIDs.remove(domain.id)
        unconfirmedDomainRecordNames.insert(saved.recordID.recordName)
        markRecordRecentlyWritten(recordType: RecordType.domain, recordName: saved.recordID.recordName)
        syncCoordinator?.noteLocalWrite()
    }

    private func saveStudentRecord(_ student: Student) async throws {
        guard let cohortRecordID else { return }
        let recordID = recordID(for: student, lookup: studentRecordNameByID)
        markRecordRecentlyWritten(recordType: RecordType.student, recordName: recordID.recordName)
        let record = CKRecord(recordType: RecordType.student, recordID: recordID)
        applyStudentFields(student, to: record, cohortRecordID: cohortRecordID)
        let saved = try await service.save(record: record)
        studentRecordNameByID[student.id] = saved.recordID.recordName
        markRecordRecentlyWritten(recordType: RecordType.student, recordName: saved.recordID.recordName)
        syncCoordinator?.noteLocalWrite()
    }

    private func saveLearningObjectiveRecord(
        _ objective: LearningObjective,
        allObjectives: [LearningObjective]? = nil
    ) async throws {
        guard let cohortRecordID else { return }
        let learningObjectiveRecordID = recordID(for: objective, lookup: learningObjectiveRecordNameByID)
        markRecordRecentlyWritten(
            recordType: RecordType.learningObjective,
            recordName: learningObjectiveRecordID.recordName
        )
        let record = CKRecord(recordType: RecordType.learningObjective, recordID: learningObjectiveRecordID)
        record[Field.cohortRef] = CKRecord.Reference(recordID: cohortRecordID, action: .none)
        record[Field.code] = objective.code
        record[Field.title] = objective.title
        record[Field.objectiveDescription] = objective.objectiveDescription
        record[Field.isQuantitative] = objective.isQuantitative ? 1 : 0
        record[Field.parentCode] = objective.parentCode
        record[Field.sortOrder] = objective.sortOrder
        record[Field.isArchived] = objective.isArchived ? 1 : 0

        if let parent = resolvedParentObjective(for: objective, in: allObjectives ?? allLearningObjectives) {
            let parentRecordID = recordID(for: parent, lookup: learningObjectiveRecordNameByID)
            record[Field.parentRef] = CKRecord.Reference(recordID: parentRecordID, action: .none)
            objective.parentId = parent.id
            if objective.parentCode == nil {
                objective.parentCode = parent.code
            }
        } else {
            record[Field.parentRef] = nil
        }

        applyAuditFields(to: record, createdAt: Date())
        let saved = try await service.save(record: record)
        learningObjectiveRecordNameByID[objective.id] = saved.recordID.recordName
        pendingLearningObjectiveCreateIDs.remove(objective.id)
        unconfirmedLearningObjectiveRecordNames.insert(saved.recordID.recordName)
        markRecordRecentlyWritten(recordType: RecordType.learningObjective, recordName: saved.recordID.recordName)
        syncCoordinator?.noteLocalWrite()
    }

    private func applyStudentFields(_ student: Student, to record: CKRecord, cohortRecordID: CKRecord.ID) {
        record[Field.cohortRef] = CKRecord.Reference(recordID: cohortRecordID, action: .none)
        record[Field.name] = student.name
        record[Field.session] = student.session.rawValue
        record[Field.createdAt] = student.createdAt

        if let group = student.group {
            let groupRecordID = recordID(for: group, lookup: groupRecordNameByID)
            record[Field.group] = CKRecord.Reference(recordID: groupRecordID, action: .none)
        } else {
            record[Field.group] = nil
        }

        if let domain = student.domain {
            let domainRecordID = recordID(for: domain, lookup: domainRecordNameByID)
            record[Field.domain] = CKRecord.Reference(recordID: domainRecordID, action: .none)
        } else {
            record[Field.domain] = nil
        }

        applyAuditFields(to: record, createdAt: student.createdAt)
    }

    private func replaceCustomProperties(for student: Student, rows: [CustomPropertyRow]) async throws {
        try await deleteCustomProperties(for: student)

        student.customProperties.removeAll()

        for (index, row) in rows.enumerated() {
            let property = StudentCustomProperty(
                key: row.key.trimmingCharacters(in: .whitespacesAndNewlines),
                value: row.value.trimmingCharacters(in: .whitespacesAndNewlines),
                sortOrder: index
            )
            property.student = student
            student.customProperties.append(property)

            try await saveCustomProperty(property, student: student)
        }

        customPropertiesLoadedStudentIDs.insert(student.id)
    }

    private func saveCustomProperty(_ property: StudentCustomProperty, student: Student) async throws {
        guard let cohortRecordID else { return }
        let studentRecordID = recordID(for: student, lookup: studentRecordNameByID)

        let recordID = recordID(for: property, lookup: customPropertyRecordNameByID)
        markRecordRecentlyWritten(recordType: RecordType.studentCustomProperty, recordName: recordID.recordName)
        let record = CKRecord(recordType: RecordType.studentCustomProperty, recordID: recordID)
        record[Field.cohortRef] = CKRecord.Reference(recordID: cohortRecordID, action: .none)
        record[Field.student] = CKRecord.Reference(recordID: studentRecordID, action: .none)
        record[Field.key] = property.key
        record[Field.value] = property.value
        record[Field.sortOrder] = property.sortOrder
        applyAuditFields(to: record, createdAt: Date())

        let saved = try await service.save(record: record)
        customPropertyRecordNameByID[property.id] = saved.recordID.recordName
        markRecordRecentlyWritten(recordType: RecordType.studentCustomProperty, recordName: saved.recordID.recordName)
        syncCoordinator?.noteLocalWrite()
    }

    private func deleteCustomProperties(for student: Student) async throws {
        guard let cohortRecordID else { return }
        let studentRecordID = recordID(for: student, lookup: studentRecordNameByID)

        let cohortRef = CKRecord.Reference(recordID: cohortRecordID, action: .none)
        let studentRef = CKRecord.Reference(recordID: studentRecordID, action: .none)
        let predicate = NSPredicate(format: "cohortRef == %@ AND student == %@", cohortRef, studentRef)
        let records = try await service.queryRecords(ofType: RecordType.studentCustomProperty, predicate: predicate)
        for record in records {
            try await service.delete(recordID: record.recordID)
        }
    }

    private func deleteProgress(for student: Student) async throws {
        guard let cohortRecordID else { return }
        let studentRecordID = recordID(for: student, lookup: studentRecordNameByID)

        let cohortRef = CKRecord.Reference(recordID: cohortRecordID, action: .none)
        let records = try await queryProgressRecords(cohortRef: cohortRef, studentRecordID: studentRecordID)
        for record in records {
            try await service.delete(recordID: record.recordID)
        }
    }

    private func deleteExpertiseCheckScores(for domain: Domain) async throws {
        guard let cohortRecordID else { return }
        let cohortRef = CKRecord.Reference(recordID: cohortRecordID, action: .none)
        let domainRecordID = recordID(for: domain, lookup: domainRecordNameByID)
        let domainRef = CKRecord.Reference(recordID: domainRecordID, action: .none)
        let predicate = NSPredicate(format: "cohortRef == %@ AND expertiseCheckRef == %@", cohortRef, domainRef)
        let records = try await service.queryRecords(ofType: RecordType.expertiseCheckObjectiveScore, predicate: predicate)
        for record in records {
            try await service.delete(recordID: record.recordID)
            if let existingID = existingID(forRecordName: record.recordID.recordName, lookup: expertiseCheckScoreRecordNameByID) {
                expertiseCheckScoreRecordNameByID.removeValue(forKey: existingID)
            }
        }
        expertiseCheckObjectiveScores.removeAll { $0.expertiseCheckId == domain.id }
        rebuildExpertiseCheckScoreCaches()
    }

    private func deleteAllRecords(ofType recordType: String, cohortRecordID: CKRecord.ID) async throws {
        let cohortRef = CKRecord.Reference(recordID: cohortRecordID, action: .none)
        let predicate = NSPredicate(format: "cohortRef == %@", cohortRef)
        let recordIDs = try await service.queryRecordIDs(ofType: recordType, predicate: predicate)
        try await service.delete(recordIDs: recordIDs)
    }

    private func mapGroup(from record: CKRecord) -> CohortGroup {
        let name = record[Field.name] as? String ?? "Untitled"
        let colorHex = record[Field.colorHex] as? String
        let group = CohortGroup(name: name, colorHex: colorHex)
        let uuid = resolvedStableID(forRecordName: record.recordID.recordName, lookup: groupRecordNameByID)
        group.id = uuid
        groupRecordNameByID[uuid] = record.recordID.recordName

        return group
    }

    private func mapDomain(from record: CKRecord) -> Domain {
        let name = record[Field.name] as? String ?? "Untitled"
        let colorHex = record[Field.colorHex] as? String
        let overallModeRaw = (record[Field.overallMode] as? String) ?? ExpertiseCheckOverallMode.computed.rawValue
        let overallMode = ExpertiseCheckOverallMode(rawValue: overallModeRaw) ?? .computed
        let domain = Domain(name: name, colorHex: colorHex, overallMode: overallMode)
        let uuid = resolvedStableID(forRecordName: record.recordID.recordName, lookup: domainRecordNameByID)
        domain.id = uuid
        domainRecordNameByID[uuid] = record.recordID.recordName

        return domain
    }

    private func mapLearningObjectives(from records: [CKRecord]) -> [LearningObjective] {
        guard records.isEmpty == false else { return [] }

        var objectiveByRecordName: [String: LearningObjective] = [:]
        var objectiveByCode: [String: LearningObjective] = [:]

        for record in records {
            let code = record[Field.code] as? String ?? ""
            let title = record[Field.title] as? String ?? code
            let description = record[Field.objectiveDescription] as? String ?? ""
            let sortOrder = (record[Field.sortOrder] as? Int)
                ?? (record[Field.sortOrder] as? NSNumber)?.intValue
                ?? 0
            let isQuantitativeRaw = (record[Field.isQuantitative] as? Int)
                ?? (record[Field.isQuantitative] as? NSNumber)?.intValue
                ?? 0
            let isArchivedRaw = (record[Field.isArchived] as? Int)
                ?? (record[Field.isArchived] as? NSNumber)?.intValue
                ?? 0
            let parentCode = record[Field.parentCode] as? String

            let objective = LearningObjective(
                code: code,
                title: title,
                description: description,
                isQuantitative: isQuantitativeRaw != 0,
                parentCode: parentCode,
                sortOrder: sortOrder,
                isArchived: isArchivedRaw != 0
            )

            let uuid = resolvedStableID(forRecordName: record.recordID.recordName, lookup: learningObjectiveRecordNameByID)
            objective.id = uuid
            learningObjectiveRecordNameByID[uuid] = record.recordID.recordName

            objectiveByRecordName[record.recordID.recordName] = objective
            objectiveByCode[objective.code] = objective
        }

        for record in records {
            guard let objective = objectiveByRecordName[record.recordID.recordName] else { continue }
            if let parentRef = record[Field.parentRef] as? CKRecord.Reference {
                if let parent = objectiveByRecordName[parentRef.recordID.recordName] {
                    objective.parentId = parent.id
                    if objective.parentCode == nil {
                        objective.parentCode = parent.code
                    }
                } else if let parentUUID = UUID(uuidString: parentRef.recordID.recordName) {
                    objective.parentId = parentUUID
                }
            } else if let parentCode = objective.parentCode, let parent = objectiveByCode[parentCode] {
                objective.parentId = parent.id
            }
        }

        return objectiveByRecordName.values.sorted {
            if $0.sortOrder != $1.sortOrder {
                return $0.sortOrder < $1.sortOrder
            }
            return $0.code < $1.code
        }
    }

    private func mapStudent(
        from record: CKRecord,
        groupMap: [String: CohortGroup],
        domainMap: [String: Domain]
    ) -> Student {
        let name = record[Field.name] as? String ?? "Unnamed"
        let sessionRaw = record[Field.session] as? String ?? Session.morning.rawValue
        let session = Session(rawValue: sessionRaw) ?? .morning

        let group = (record[Field.group] as? CKRecord.Reference).flatMap { groupMap[$0.recordID.recordName] }
        let domain = (record[Field.domain] as? CKRecord.Reference).flatMap { domainMap[$0.recordID.recordName] }

        let student = Student(name: name, group: group, session: session, domain: domain)
        if let createdAt = record[Field.createdAt] as? Date {
            student.createdAt = createdAt
        }

        let uuid = resolvedStableID(forRecordName: record.recordID.recordName, lookup: studentRecordNameByID)
        student.id = uuid
        studentRecordNameByID[uuid] = record.recordID.recordName

        return student
    }

    private func mapCategoryLabel(from record: CKRecord) -> CategoryLabel {
        let code = record[Field.code] as? String ?? (record[Field.key] as? String ?? record.recordID.recordName)
        let title = record[Field.title] as? String ?? code
        categoryLabelRecordNameByCode[code] = record.recordID.recordName
        return CategoryLabel(code: code, title: title)
    }

    private func mapMembership(
        from record: CKRecord,
        studentMap: [String: Student],
        groupMap: [String: CohortGroup]
    ) -> StudentGroupMembership? {
        guard let studentRef = studentReference(from: record) else { return nil }
        guard let groupRef = record[Field.groupRef] as? CKRecord.Reference else { return nil }
        guard let student = studentMap[studentRef.recordID.recordName] else { return nil }
        guard let group = groupMap[groupRef.recordID.recordName] else { return nil }

        let createdAt = (record[Field.createdAt] as? Date) ?? Date()
        let updatedAt = (record[Field.updatedAt] as? Date) ?? createdAt
        let membership = StudentGroupMembership(student: student, group: group, createdAt: createdAt, updatedAt: updatedAt)
        let uuid = resolvedStableID(forRecordName: record.recordID.recordName, lookup: membershipRecordNameByID)
        membership.id = uuid
        membershipRecordNameByID[uuid] = record.recordID.recordName

        return membership
    }

    private func mapProgress(from record: CKRecord, student: Student) -> ObjectiveProgress {
        let objectiveRef = record[Field.objectiveRef] as? CKRecord.Reference
        let objectiveId: UUID? = objectiveRef.flatMap { reference in
            self.objectiveID(forRecordName: reference.recordID.recordName)
        }
        var objectiveCode = record[Field.objectiveCode] as? String ?? ""
        if objectiveCode.isEmpty, let objectiveId, let mappedObjective = objectiveByID(objectiveId) {
            objectiveCode = mappedObjective.code
        }

        let canonicalValue = (record[Field.value] as? Int)
            ?? (record[Field.value] as? NSNumber)?.intValue
            ?? (record[Field.completionPercentage] as? Int)
            ?? (record[Field.completionPercentage] as? NSNumber)?.intValue
            ?? 0
        let notes = record[Field.notes] as? String ?? ""
        let progress = ObjectiveProgress(
            objectiveCode: objectiveCode,
            completionPercentage: canonicalValue,
            notes: notes,
            objectiveId: objectiveId,
            value: canonicalValue
        )
        progress.student = student
        if let lastUpdated = record[Field.lastUpdated] as? Date {
            progress.lastUpdated = lastUpdated
        }
        if let statusRaw = record[Field.status] as? String, let status = ProgressStatus(rawValue: statusRaw) {
            progress.status = status
        }

        let uuid = resolvedStableID(forRecordName: record.recordID.recordName, lookup: progressRecordNameByID)
        progress.id = uuid
        progressRecordNameByID[uuid] = record.recordID.recordName

        return progress
    }

    private func mapCustomProperty(from record: CKRecord, student: Student) -> StudentCustomProperty {
        let key = record[Field.key] as? String ?? ""
        let value = record[Field.value] as? String ?? ""
        let sortOrder = (record[Field.sortOrder] as? Int)
            ?? (record[Field.sortOrder] as? NSNumber)?.intValue
            ?? 0
        let property = StudentCustomProperty(key: key, value: value, sortOrder: sortOrder)
        property.student = student

        let uuid = resolvedStableID(forRecordName: record.recordID.recordName, lookup: customPropertyRecordNameByID)
        property.id = uuid
        customPropertyRecordNameByID[uuid] = record.recordID.recordName

        return property
    }

    private func mapExpertiseCheckObjectiveScore(from record: CKRecord) -> ExpertiseCheckObjectiveScore? {
        guard let domainRef = record[Field.expertiseCheckRef] as? CKRecord.Reference else { return nil }
        let domainID = resolvedStableID(forRecordName: domainRef.recordID.recordName, lookup: domainRecordNameByID)
        let objectiveRef = record[Field.objectiveRef] as? CKRecord.Reference
        var objectiveId = objectiveRef.flatMap { objectiveID(forRecordName: $0.recordID.recordName) }
        var objectiveCode = (record[Field.objectiveCode] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if objectiveCode.isEmpty, let objectiveId, let objective = objectiveByID(objectiveId) {
            objectiveCode = objective.code
        }
        if objectiveId == nil, objectiveCode.isEmpty == false {
            objectiveId = objectiveByCode(objectiveCode)?.id
        }
        guard objectiveId != nil || objectiveCode.isEmpty == false else { return nil }

        let canonicalValue = (record[Field.value] as? Int)
            ?? (record[Field.value] as? NSNumber)?.intValue
            ?? 0
        let clampedValue = max(0, min(100, canonicalValue))
        let statusRaw = (record[Field.status] as? String) ?? ObjectiveProgress.calculateStatus(from: clampedValue).rawValue
        let createdAt = (record[Field.createdAt] as? Date) ?? Date()
        let updatedAt = (record[Field.updatedAt] as? Date) ?? createdAt
        let displayName = record[Field.lastEditedByDisplayName] as? String

        let score = ExpertiseCheckObjectiveScore(
            expertiseCheckId: domainID,
            objectiveId: objectiveId,
            objectiveCode: objectiveCode,
            value: clampedValue,
            status: ProgressStatus(rawValue: statusRaw),
            createdAt: createdAt,
            updatedAt: updatedAt,
            lastEditedByDisplayName: displayName
        )
        let uuid = resolvedStableID(forRecordName: record.recordID.recordName, lookup: expertiseCheckScoreRecordNameByID)
        score.id = uuid
        expertiseCheckScoreRecordNameByID[uuid] = record.recordID.recordName
        return score
    }

    private func applyExpertiseCheckScores(_ incoming: [ExpertiseCheckObjectiveScore], cleanupRemoteDuplicates: Bool = true) {
        guard incoming.isEmpty == false else {
            expertiseCheckObjectiveScores.removeAll()
            rebuildExpertiseCheckScoreCaches()
            return
        }

        var bestByKey: [String: ExpertiseCheckObjectiveScore] = [:]
        var staleRecordNames: [String] = []

        for score in incoming {
            guard let domainID = score.expertiseCheckId else { continue }
            let key = expertiseCheckScoreKey(
                domainID: domainID,
                objectiveID: score.objectiveId,
                objectiveCode: score.objectiveCode
            )
            if let existing = bestByKey[key] {
                if shouldPreferExpertiseCheckScore(score, over: existing) {
                    staleRecordNames.append(recordName(for: existing))
                    bestByKey[key] = score
                } else {
                    staleRecordNames.append(recordName(for: score))
                }
            } else {
                bestByKey[key] = score
            }
        }

        expertiseCheckObjectiveScores = Array(bestByKey.values)
        rebuildExpertiseCheckScoreCaches()

        if cleanupRemoteDuplicates && staleRecordNames.isEmpty == false {
            cleanupDuplicateExpertiseCheckScoreRecords(recordNames: staleRecordNames)
        }
    }

    private func rebuildExpertiseCheckScoreCaches() {
        var byDomainObjectiveID: [UUID: [UUID: ExpertiseCheckObjectiveScore]] = [:]
        var byDomainObjectiveCode: [UUID: [String: ExpertiseCheckObjectiveScore]] = [:]

        for score in expertiseCheckObjectiveScores {
            guard let domainID = score.expertiseCheckId else { continue }
            if let objectiveID = score.objectiveId {
                byDomainObjectiveID[domainID, default: [:]][objectiveID] = score
            }
            let codeKey = normalizedObjectiveCodeKey(score.objectiveCode)
            if codeKey.isEmpty == false {
                byDomainObjectiveCode[domainID, default: [:]][codeKey] = score
            }
        }

        expertiseCheckScoreByDomainObjectiveID = byDomainObjectiveID
        expertiseCheckScoreByDomainObjectiveCode = byDomainObjectiveCode

        if hasLoaded {
            scheduleSnapshotPersistence()
        }
    }

    private func expertiseCheckScoreKey(domainID: UUID, objectiveID: UUID?, objectiveCode: String) -> String {
        if let objectiveID {
            return "\(domainID.uuidString)|\(objectiveID.uuidString)"
        }
        return "\(domainID.uuidString)|code:\(normalizedObjectiveCodeKey(objectiveCode))"
    }

    private func shouldPreferExpertiseCheckScore(
        _ candidate: ExpertiseCheckObjectiveScore,
        over existing: ExpertiseCheckObjectiveScore
    ) -> Bool {
        if candidate.updatedAt != existing.updatedAt {
            return candidate.updatedAt > existing.updatedAt
        }
        if candidate.createdAt != existing.createdAt {
            return candidate.createdAt > existing.createdAt
        }
        return candidate.id.uuidString < existing.id.uuidString
    }

    private func recordName(for score: ExpertiseCheckObjectiveScore) -> String {
        expertiseCheckScoreRecordNameByID[score.id] ?? score.id.uuidString
    }

    private func cleanupDuplicateExpertiseCheckScoreRecords(recordNames: [String]) {
        guard recordNames.isEmpty == false else { return }
        Task { [weak self] in
            guard let self else { return }
            guard await self.requireWriteAccess() else { return }
            for recordName in Set(recordNames) {
                let recordID = CKRecord.ID(recordName: recordName)
                do {
                    try await self.service.delete(recordID: recordID)
                    self.unmarkRecordRecentlyWritten(recordType: RecordType.expertiseCheckObjectiveScore, recordName: recordName)
                } catch {
                    self.syncLogger.error("Failed duplicate ExpertiseCheckObjectiveScore cleanup for \(recordName, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    private func setLearningObjectives(_ objectives: [LearningObjective]) {
        allLearningObjectives = deduplicateLearningObjectivesByCode(objectives).sorted {
            if $0.sortOrder != $1.sortOrder {
                return $0.sortOrder < $1.sortOrder
            }
            return $0.code < $1.code
        }
        let parentCodeByID = Dictionary(uniqueKeysWithValues: allLearningObjectives.map { ($0.id, $0.code) })
        for objective in allLearningObjectives where objective.parentCode == nil {
            if let parentId = objective.parentId {
                objective.parentCode = parentCodeByID[parentId]
            }
        }
        learningObjectives = allLearningObjectives.filter { $0.isArchived == false }
        rebuildObjectiveCaches()
        if hasLoaded {
            rebuildProgressCaches(debounce: true)
        } else {
            rebuildProgressCaches()
        }
    }

    private func defaultLearningObjectivesWithResolvedParents() -> [LearningObjective] {
        let defaults = LearningObjectiveCatalog.defaultObjectives()
        let objectiveByCode = objectiveDictionaryByCode(defaults)
        for objective in defaults {
            if let parentCode = objective.parentCode, let parent = objectiveByCode[parentCode] {
                objective.parentId = parent.id
            }
        }
        return defaults
    }

    private func resolvedParentObjective(
        for objective: LearningObjective,
        in allObjectives: [LearningObjective]
    ) -> LearningObjective? {
        if let parentId = objective.parentId {
            return allObjectives.first { $0.id == parentId }
        }
        if let parentCode = objective.parentCode {
            let parentKey = normalizedObjectiveCodeKey(parentCode)
            return allObjectives.first { normalizedObjectiveCodeKey($0.code) == parentKey }
        }
        return nil
    }

    private func objectiveByCode(_ code: String) -> LearningObjective? {
        objectiveByCodeCache[normalizedObjectiveCodeKey(code)]
    }

    private func objectiveByID(_ id: UUID) -> LearningObjective? {
        allLearningObjectives.first { $0.id == id }
    }

    private func objectiveID(forRecordName recordName: String) -> UUID? {
        if let uuid = UUID(uuidString: recordName) {
            return uuid
        }
        return learningObjectiveRecordNameByID.first(where: { $0.value == recordName })?.key
    }

    private func progressPredicateForStudentRef(cohortRef: CKRecord.Reference, studentRecordID: CKRecord.ID) -> NSPredicate {
        let studentRef = CKRecord.Reference(recordID: studentRecordID, action: .none)
        return NSPredicate(
            format: "cohortRef == %@ AND studentRef == %@",
            cohortRef,
            studentRef
        )
    }

    private func progressPredicateForLegacyStudentField(cohortRef: CKRecord.Reference, studentRecordID: CKRecord.ID) -> NSPredicate {
        let studentRef = CKRecord.Reference(recordID: studentRecordID, action: .none)
        return NSPredicate(
            format: "cohortRef == %@ AND student == %@",
            cohortRef,
            studentRef
        )
    }

    private func queryProgressRecords(
        cohortRef: CKRecord.Reference,
        studentRecordID: CKRecord.ID
    ) async throws -> [CKRecord] {
        let primary = try await service.queryRecords(
            ofType: RecordType.objectiveProgress,
            predicate: progressPredicateForStudentRef(cohortRef: cohortRef, studentRecordID: studentRecordID)
        )
        let legacy = try await service.queryRecords(
            ofType: RecordType.objectiveProgress,
            predicate: progressPredicateForLegacyStudentField(cohortRef: cohortRef, studentRecordID: studentRecordID)
        )

        var byRecordName: [String: CKRecord] = [:]
        for record in primary {
            byRecordName[record.recordID.recordName] = record
        }
        for record in legacy {
            byRecordName[record.recordID.recordName] = record
        }
        return Array(byRecordName.values)
    }

    private func studentReference(from record: CKRecord) -> CKRecord.Reference? {
        (record[Field.studentRef] as? CKRecord.Reference)
        ?? (record[Field.student] as? CKRecord.Reference)
    }

    func rootCategoryObjectives() -> [LearningObjective] {
        rootCategoryObjectivesCache
    }

    func childObjectives(of objective: LearningObjective) -> [LearningObjective] {
        objectiveChildrenByParentID[objective.id] ?? []
    }

    func objective(forCode code: String) -> LearningObjective? {
        objectiveByCode(code)
    }

    func progressValue(student: Student, objective: LearningObjective) -> Int {
        if let aggregate = objectiveAggregateByStudentID[student.id]?[objective.id] {
            return aggregate
        }
        if let value = progressValuesByStudentObjectiveID[student.id]?[objective.id] {
            return value
        }
        return progressValuesByStudentObjectiveCode[student.id]?[objective.code] ?? 0
    }

    func objectivePercentage(student: Student, objective: LearningObjective) -> Int {
        if let cached = objectiveAggregateByStudentID[student.id]?[objective.id] {
            return cached
        }
        var memo: [UUID: Int] = [:]
        return objectivePercentage(studentID: student.id, objective: objective, memo: &memo)
    }

    func studentOverallProgress(student: Student) -> Int {
        if let cached = studentOverallProgressByID[student.id] {
            return cached
        }
        guard rootCategoryObjectivesCache.isEmpty == false else { return 0 }
        var memo: [UUID: Int] = [:]
        let total = rootCategoryObjectivesCache.reduce(0) { partial, category in
            partial + objectivePercentage(studentID: student.id, objective: category, memo: &memo)
        }
        return total / rootCategoryObjectivesCache.count
    }

    func cohortObjectiveAverage(objective: LearningObjective, students: [Student]) -> Int {
        guard students.isEmpty == false else { return 0 }
        var total = 0
        for student in students {
            if let cached = objectiveAggregateByStudentID[student.id]?[objective.id] {
                total += cached
            } else {
                var memo: [UUID: Int] = [:]
                total += objectivePercentage(studentID: student.id, objective: objective, memo: &memo)
            }
        }
        return total / students.count
    }

    func cohortOverallProgress(students: [Student]) -> Int {
        guard students.isEmpty == false else { return 0 }
        if students.count == self.students.count {
            let localIDs = Set(self.students.map(\.id))
            let comparedIDs = Set(students.map(\.id))
            if localIDs == comparedIDs {
                return cohortOverallProgressCache
            }
        }
        var total = 0
        for student in students {
            if let cached = studentOverallProgressByID[student.id] {
                total += cached
            } else {
                total += studentOverallProgress(student: student)
            }
        }
        return total / students.count
    }

    func groupOverallProgress(group: CohortGroup, students: [Student]) -> Int {
        let groupStudents = students.filter { student in
            if let explicitGroups = groupsByStudentIDCache[student.id], explicitGroups.isEmpty == false {
                return explicitGroups.contains(where: { $0.id == group.id })
            }
            return student.group?.id == group.id
        }
        return cohortOverallProgress(students: groupStudents)
    }

    func expertiseCheckReviewLeafValue(domain: Domain, objective: LearningObjective) -> Int {
        if let score = expertiseCheckScoreByDomainObjectiveID[domain.id]?[objective.id] {
            return score.value
        }
        return expertiseCheckScoreByDomainObjectiveCode[domain.id]?[normalizedObjectiveCodeKey(objective.code)]?.value ?? 0
    }

    func expertiseCheckReviewerObjectivePercentage(domain: Domain, objective: LearningObjective) -> Int {
        var memo: [UUID: Int] = [:]
        return expertiseCheckReviewerObjectivePercentage(
            domainID: domain.id,
            objective: objective,
            memo: &memo
        )
    }

    func expertiseCheckReviewerOverallProgress(domain: Domain) -> Int {
        guard rootCategoryObjectivesCache.isEmpty == false else { return 0 }
        var memo: [UUID: Int] = [:]
        let total = rootCategoryObjectivesCache.reduce(0) { partial, objective in
            partial + expertiseCheckReviewerObjectivePercentage(
                domainID: domain.id,
                objective: objective,
                memo: &memo
            )
        }
        return total / rootCategoryObjectivesCache.count
    }

    func setExpertiseCheckMode(_ domain: Domain, mode: ExpertiseCheckOverallMode) async {
        lastErrorMessage = nil
        guard await requireWriteAccess() else { return }
        guard domain.overallMode != mode else { return }
        guard pendingExpertiseCheckModeUpdateIDs.contains(domain.id) == false else { return }

        let previousMode = domain.overallMode
        objectWillChange.send()
        pendingExpertiseCheckModeUpdateIDs.insert(domain.id)
        defer {
            objectWillChange.send()
            pendingExpertiseCheckModeUpdateIDs.remove(domain.id)
        }

        objectWillChange.send()
        domain.overallMode = mode
        if hasLoaded {
            scheduleSnapshotPersistence()
        }

        let maxAttempts = 3
        for attempt in 1...maxAttempts {
            do {
                try await saveDomainRecord(domain)
                return
            } catch {
                let isConflict = isCloudKitOplockConflict(error)
                if isConflict, attempt < maxAttempts {
                    let delay = retryDelayNanoseconds(for: error, attempt: attempt)
                    syncLogger.warning(
                        "Retrying expertise check mode save for \(domain.id.uuidString, privacy: .public) after lock conflict (attempt \(attempt, privacy: .public)/\(maxAttempts, privacy: .public))"
                    )
                    try? await Task.sleep(nanoseconds: delay)
                    continue
                }

                objectWillChange.send()
                domain.overallMode = previousMode
                if hasLoaded {
                    scheduleSnapshotPersistence()
                }
                lastErrorMessage = "Failed to update expertise check mode: \(service.describe(error))"
                return
            }
        }
    }

    func setExpertiseCheckReviewScore(domain: Domain, objective: LearningObjective, value: Int) async {
        lastErrorMessage = nil
        guard await requireWriteAccess() else { return }
        guard let cohortRecordID else { return }

        let canonicalValue = max(0, min(100, value))
        if canonicalValue == 0 {
            await deleteExpertiseCheckObjectiveScore(domain: domain, objective: objective)
            return
        }

        let existingByID = expertiseCheckScoreByDomainObjectiveID[domain.id]?[objective.id]
        let existingByCode = expertiseCheckScoreByDomainObjectiveCode[domain.id]?[normalizedObjectiveCodeKey(objective.code)]
        let existing = existingByID ?? existingByCode
        let previousSnapshot = existing.map { ($0.value, $0.statusRawValue, $0.updatedAt, $0.objectiveId, $0.objectiveCode) }

        let score: ExpertiseCheckObjectiveScore
        let created: Bool
        if let existing {
            score = existing
            created = false
        } else {
            score = ExpertiseCheckObjectiveScore(
                expertiseCheckId: domain.id,
                objectiveId: objective.id,
                objectiveCode: objective.code,
                value: canonicalValue,
                status: ObjectiveProgress.calculateStatus(from: canonicalValue),
                createdAt: Date(),
                updatedAt: Date(),
                lastEditedByDisplayName: editorDisplayName()
            )
            expertiseCheckObjectiveScores.append(score)
            created = true
        }

        objectWillChange.send()
        score.expertiseCheckId = domain.id
        score.objectiveId = objective.id
        score.objectiveCode = objective.code
        score.value = canonicalValue
        score.statusRawValue = ObjectiveProgress.calculateStatus(from: canonicalValue).rawValue
        score.updatedAt = Date()
        score.lastEditedByDisplayName = editorDisplayName()
        applyExpertiseCheckScores(expertiseCheckObjectiveScores)

        do {
            let scoreRecordID = recordID(for: score, lookup: expertiseCheckScoreRecordNameByID)
            markRecordRecentlyWritten(recordType: RecordType.expertiseCheckObjectiveScore, recordName: scoreRecordID.recordName)
            let record = CKRecord(recordType: RecordType.expertiseCheckObjectiveScore, recordID: scoreRecordID)
            let domainRecordID = recordID(for: domain, lookup: domainRecordNameByID)
            let objectiveRecordID = recordID(for: objective, lookup: learningObjectiveRecordNameByID)
            record[Field.cohortRef] = CKRecord.Reference(recordID: cohortRecordID, action: .none)
            record[Field.expertiseCheckRef] = CKRecord.Reference(recordID: domainRecordID, action: .none)
            record[Field.objectiveRef] = CKRecord.Reference(recordID: objectiveRecordID, action: .none)
            record[Field.objectiveCode] = objective.code
            record[Field.value] = canonicalValue
            record[Field.status] = score.statusRawValue
            applyAuditFields(to: record, createdAt: score.createdAt)

            let saved = try await service.save(record: record)
            expertiseCheckScoreRecordNameByID[score.id] = saved.recordID.recordName
            markRecordRecentlyWritten(recordType: RecordType.expertiseCheckObjectiveScore, recordName: saved.recordID.recordName)
            syncCoordinator?.noteLocalWrite()
        } catch {
            if created {
                expertiseCheckObjectiveScores.removeAll { $0.id == score.id }
            } else if let previousSnapshot {
                score.value = previousSnapshot.0
                score.statusRawValue = previousSnapshot.1
                score.updatedAt = previousSnapshot.2
                score.objectiveId = previousSnapshot.3
                score.objectiveCode = previousSnapshot.4
            }
            applyExpertiseCheckScores(expertiseCheckObjectiveScores)
            lastErrorMessage = "Failed to save expertise check review score: \(error.localizedDescription)"
        }
    }

    func deleteExpertiseCheckObjectiveScore(domain: Domain, objective: LearningObjective) async {
        lastErrorMessage = nil
        guard await requireWriteAccess() else { return }

        let existing = expertiseCheckScoreByDomainObjectiveID[domain.id]?[objective.id]
            ?? expertiseCheckScoreByDomainObjectiveCode[domain.id]?[normalizedObjectiveCodeKey(objective.code)]
        guard let existing else { return }

        let recordName = expertiseCheckScoreRecordNameByID[existing.id] ?? existing.id.uuidString
        objectWillChange.send()
        expertiseCheckObjectiveScores.removeAll { $0.id == existing.id }
        expertiseCheckScoreRecordNameByID.removeValue(forKey: existing.id)
        applyExpertiseCheckScores(expertiseCheckObjectiveScores)

        do {
            try await service.delete(recordID: CKRecord.ID(recordName: recordName))
            unmarkRecordRecentlyWritten(recordType: RecordType.expertiseCheckObjectiveScore, recordName: recordName)
            syncCoordinator?.noteLocalWrite()
        } catch {
            expertiseCheckObjectiveScores.append(existing)
            expertiseCheckScoreRecordNameByID[existing.id] = recordName
            applyExpertiseCheckScores(expertiseCheckObjectiveScores)
            lastErrorMessage = "Failed to delete expertise check review score: \(error.localizedDescription)"
        }
    }

    private func expertiseCheckReviewerObjectivePercentage(
        domainID: UUID,
        objective: LearningObjective,
        memo: inout [UUID: Int]
    ) -> Int {
        if let cached = memo[objective.id] {
            return cached
        }

        let children = objectiveChildrenByParentID[objective.id] ?? []
        if children.isEmpty {
            let value = expertiseCheckReviewLeafValueByDomainID(
                domainID: domainID,
                objectiveID: objective.id,
                objectiveCode: objective.code
            )
            memo[objective.id] = value
            return value
        }

        let total = children.reduce(0) { partial, child in
            partial + expertiseCheckReviewerObjectivePercentage(domainID: domainID, objective: child, memo: &memo)
        }
        let value = total / max(children.count, 1)
        memo[objective.id] = value
        return value
    }

    private func expertiseCheckReviewLeafValueByDomainID(
        domainID: UUID,
        objectiveID: UUID,
        objectiveCode: String
    ) -> Int {
        if let score = expertiseCheckScoreByDomainObjectiveID[domainID]?[objectiveID] {
            return score.value
        }
        return expertiseCheckScoreByDomainObjectiveCode[domainID]?[normalizedObjectiveCodeKey(objectiveCode)]?.value ?? 0
    }

    private func uniqueMemberships(_ input: [StudentGroupMembership]) -> [StudentGroupMembership] {
        var seen: Set<String> = []
        var output: [StudentGroupMembership] = []
        for membership in input {
            guard let studentID = membership.student?.id, let groupID = membership.group?.id else { continue }
            let key = "\(studentID.uuidString)|\(groupID.uuidString)"
            guard seen.insert(key).inserted else { continue }
            output.append(membership)
        }
        return output
    }

    private func explicitGroups(for student: Student) -> [CohortGroup] {
        if let cached = groupsByStudentIDCache[student.id] {
            return cached
        }
        return memberships.compactMap { membership -> CohortGroup? in
            guard membership.student?.id == student.id else { return nil }
            return membership.group
        }
    }

    private func refreshLegacyGroupConvenience() {
        for student in students {
            refreshLegacyGroupConvenience(for: student)
        }
    }

    private func refreshLegacyGroupConvenience(for student: Student) {
        let explicit = explicitGroups(for: student)
        if explicit.count == 1 {
            student.group = explicit[0]
        } else if explicit.count > 1 {
            student.group = nil
        }
    }

    private func setGroupsInternal(
        for student: Student,
        groups: [CohortGroup],
        updateLegacyGroupField: Bool
    ) async throws {
        let desiredGroups = Dictionary(grouping: groups, by: \.id).compactMap { $0.value.first }
        let currentGroups = explicitGroups(for: student)

        let currentIDs = Set(currentGroups.map(\.id))
        let desiredIDs = Set(desiredGroups.map(\.id))

        let groupsToRemove = currentGroups.filter { desiredIDs.contains($0.id) == false }
        for group in groupsToRemove {
            try await removeStudentFromGroupInternal(student, group: group, updateLegacyGroupField: false)
        }

        let groupsToAdd = desiredGroups.filter { currentIDs.contains($0.id) == false }
        for group in groupsToAdd {
            try await addStudentToGroupInternal(student, group: group, updateLegacyGroupField: false)
        }

        if updateLegacyGroupField {
            let explicit = explicitGroups(for: student)
            student.group = explicit.count == 1 ? explicit.first : nil
            try await saveStudentRecord(student)
        }
    }

    private func addStudentToGroupInternal(
        _ student: Student,
        group: CohortGroup,
        updateLegacyGroupField: Bool
    ) async throws {
        if memberships.contains(where: { $0.student?.id == student.id && $0.group?.id == group.id }) {
            return
        }

        let membership = StudentGroupMembership(student: student, group: group)
        memberships.append(membership)
        memberships = uniqueMemberships(memberships)
        rebuildGroupMembershipCaches()

        try await saveMembershipRecord(membership, student: student, group: group)

        if updateLegacyGroupField {
            refreshLegacyGroupConvenience(for: student)
            try await saveStudentRecord(student)
        }
    }

    private func removeStudentFromGroupInternal(
        _ student: Student,
        group: CohortGroup,
        updateLegacyGroupField: Bool
    ) async throws {
        let matched = memberships.filter { $0.student?.id == student.id && $0.group?.id == group.id }
        guard matched.isEmpty == false else { return }

        for membership in matched {
            try await deleteMembershipRecord(membership)
        }

        if updateLegacyGroupField {
            refreshLegacyGroupConvenience(for: student)
            try await saveStudentRecord(student)
        }
    }

    private func saveMembershipRecord(
        _ membership: StudentGroupMembership,
        student: Student,
        group: CohortGroup
    ) async throws {
        guard let cohortRecordID else { return }
        let studentRecordID = recordID(for: student, lookup: studentRecordNameByID)
        let groupRecordID = recordID(for: group, lookup: groupRecordNameByID)
        let recordID = recordID(for: membership, lookup: membershipRecordNameByID)
        markRecordRecentlyWritten(recordType: RecordType.studentGroupMembership, recordName: recordID.recordName)
        let record = CKRecord(recordType: RecordType.studentGroupMembership, recordID: recordID)
        record[Field.cohortRef] = CKRecord.Reference(recordID: cohortRecordID, action: .none)
        record[Field.studentRef] = CKRecord.Reference(recordID: studentRecordID, action: .none)
        record[Field.groupRef] = CKRecord.Reference(recordID: groupRecordID, action: .none)
        applyAuditFields(to: record, createdAt: membership.createdAt)

        let saved = try await service.save(record: record)
        membership.updatedAt = Date()
        membershipRecordNameByID[membership.id] = saved.recordID.recordName
        markRecordRecentlyWritten(recordType: RecordType.studentGroupMembership, recordName: saved.recordID.recordName)
        rebuildGroupMembershipCaches()
        syncCoordinator?.noteLocalWrite()
    }

    private func deleteMembershipRecord(_ membership: StudentGroupMembership) async throws {
        let recordID = recordID(for: membership, lookup: membershipRecordNameByID)
        try await service.delete(recordID: recordID)
        memberships.removeAll { $0.id == membership.id }
        membershipRecordNameByID.removeValue(forKey: membership.id)
        unmarkRecordRecentlyWritten(recordType: RecordType.studentGroupMembership, recordName: recordID.recordName)
        rebuildGroupMembershipCaches()
        syncCoordinator?.noteLocalWrite()
    }

    private func deleteMemberships(forStudentID studentID: UUID) async throws {
        let matched = memberships.filter { $0.student?.id == studentID }
        for membership in matched {
            try await deleteMembershipRecord(membership)
        }
    }

    private func deleteMemberships(forGroupID groupID: UUID) async throws {
        let matched = memberships.filter { $0.group?.id == groupID }
        for membership in matched {
            try await deleteMembershipRecord(membership)
        }
    }

    func ensureLearningObjectivesSeededIfNeeded() async {
        guard hasLoaded else { return }
        guard let cohortRecordID else { return }
        guard isSeedingLearningObjectives == false else { return }
        isSeedingLearningObjectives = true
        defer { isSeedingLearningObjectives = false }

        do {
            syncLogger.info("Checking if LearningObjective seeding is needed")
            let cohortRef = CKRecord.Reference(recordID: cohortRecordID, action: .none)
            let records = try await service.queryRecords(
                ofType: RecordType.learningObjective,
                predicate: NSPredicate(format: "cohortRef == %@", cohortRef)
            )
            guard records.isEmpty else { return }

            let defaults = defaultLearningObjectivesWithResolvedParents()
            if allLearningObjectives.isEmpty {
                setLearningObjectives(defaults)
            }

            syncLogger.info("Seeding default learning objectives because remote cohort has zero records")
            try await seedLearningObjectives(defaults)
            syncLogger.info("Default learning objective seed complete: \(defaults.count, privacy: .public) records")
        } catch {
            syncLogger.error("Learning objective seed failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func migrateLegacyGroupMembershipsIfNeeded() async {
        guard hasLoaded else { return }
        guard isMigratingLegacyMemberships == false else { return }
        isMigratingLegacyMemberships = true
        defer { isMigratingLegacyMemberships = false }

        var createdCount = 0
        do {
            syncLogger.info("Checking for legacy student.group memberships to migrate")
            for student in students {
                guard let legacyGroup = student.group else { continue }
                let hasExplicitMembership = memberships.contains {
                    $0.student?.id == student.id && $0.group?.id == legacyGroup.id
                }
                let hasAnyMembershipForStudent = memberships.contains { $0.student?.id == student.id }
                guard hasExplicitMembership == false, hasAnyMembershipForStudent == false else { continue }

                try await addStudentToGroupInternal(student, group: legacyGroup, updateLegacyGroupField: false)
                createdCount += 1
            }

            if createdCount > 0 {
                syncLogger.info("Migrated \(createdCount, privacy: .public) legacy student.group assignments into StudentGroupMembership records")
            } else {
                syncLogger.info("No legacy group membership migration required")
            }
        } catch {
            syncLogger.error("Legacy group membership migration failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func scheduleObjectiveRefMigrationIfNeeded(records: [CKRecord], studentRecordID: CKRecord.ID) {
        var recordsToMigrate: [CKRecord] = []
        for record in records {
            let hasObjectiveRef = (record[Field.objectiveRef] as? CKRecord.Reference) != nil
            guard hasObjectiveRef == false else { continue }
            let code = (record[Field.objectiveCode] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard code.isEmpty == false, objectiveByCode(code) != nil else { continue }
            guard objectiveRefMigrationRecordNames.insert(record.recordID.recordName).inserted else { continue }
            recordsToMigrate.append(record)
        }
        guard recordsToMigrate.isEmpty == false else { return }

        Task { [weak self] in
            guard let self else { return }
            await self.migrateObjectiveRefs(recordsToMigrate, studentRecordID: studentRecordID)
        }
    }

    private func migrateObjectiveRefs(_ records: [CKRecord], studentRecordID: CKRecord.ID) async {
        for record in records {
            defer { objectiveRefMigrationRecordNames.remove(record.recordID.recordName) }
            let code = (record[Field.objectiveCode] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard let objective = objectiveByCode(code) else { continue }

            record[Field.objectiveRef] = CKRecord.Reference(
                recordID: recordID(for: objective, lookup: learningObjectiveRecordNameByID),
                action: .none
            )
            if record[Field.studentRef] == nil {
                record[Field.studentRef] = CKRecord.Reference(recordID: studentRecordID, action: .none)
            }
            if record[Field.value] == nil {
                let fallback = (record[Field.completionPercentage] as? Int)
                    ?? (record[Field.completionPercentage] as? NSNumber)?.intValue
                    ?? 0
                record[Field.value] = fallback
            }

            applyAuditFields(to: record, createdAt: (record[Field.createdAt] as? Date) ?? Date())

            do {
                _ = try await service.save(record: record)
                syncLogger.info("Migrated ObjectiveProgress objectiveRef for record \(record.recordID.recordName, privacy: .public)")
            } catch {
                syncLogger.error("Failed objectiveRef migration for progress \(record.recordID.recordName, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func applyAuditFields(to record: CKRecord, createdAt: Date) {
        if record[Field.createdAt] == nil {
            record[Field.createdAt] = createdAt
        }
        record[Field.updatedAt] = Date()

        if let displayName = editorDisplayName() {
            record[Field.lastEditedByDisplayName] = displayName
        }
    }

    private func editorDisplayName() -> String? {
        let name = NSFullUserName()
        return name.isEmpty ? nil : name
    }

    private func friendlyMessage(for error: Error, detail: String) -> String {
        if let ckError = error as? CKError {
            switch ckError.code {
            case .permissionFailure:
                requiresICloudLogin = false
                return "CloudKit permission failure (container: \(service.containerIdentifier)). " +
                "Update CloudKit Dashboard → Security Roles → Public Database → World to allow Read/Write for your record types, then Deploy Schema Changes. " +
                detail
            case .notAuthenticated:
                requiresICloudLogin = true
                return "Not authenticated with iCloud. Sign in to iCloud on this Mac, then relaunch the app. " +
                detail
            default:
                break
            }
        }
        return "Failed to load CloudKit data (container: \(service.containerIdentifier)). \(detail)"
    }

    private func requireWriteAccess() async -> Bool {
        do {
            let status = try await service.accountStatus()
            if status == .available {
                requiresICloudLogin = false
                return true
            }
            requiresICloudLogin = true
            lastErrorMessage = "Writes require iCloud sign-in. Please sign in to iCloud on this Mac and relaunch the app."
            return false
        } catch {
            lastErrorMessage = "Unable to verify iCloud account for writes. \(service.describe(error))"
            return false
        }
    }

    private func snapshotGroup(_ group: CohortGroup) -> CloudKitStoreSnapshot.Group {
        CloudKitStoreSnapshot.Group(
            id: group.id,
            name: group.name,
            colorHex: group.colorHex,
            recordName: groupRecordNameByID[group.id] ?? group.id.uuidString
        )
    }

    private func snapshotDomain(_ domain: Domain) -> CloudKitStoreSnapshot.Domain {
        CloudKitStoreSnapshot.Domain(
            id: domain.id,
            name: domain.name,
            colorHex: domain.colorHex,
            overallModeRaw: domain.overallMode.rawValue,
            recordName: domainRecordNameByID[domain.id] ?? domain.id.uuidString
        )
    }

    private func snapshotLearningObjective(
        _ objective: LearningObjective,
        isArchivedOverride: Bool? = nil
    ) -> CloudKitStoreSnapshot.LearningObjective {
        CloudKitStoreSnapshot.LearningObjective(
            id: objective.id,
            code: objective.code,
            title: objective.title,
            objectiveDescription: objective.objectiveDescription,
            isQuantitative: objective.isQuantitative,
            parentCode: objective.parentCode,
            parentId: objective.parentId,
            sortOrder: objective.sortOrder,
            isArchived: isArchivedOverride ?? objective.isArchived,
            recordName: learningObjectiveRecordNameByID[objective.id] ?? objective.id.uuidString
        )
    }

    private func snapshotStudent(_ student: Student) -> CloudKitStoreSnapshot.Student {
        CloudKitStoreSnapshot.Student(
            id: student.id,
            name: student.name,
            createdAt: student.createdAt,
            sessionRawValue: student.session.rawValue,
            groupID: student.group?.id,
            domainID: student.domain?.id,
            recordName: studentRecordNameByID[student.id] ?? student.id.uuidString
        )
    }

    private func snapshotMembership(_ membership: StudentGroupMembership) -> CloudKitStoreSnapshot.Membership? {
        guard let studentID = membership.student?.id, let groupID = membership.group?.id else { return nil }
        return CloudKitStoreSnapshot.Membership(
            id: membership.id,
            studentID: studentID,
            groupID: groupID,
            createdAt: membership.createdAt,
            updatedAt: membership.updatedAt,
            recordName: membershipRecordNameByID[membership.id] ?? membership.id.uuidString
        )
    }

    private func snapshotProgress(
        _ progress: ObjectiveProgress,
        studentID: UUID
    ) -> CloudKitStoreSnapshot.ObjectiveProgress {
        CloudKitStoreSnapshot.ObjectiveProgress(
            id: progress.id,
            studentID: studentID,
            objectiveId: progress.objectiveId,
            objectiveCode: progress.objectiveCode,
            value: progress.value,
            notes: progress.notes,
            lastUpdated: progress.lastUpdated,
            statusRawValue: progress.status.rawValue,
            recordName: progressRecordNameByID[progress.id] ?? progress.id.uuidString
        )
    }

    private func snapshotCustomProperty(
        _ property: StudentCustomProperty,
        studentID: UUID
    ) -> UndoCustomPropertySnapshot {
        UndoCustomPropertySnapshot(
            id: property.id,
            studentID: studentID,
            key: property.key,
            value: property.value,
            sortOrder: property.sortOrder,
            recordName: customPropertyRecordNameByID[property.id] ?? property.id.uuidString
        )
    }

    private func explicitGroupIDs(for student: Student) -> [UUID] {
        explicitGroups(for: student)
            .map(\.id)
            .sorted { $0.uuidString < $1.uuidString }
    }

    private func snapshotStudentUndoBundle(_ student: Student) -> StudentUndoBundle {
        let membershipSnapshots = memberships
            .filter { $0.student?.id == student.id }
            .compactMap { snapshotMembership($0) }
            .sorted { $0.createdAt < $1.createdAt }
        let progressSnapshots = student.progressRecords
            .map { snapshotProgress($0, studentID: student.id) }
            .sorted { $0.objectiveCode < $1.objectiveCode }
        let customSnapshots = student.customProperties
            .map { snapshotCustomProperty($0, studentID: student.id) }
            .sorted { $0.sortOrder < $1.sortOrder }

        return StudentUndoBundle(
            student: snapshotStudent(student),
            memberships: membershipSnapshots,
            progress: progressSnapshots,
            customProperties: customSnapshots
        )
    }

    private func snapshotDeletedStudentBundle(_ student: Student) async -> StudentUndoBundle {
        let fallback = snapshotStudentUndoBundle(student)
        guard let cohortRecordID else { return fallback }

        let studentRecordID = recordID(for: student, lookup: studentRecordNameByID)
        let cohortRef = CKRecord.Reference(recordID: cohortRecordID, action: .none)
        let studentRef = CKRecord.Reference(recordID: studentRecordID, action: .none)

        var progressSnapshots = fallback.progress
        do {
            let records = try await queryProgressRecords(cohortRef: cohortRef, studentRecordID: studentRecordID)
            if records.isEmpty == false {
                progressSnapshots = records
                    .map { snapshotProgress(from: $0, studentID: student.id) }
                    .sorted { $0.objectiveCode < $1.objectiveCode }
            }
        } catch {
            syncLogger.error("Failed to snapshot progress before student delete: \(error.localizedDescription, privacy: .public)")
        }

        var customSnapshots = fallback.customProperties
        do {
            let predicate = NSPredicate(format: "cohortRef == %@ AND student == %@", cohortRef, studentRef)
            let records = try await service.queryRecords(ofType: RecordType.studentCustomProperty, predicate: predicate)
            if records.isEmpty == false {
                customSnapshots = records
                    .map { snapshotCustomProperty(from: $0, studentID: student.id) }
                    .sorted { $0.sortOrder < $1.sortOrder }
            }
        } catch {
            syncLogger.error("Failed to snapshot custom properties before student delete: \(error.localizedDescription, privacy: .public)")
        }

        return StudentUndoBundle(
            student: fallback.student,
            memberships: fallback.memberships,
            progress: progressSnapshots,
            customProperties: customSnapshots
        )
    }

    private func snapshotGroupDeleteBundle(_ group: CohortGroup) -> GroupUndoBundle {
        let membershipSnapshots = memberships
            .filter { $0.group?.id == group.id }
            .compactMap { snapshotMembership($0) }
            .sorted { $0.createdAt < $1.createdAt }
        let affectedStudentIDs = students
            .filter { student in
                student.group?.id == group.id
                || membershipSnapshots.contains(where: { $0.studentID == student.id })
            }
            .map(\.id)
            .sorted { $0.uuidString < $1.uuidString }
        return GroupUndoBundle(
            group: snapshotGroup(group),
            memberships: membershipSnapshots,
            affectedStudentIDs: affectedStudentIDs
        )
    }

    private func snapshotDomainDeleteBundle(_ domain: Domain) -> DomainUndoBundle {
        let affectedStudentIDs = students
            .filter { $0.domain?.id == domain.id }
            .map(\.id)
            .sorted { $0.uuidString < $1.uuidString }
        return DomainUndoBundle(domain: snapshotDomain(domain), affectedStudentIDs: affectedStudentIDs)
    }

    private func snapshotProgress(from record: CKRecord, studentID: UUID) -> CloudKitStoreSnapshot.ObjectiveProgress {
        let objectiveRef = record[Field.objectiveRef] as? CKRecord.Reference
        let resolvedObjectiveID: UUID? = objectiveRef.flatMap { reference in
            self.objectiveID(forRecordName: reference.recordID.recordName)
        }
        var objectiveCode = record[Field.objectiveCode] as? String ?? ""
        if objectiveCode.isEmpty, let resolvedObjectiveID, let objective = objectiveByID(resolvedObjectiveID) {
            objectiveCode = objective.code
        }
        let value = (record[Field.value] as? Int)
            ?? (record[Field.value] as? NSNumber)?.intValue
            ?? (record[Field.completionPercentage] as? Int)
            ?? (record[Field.completionPercentage] as? NSNumber)?.intValue
            ?? 0
        let notes = record[Field.notes] as? String ?? ""
        let lastUpdated = (record[Field.lastUpdated] as? Date) ?? Date()
        let statusRaw = record[Field.status] as? String
        let status = statusRaw ?? ObjectiveProgress.calculateStatus(from: value).rawValue
        let progressID = resolvedStableID(forRecordName: record.recordID.recordName, lookup: progressRecordNameByID)

        return CloudKitStoreSnapshot.ObjectiveProgress(
            id: progressID,
            studentID: studentID,
            objectiveId: resolvedObjectiveID,
            objectiveCode: objectiveCode,
            value: value,
            notes: notes,
            lastUpdated: lastUpdated,
            statusRawValue: status,
            recordName: record.recordID.recordName
        )
    }

    private func snapshotCustomProperty(from record: CKRecord, studentID: UUID) -> UndoCustomPropertySnapshot {
        let propertyID = resolvedStableID(forRecordName: record.recordID.recordName, lookup: customPropertyRecordNameByID)
        let key = record[Field.key] as? String ?? ""
        let value = record[Field.value] as? String ?? ""
        let sortOrder = (record[Field.sortOrder] as? Int)
            ?? (record[Field.sortOrder] as? NSNumber)?.intValue
            ?? 0
        return UndoCustomPropertySnapshot(
            id: propertyID,
            studentID: studentID,
            key: key,
            value: value,
            sortOrder: sortOrder,
            recordName: record.recordID.recordName
        )
    }

    private func deleteGroupByID(_ groupID: UUID) async -> Bool {
        guard let group = groups.first(where: { $0.id == groupID }) else { return true }
        await withUndoCaptureSuppressed {
            await deleteGroup(group)
        }
        return groups.contains(where: { $0.id == groupID }) == false
    }

    private func restoreGroupSnapshot(_ snapshot: CloudKitStoreSnapshot.Group) async -> Bool {
        guard await requireWriteAccess() else { return false }
        do {
            _ = try await ensureCohortRecordIDForWrite()
            let existing = groups.first(where: { $0.id == snapshot.id })
            let group: CohortGroup
            let created: Bool
            if let existing {
                group = existing
                created = false
            } else {
                group = CohortGroup(name: snapshot.name, colorHex: snapshot.colorHex)
                group.id = snapshot.id
                groups.append(group)
                created = true
            }
            group.name = snapshot.name
            group.colorHex = snapshot.colorHex
            groups.sort { $0.name < $1.name }
            groupRecordNameByID[snapshot.id] = snapshot.recordName

            do {
                try await saveGroupRecord(group)
                return true
            } catch {
                if created {
                    groups.removeAll { $0.id == snapshot.id }
                }
                lastErrorMessage = "Failed to restore group: \(error.localizedDescription)"
                return false
            }
        } catch {
            lastErrorMessage = "Failed to restore group: \(error.localizedDescription)"
            return false
        }
    }

    private func restoreDeletedGroup(_ bundle: GroupUndoBundle) async -> Bool {
        guard await restoreGroupSnapshot(bundle.group) else { return false }
        var succeeded = true
        for membership in bundle.memberships {
            succeeded = await restoreMembershipSnapshot(membership) && succeeded
        }
        let affectedStudentIDs = Set(bundle.memberships.map(\.studentID)).union(bundle.affectedStudentIDs)
        for studentID in affectedStudentIDs {
            guard let student = students.first(where: { $0.id == studentID }) else { continue }
            refreshLegacyGroupConvenience(for: student)
            do {
                try await saveStudentRecord(student)
            } catch {
                lastErrorMessage = "Failed to restore student group convenience field: \(error.localizedDescription)"
                succeeded = false
            }
        }
        return succeeded
    }

    private func deleteDomainByID(_ domainID: UUID) async -> Bool {
        guard let domain = domains.first(where: { $0.id == domainID }) else { return true }
        await withUndoCaptureSuppressed {
            await deleteDomain(domain)
        }
        return domains.contains(where: { $0.id == domainID }) == false
    }

    private func restoreDomainSnapshot(_ snapshot: CloudKitStoreSnapshot.Domain) async -> Bool {
        guard await requireWriteAccess() else { return false }
        do {
            _ = try await ensureCohortRecordIDForWrite()
            let existing = domains.first(where: { $0.id == snapshot.id })
            let domain: Domain
            let created: Bool
            if let existing {
                domain = existing
                created = false
            } else {
                let mode = ExpertiseCheckOverallMode(rawValue: snapshot.overallModeRaw) ?? .computed
                domain = Domain(name: snapshot.name, colorHex: snapshot.colorHex, overallMode: mode)
                domain.id = snapshot.id
                domains.append(domain)
                created = true
            }
            domain.name = snapshot.name
            domain.colorHex = snapshot.colorHex
            domain.overallMode = ExpertiseCheckOverallMode(rawValue: snapshot.overallModeRaw) ?? .computed
            domains.sort { $0.name < $1.name }
            domainRecordNameByID[snapshot.id] = snapshot.recordName

            do {
                try await saveDomainRecord(domain)
                return true
            } catch {
                if created {
                    domains.removeAll { $0.id == snapshot.id }
                }
                lastErrorMessage = "Failed to restore expertise check: \(error.localizedDescription)"
                return false
            }
        } catch {
            lastErrorMessage = "Failed to restore expertise check: \(error.localizedDescription)"
            return false
        }
    }

    private func restoreDeletedDomain(_ bundle: DomainUndoBundle) async -> Bool {
        guard await restoreDomainSnapshot(bundle.domain) else { return false }
        guard let domain = domains.first(where: { $0.id == bundle.domain.id }) else { return false }
        var succeeded = true
        for studentID in bundle.affectedStudentIDs {
            guard let student = students.first(where: { $0.id == studentID }) else { continue }
            student.domain = domain
            do {
                try await saveStudentRecord(student)
            } catch {
                lastErrorMessage = "Failed to restore student expertise check: \(error.localizedDescription)"
                succeeded = false
            }
        }
        return succeeded
    }

    private func deleteStudentByID(_ studentID: UUID) async -> Bool {
        guard let student = students.first(where: { $0.id == studentID }) else { return true }
        await withUndoCaptureSuppressed {
            await deleteStudent(student)
        }
        return students.contains(where: { $0.id == studentID }) == false
    }

    private func restoreStudentEditableState(_ bundle: StudentUndoBundle) async -> Bool {
        guard await requireWriteAccess() else { return false }
        guard let student = await upsertStudentCore(bundle.student) else { return false }
        guard await applyStudentCustomProperties(student: student, snapshots: bundle.customProperties) else { return false }
        let groupIDs = Array(Set(bundle.memberships.map(\.groupID))).sorted { $0.uuidString < $1.uuidString }
        return await applyStudentGroupSelection(studentID: student.id, groupIDs: groupIDs)
    }

    private func restoreDeletedStudent(_ bundle: StudentUndoBundle) async -> Bool {
        guard await requireWriteAccess() else { return false }
        guard let student = await upsertStudentCore(bundle.student) else { return false }
        guard await applyStudentCustomProperties(student: student, snapshots: bundle.customProperties) else { return false }

        do {
            try await deleteProgress(for: student)
        } catch {
            lastErrorMessage = "Failed to clear existing progress before restore: \(error.localizedDescription)"
            return false
        }
        for progress in student.progressRecords {
            progressRecordNameByID.removeValue(forKey: progress.id)
        }
        student.progressRecords.removeAll()

        var succeeded = true
        for progressSnapshot in bundle.progress {
            succeeded = await upsertProgressSnapshot(progressSnapshot) && succeeded
        }

        do {
            try await deleteMemberships(forStudentID: student.id)
        } catch {
            lastErrorMessage = "Failed to clear existing memberships before restore: \(error.localizedDescription)"
            return false
        }
        for membershipSnapshot in bundle.memberships {
            succeeded = await restoreMembershipSnapshot(membershipSnapshot) && succeeded
        }

        refreshLegacyGroupConvenience(for: student)
        do {
            try await saveStudentRecord(student)
        } catch {
            lastErrorMessage = "Failed to restore student legacy group convenience field: \(error.localizedDescription)"
            succeeded = false
        }
        return succeeded
    }

    private func upsertStudentCore(_ snapshot: CloudKitStoreSnapshot.Student) async -> Student? {
        do {
            _ = try await ensureCohortRecordIDForWrite()
            let existing = students.first(where: { $0.id == snapshot.id })
            let student: Student
            if let existing {
                student = existing
            } else {
                student = Student(name: snapshot.name, group: nil, session: .morning, domain: nil)
                student.id = snapshot.id
                students.append(student)
                students.sort { $0.createdAt < $1.createdAt }
            }
            student.name = snapshot.name
            student.createdAt = snapshot.createdAt
            student.session = Session(rawValue: snapshot.sessionRawValue) ?? .morning
            student.group = snapshot.groupID.flatMap { groupID in
                groups.first(where: { $0.id == groupID })
            }
            student.domain = snapshot.domainID.flatMap { domainID in
                domains.first(where: { $0.id == domainID })
            }
            studentRecordNameByID[snapshot.id] = snapshot.recordName

            do {
                try await saveStudentRecord(student)
                return student
            } catch {
                lastErrorMessage = "Failed to restore student: \(error.localizedDescription)"
                return nil
            }
        } catch {
            lastErrorMessage = "Failed to restore student: \(error.localizedDescription)"
            return nil
        }
    }

    private func applyStudentCustomProperties(
        student: Student,
        snapshots: [UndoCustomPropertySnapshot]
    ) async -> Bool {
        do {
            try await deleteCustomProperties(for: student)
        } catch {
            lastErrorMessage = "Failed to clear custom properties before restore: \(error.localizedDescription)"
            return false
        }

        for property in student.customProperties {
            customPropertyRecordNameByID.removeValue(forKey: property.id)
        }
        student.customProperties.removeAll()

        for snapshot in snapshots.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            let property = StudentCustomProperty(key: snapshot.key, value: snapshot.value, sortOrder: snapshot.sortOrder)
            property.id = snapshot.id
            property.student = student
            student.customProperties.append(property)
            customPropertyRecordNameByID[snapshot.id] = snapshot.recordName
            do {
                try await saveCustomProperty(property, student: student)
            } catch {
                lastErrorMessage = "Failed to restore custom property: \(error.localizedDescription)"
                return false
            }
        }

        customPropertiesLoadedStudentIDs.insert(student.id)
        return true
    }

    private func applyStudentGroupSelection(studentID: UUID, groupIDs: [UUID]) async -> Bool {
        guard let student = students.first(where: { $0.id == studentID }) else { return false }
        let desired = groupIDs.compactMap { targetID in
            groups.first(where: { $0.id == targetID })
        }
        if desired.count != groupIDs.count {
            lastErrorMessage = "Unable to restore one or more group memberships because the group no longer exists."
            return false
        }

        do {
            try await setGroupsInternal(for: student, groups: desired, updateLegacyGroupField: true)
            let restored = explicitGroupIDs(for: student)
            return restored == groupIDs.sorted { $0.uuidString < $1.uuidString }
        } catch {
            lastErrorMessage = "Failed to restore student groups: \(error.localizedDescription)"
            return false
        }
    }

    private func restoreMembershipSnapshot(_ snapshot: CloudKitStoreSnapshot.Membership) async -> Bool {
        guard let student = students.first(where: { $0.id == snapshot.studentID }) else { return false }
        guard let group = groups.first(where: { $0.id == snapshot.groupID }) else { return false }

        let membership: StudentGroupMembership
        if let existing = memberships.first(where: { $0.id == snapshot.id }) {
            membership = existing
            membership.student = student
            membership.group = group
            membership.createdAt = snapshot.createdAt
            membership.updatedAt = snapshot.updatedAt
        } else {
            membership = StudentGroupMembership(
                student: student,
                group: group,
                createdAt: snapshot.createdAt,
                updatedAt: snapshot.updatedAt
            )
            membership.id = snapshot.id
            memberships.append(membership)
            memberships = uniqueMemberships(memberships)
        }

        membershipRecordNameByID[snapshot.id] = snapshot.recordName
        do {
            try await saveMembershipRecord(membership, student: student, group: group)
            return true
        } catch {
            lastErrorMessage = "Failed to restore group membership: \(error.localizedDescription)"
            return false
        }
    }

    private func restoreLearningObjectiveSnapshot(_ snapshot: CloudKitStoreSnapshot.LearningObjective) async -> Bool {
        guard await requireWriteAccess() else { return false }
        do {
            _ = try await ensureCohortRecordIDForWrite()
            let existing = allLearningObjectives.first(where: { $0.id == snapshot.id })
            let objective: LearningObjective
            let created: Bool
            if let existing {
                objective = existing
                created = false
            } else {
                objective = LearningObjective(
                    code: snapshot.code,
                    title: snapshot.title,
                    description: snapshot.objectiveDescription,
                    isQuantitative: snapshot.isQuantitative,
                    parentCode: snapshot.parentCode,
                    parentId: snapshot.parentId,
                    sortOrder: snapshot.sortOrder,
                    isArchived: snapshot.isArchived
                )
                objective.id = snapshot.id
                allLearningObjectives.append(objective)
                created = true
            }

            objective.code = snapshot.code
            objective.title = snapshot.title
            objective.objectiveDescription = snapshot.objectiveDescription
            objective.isQuantitative = snapshot.isQuantitative
            objective.parentCode = snapshot.parentCode
            objective.parentId = snapshot.parentId
            objective.sortOrder = snapshot.sortOrder
            objective.isArchived = snapshot.isArchived
            learningObjectiveRecordNameByID[snapshot.id] = snapshot.recordName
            setLearningObjectives(allLearningObjectives)

            do {
                try await saveLearningObjectiveRecord(objective)
                return true
            } catch {
                if created {
                    allLearningObjectives.removeAll { $0.id == snapshot.id }
                    setLearningObjectives(allLearningObjectives)
                }
                lastErrorMessage = "Failed to restore learning objective: \(error.localizedDescription)"
                return false
            }
        } catch {
            lastErrorMessage = "Failed to restore learning objective: \(error.localizedDescription)"
            return false
        }
    }

    private func restoreProgressSnapshot(_ snapshot: CloudKitStoreSnapshot.ObjectiveProgress) async -> Bool {
        guard await requireWriteAccess() else { return false }
        return await upsertProgressSnapshot(snapshot)
    }

    private func upsertProgressSnapshot(_ snapshot: CloudKitStoreSnapshot.ObjectiveProgress) async -> Bool {
        guard let student = students.first(where: { $0.id == snapshot.studentID }) else { return false }
        guard let cohortRecordID = try? await ensureCohortRecordIDForWrite() else {
            lastErrorMessage = "Unable to resolve cohort record while restoring progress."
            return false
        }
        let studentRecordID = recordID(for: student, lookup: studentRecordNameByID)
        let objective = snapshot.objectiveId.flatMap { objectiveByID($0) } ?? objectiveByCode(snapshot.objectiveCode)

        let progress: ObjectiveProgress
        if let existing = student.progressRecords.first(where: { $0.id == snapshot.id }) {
            progress = existing
        } else {
            progress = ObjectiveProgress(
                objectiveCode: snapshot.objectiveCode,
                completionPercentage: snapshot.value,
                notes: snapshot.notes,
                objectiveId: snapshot.objectiveId,
                value: snapshot.value
            )
            progress.id = snapshot.id
            progress.student = student
            student.progressRecords.append(progress)
        }

        progress.objectiveId = snapshot.objectiveId
        progress.objectiveCode = snapshot.objectiveCode
        progress.value = snapshot.value
        progress.completionPercentage = snapshot.value
        progress.notes = snapshot.notes
        progress.lastUpdated = snapshot.lastUpdated
        progress.status = ProgressStatus(rawValue: snapshot.statusRawValue)
            ?? ObjectiveProgress.calculateStatus(from: snapshot.value)

        progressRecordNameByID[snapshot.id] = snapshot.recordName

        let progressRecordID = CKRecord.ID(recordName: snapshot.recordName)
        markRecordRecentlyWritten(recordType: RecordType.objectiveProgress, recordName: progressRecordID.recordName)
        let record = CKRecord(recordType: RecordType.objectiveProgress, recordID: progressRecordID)
        record[Field.cohortRef] = CKRecord.Reference(recordID: cohortRecordID, action: .none)
        let studentRef = CKRecord.Reference(recordID: studentRecordID, action: .none)
        record[Field.studentRef] = studentRef
        record[Field.student] = CKRecord.Reference(recordID: studentRecordID, action: .none)
        record[Field.objectiveCode] = progress.objectiveCode
        record[Field.value] = progress.value
        record[Field.completionPercentage] = progress.completionPercentage
        record[Field.status] = progress.status.rawValue
        record[Field.notes] = progress.notes
        record[Field.lastUpdated] = progress.lastUpdated
        if let objective {
            let objectiveRecordID = recordID(for: objective, lookup: learningObjectiveRecordNameByID)
            record[Field.objectiveRef] = CKRecord.Reference(recordID: objectiveRecordID, action: .none)
        } else {
            record[Field.objectiveRef] = nil
        }
        applyAuditFields(to: record, createdAt: progress.lastUpdated)

        do {
            let saved = try await service.save(record: record)
            progressRecordNameByID[snapshot.id] = saved.recordID.recordName
            progressLoadedStudentIDs.insert(student.id)
            markRecordRecentlyWritten(recordType: RecordType.objectiveProgress, recordName: saved.recordID.recordName)
            rebuildProgressCaches()
            return true
        } catch {
            lastErrorMessage = "Failed to restore progress: \(error.localizedDescription)"
            return false
        }
    }

    private func deleteProgressBySnapshot(_ snapshot: CloudKitStoreSnapshot.ObjectiveProgress) async -> Bool {
        guard await requireWriteAccess() else { return false }
        if let student = students.first(where: { $0.id == snapshot.studentID }) {
            student.progressRecords.removeAll { $0.id == snapshot.id }
        }
        progressRecordNameByID.removeValue(forKey: snapshot.id)
        do {
            try await service.delete(recordID: CKRecord.ID(recordName: snapshot.recordName))
        } catch {
            if isUnknownItemError(error) == false {
                lastErrorMessage = "Failed to delete progress during undo: \(error.localizedDescription)"
                rebuildProgressCaches()
                return false
            }
        }
        rebuildProgressCaches()
        syncCoordinator?.noteLocalWrite()
        return true
    }

    private func isUnknownItemError(_ error: Error) -> Bool {
        guard let ckError = error as? CKError else { return false }
        return ckError.code == .unknownItem
    }

    private func isCloudKitOplockConflict(_ error: Error) -> Bool {
        guard let ckError = error as? CKError else {
            return error.localizedDescription.localizedCaseInsensitiveContains("oplock")
        }

        if ckError.code == .serverRecordChanged {
            return true
        }

        if ckError.code == .partialFailure,
           let partials = ckError.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error],
           partials.values.contains(where: { isCloudKitOplockConflict($0) }) {
            return true
        }

        let details = service.describe(error).lowercased()
        if details.contains("oplock") || details.contains("server record changed") {
            return true
        }

        return false
    }

    private func retryDelayNanoseconds(for error: Error, attempt: Int) -> UInt64 {
        if let ckError = error as? CKError, let retryAfter = ckError.retryAfterSeconds {
            let clampedSeconds = max(0.2, min(retryAfter, 2.0))
            return UInt64(clampedSeconds * 1_000_000_000)
        }
        let baseSeconds = min(0.2 * Double(attempt), 0.8)
        return UInt64(baseSeconds * 1_000_000_000)
    }

    func openICloudSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preferences.AppleIDPrefPane") {
            NSWorkspace.shared.open(url)
        }
    }

    func isPendingCreate(group: CohortGroup) -> Bool {
        pendingGroupCreateIDs.contains(group.id)
    }

    func isPendingCreate(domain: Domain) -> Bool {
        pendingDomainCreateIDs.contains(domain.id)
    }

    func isSavingExpertiseCheckMode(domain: Domain) -> Bool {
        pendingExpertiseCheckModeUpdateIDs.contains(domain.id)
    }

    func isPendingCreate(objective: LearningObjective) -> Bool {
        pendingLearningObjectiveCreateIDs.contains(objective.id)
    }

    func isPendingCreate(categoryCode: String) -> Bool {
        pendingCategoryLabelCreateKeys.contains(categoryCode)
    }

    private func recordID<T>(for item: T, lookup: [UUID: String]) -> CKRecord.ID where T: Identifiable, T.ID == UUID {
        let recordName = lookup[item.id] ?? item.id.uuidString
        return CKRecord.ID(recordName: recordName)
    }

    private func existingID(forRecordName recordName: String, lookup: [UUID: String]) -> UUID? {
        lookup.first(where: { $0.value == recordName })?.key
    }

    private func orderedLearningObjectivesForSeed(_ objectives: [LearningObjective]) -> [LearningObjective] {
        objectives.sorted {
            if $0.depth != $1.depth {
                return $0.depth < $1.depth
            }
            if $0.sortOrder != $1.sortOrder {
                return $0.sortOrder < $1.sortOrder
            }
            return $0.code < $1.code
        }
    }

    private func seedLearningObjectives(_ objectives: [LearningObjective]) async throws {
        let orderedObjectives = orderedLearningObjectivesForSeed(objectives)
        for objective in orderedObjectives {
            objective.isArchived = false
            try await saveLearningObjectiveRecord(objective, allObjectives: objectives)
        }
        setLearningObjectives(objectives)
    }

    private func clearLocalObjectiveProgressState() {
        objectWillChange.send()
        progressRecordNameByID.removeAll()
        objectiveRefMigrationRecordNames.removeAll()
        progressLoadedStudentIDs.removeAll()
        for student in students {
            student.progressRecords.removeAll()
        }
        rebuildProgressCaches()
    }

    private func clearLocalCustomPropertyState() {
        customPropertyRecordNameByID.removeAll()
        customPropertiesLoadedStudentIDs.removeAll()
        for student in students {
            student.customProperties.removeAll()
        }
    }

    private func clearLocalMembershipState() {
        memberships.removeAll()
        membershipRecordNameByID.removeAll()
        refreshLegacyGroupConvenience()
        rebuildGroupMembershipCaches()
    }

    private func clearLocalStudentState() {
        students.removeAll()
        selectedStudentId = nil
        studentRecordNameByID.removeAll()
        progressLoadedStudentIDs.removeAll()
        customPropertiesLoadedStudentIDs.removeAll()
        memberships.removeAll()
        membershipRecordNameByID.removeAll()
        progressRecordNameByID.removeAll()
        customPropertyRecordNameByID.removeAll()
        rebuildGroupMembershipCaches()
        rebuildProgressCaches()
    }

    private func clearLocalGroupState() {
        groups.removeAll()
        groupRecordNameByID.removeAll()
        pendingGroupCreateIDs.removeAll()
        unconfirmedGroupRecordNames.removeAll()
        refreshLegacyGroupConvenience()
        rebuildGroupMembershipCaches()
    }

    private func clearLocalCategoryLabelState() {
        categoryLabels.removeAll()
        categoryLabelRecordNameByCode.removeAll()
        pendingCategoryLabelCreateKeys.removeAll()
        unconfirmedCategoryLabelRecordNames.removeAll()
    }

    private func clearInMemoryDataForSheetSwitch() {
        clearLocalObjectiveProgressState()
        clearLocalCustomPropertyState()
        clearLocalMembershipState()
        clearLocalStudentState()
        clearLocalGroupState()
        clearLocalCategoryLabelState()
        clearLocalDomainState()
        clearLocalLearningObjectiveState()
        selectedScope = .overall
        selectedStudentId = nil
        lastErrorMessage = nil
        lastSyncDate = .distantPast
    }

    private func clearLocalDomainState() {
        domains.removeAll()
        domainRecordNameByID.removeAll()
        pendingDomainCreateIDs.removeAll()
        pendingExpertiseCheckModeUpdateIDs.removeAll()
        unconfirmedDomainRecordNames.removeAll()
        expertiseCheckObjectiveScores.removeAll()
        expertiseCheckScoreRecordNameByID.removeAll()
        categoryLabelRecordNameByCode.removeAll()
        expertiseCheckScoreByDomainObjectiveID.removeAll()
        expertiseCheckScoreByDomainObjectiveCode.removeAll()
        for student in students {
            student.domain = nil
        }
    }

    private func clearLocalLearningObjectiveState() {
        learningObjectiveRecordNameByID.removeAll()
        pendingLearningObjectiveCreateIDs.removeAll()
        unconfirmedLearningObjectiveRecordNames.removeAll()
        allLearningObjectives.removeAll()
        setLearningObjectives([])
    }

    private func ensureCohortRecordIDForWrite() async throws -> CKRecord.ID {
        if let cohortRecordID {
            return cohortRecordID
        }
        let cohortRecord = try await ensureCohortRecord()
        cohortRecordID = cohortRecord.recordID
        return cohortRecord.recordID
    }

    private func resolvedStableID(forRecordName recordName: String, lookup: [UUID: String]) -> UUID {
        if let uuid = UUID(uuidString: recordName) {
            return uuid
        }
        if let existing = existingID(forRecordName: recordName, lookup: lookup) {
            return existing
        }
        return UUID()
    }

    private func normalizedDomainName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func clearRecordTrackingStateForFullReload() {
        groupRecordNameByID.removeAll()
        domainRecordNameByID.removeAll()
        learningObjectiveRecordNameByID.removeAll()
        studentRecordNameByID.removeAll()
        membershipRecordNameByID.removeAll()
        progressRecordNameByID.removeAll()
        customPropertyRecordNameByID.removeAll()
        expertiseCheckScoreRecordNameByID.removeAll()
        pendingGroupCreateIDs.removeAll()
        pendingDomainCreateIDs.removeAll()
        pendingExpertiseCheckModeUpdateIDs.removeAll()
        pendingLearningObjectiveCreateIDs.removeAll()
        pendingCategoryLabelCreateKeys.removeAll()
        unconfirmedGroupRecordNames.removeAll()
        unconfirmedDomainRecordNames.removeAll()
        unconfirmedLearningObjectiveRecordNames.removeAll()
        unconfirmedCategoryLabelRecordNames.removeAll()
        recentLocalWriteRecordKeys.removeAll()
        objectiveRefMigrationRecordNames.removeAll()
        expertiseCheckObjectiveScores.removeAll()
        expertiseCheckScoreByDomainObjectiveID.removeAll()
        expertiseCheckScoreByDomainObjectiveCode.removeAll()
    }

    private func mapSheet(from record: CKRecord) -> CohortSheet {
        let cohortId = record[Field.cohortId] as? String ?? record.recordID.recordName
        let name = record[Field.name] as? String ?? "Sheet"
        let createdAt = record[Field.createdAt] as? Date ?? Date()
        let updatedAt = record[Field.updatedAt] as? Date ?? createdAt
        return CohortSheet(id: record.recordID.recordName, cohortId: cohortId, name: name, createdAt: createdAt, updatedAt: updatedAt)
    }

    private func deduplicatedProgress(_ records: [ObjectiveProgress]) -> [ObjectiveProgress] {
        var byKey: [String: ObjectiveProgress] = [:]
        for progress in records {
            let key = progress.objectiveId?.uuidString ?? "code:\(progress.objectiveCode)"
            if let existing = byKey[key] {
                if progress.lastUpdated >= existing.lastUpdated {
                    byKey[key] = progress
                }
            } else {
                byKey[key] = progress
            }
        }
        return Array(byKey.values)
    }

    private func restoreSnapshotIfAvailable() -> Bool {
        guard isPreviewData == false else { return false }
        guard let snapshot = CloudKitStoreSnapshotCache.load(cohortId: activeCohortId) else { return false }

        clearRecordTrackingStateForFullReload()

        var restoredGroups: [CohortGroup] = []
        for cached in snapshot.groups {
            let group = CohortGroup(name: cached.name, colorHex: cached.colorHex)
            group.id = cached.id
            groupRecordNameByID[cached.id] = cached.recordName
            restoredGroups.append(group)
        }
        restoredGroups.sort { $0.name < $1.name }
        let groupsByID = Dictionary(uniqueKeysWithValues: restoredGroups.map { ($0.id, $0) })

        var restoredDomains: [Domain] = []
        for cached in snapshot.domains {
            let mode = ExpertiseCheckOverallMode(rawValue: cached.overallModeRaw) ?? .computed
            let domain = Domain(name: cached.name, colorHex: cached.colorHex, overallMode: mode)
            domain.id = cached.id
            domainRecordNameByID[cached.id] = cached.recordName
            restoredDomains.append(domain)
        }
        restoredDomains.sort { $0.name < $1.name }
        let domainsByID = Dictionary(uniqueKeysWithValues: restoredDomains.map { ($0.id, $0) })

        var restoredObjectives: [LearningObjective] = []
        for cached in snapshot.learningObjectives {
            let objective = LearningObjective(
                code: cached.code,
                title: cached.title,
                description: cached.objectiveDescription,
                isQuantitative: cached.isQuantitative,
                parentCode: cached.parentCode,
                parentId: cached.parentId,
                sortOrder: cached.sortOrder,
                isArchived: cached.isArchived
            )
            objective.id = cached.id
            learningObjectiveRecordNameByID[cached.id] = cached.recordName
            restoredObjectives.append(objective)
        }

        var restoredStudents: [Student] = []
        for cached in snapshot.students {
            let session = Session(rawValue: cached.sessionRawValue) ?? .morning
            let student = Student(
                name: cached.name,
                group: cached.groupID.flatMap { groupsByID[$0] },
                session: session,
                domain: cached.domainID.flatMap { domainsByID[$0] }
            )
            student.id = cached.id
            student.createdAt = cached.createdAt
            studentRecordNameByID[cached.id] = cached.recordName
            restoredStudents.append(student)
        }
        restoredStudents.sort { $0.createdAt < $1.createdAt }
        let studentsByID = Dictionary(uniqueKeysWithValues: restoredStudents.map { ($0.id, $0) })

        var restoredMemberships: [StudentGroupMembership] = []
        for cached in snapshot.memberships {
            guard let student = studentsByID[cached.studentID],
                  let group = groupsByID[cached.groupID] else {
                continue
            }
            let membership = StudentGroupMembership(
                student: student,
                group: group,
                createdAt: cached.createdAt,
                updatedAt: cached.updatedAt
            )
            membership.id = cached.id
            membershipRecordNameByID[cached.id] = cached.recordName
            restoredMemberships.append(membership)
        }

        for cached in snapshot.objectiveProgress {
            guard let student = studentsByID[cached.studentID] else { continue }
            let progress = ObjectiveProgress(
                objectiveCode: cached.objectiveCode,
                completionPercentage: cached.value,
                notes: cached.notes,
                objectiveId: cached.objectiveId,
                value: cached.value
            )
            progress.id = cached.id
            progress.lastUpdated = cached.lastUpdated
            progress.status = ProgressStatus(rawValue: cached.statusRawValue)
            ?? ObjectiveProgress.calculateStatus(from: cached.value)
            progress.student = student
            student.progressRecords.append(progress)
            progressRecordNameByID[cached.id] = cached.recordName
        }
        for student in restoredStudents {
            student.progressRecords = deduplicatedProgress(student.progressRecords).sorted { $0.objectiveCode < $1.objectiveCode }
        }

        var restoredExpertiseCheckScores: [ExpertiseCheckObjectiveScore] = []
        for cached in snapshot.expertiseCheckObjectiveScores {
            let score = ExpertiseCheckObjectiveScore(
                expertiseCheckId: cached.expertiseCheckID,
                objectiveId: cached.objectiveId,
                objectiveCode: cached.objectiveCode,
                value: cached.value,
                status: ProgressStatus(rawValue: cached.statusRawValue),
                createdAt: cached.createdAt,
                updatedAt: cached.updatedAt,
                lastEditedByDisplayName: cached.lastEditedByDisplayName
            )
            score.id = cached.id
            expertiseCheckScoreRecordNameByID[cached.id] = cached.recordName
            restoredExpertiseCheckScores.append(score)
        }

        let restoredLabels = snapshot.categoryLabels.map { cached in
            CategoryLabel(code: cached.code, title: cached.title)
        }.sorted { $0.key < $1.key }

        groups = restoredGroups
        domains = restoredDomains
        students = restoredStudents
        memberships = uniqueMemberships(restoredMemberships)
        categoryLabels = restoredLabels
        applyExpertiseCheckScores(restoredExpertiseCheckScores, cleanupRemoteDuplicates: false)
        if restoredObjectives.isEmpty {
            setLearningObjectives(defaultLearningObjectivesWithResolvedParents())
        } else {
            setLearningObjectives(restoredObjectives)
        }
        refreshLegacyGroupConvenience()
        rebuildAllDerivedCaches()

        progressLoadedStudentIDs = Set(restoredStudents.map(\.id))
        customPropertiesLoadedStudentIDs.removeAll()
        cohortRecordID = snapshot.cohortRecordName.map { CKRecord.ID(recordName: $0) }
        lastSyncDate = snapshot.lastSyncDate
        cachedSnapshotDate = snapshot.savedAt
        return true
    }

    private func makeSnapshot() -> CloudKitStoreSnapshot {
        let savedAt = Date()
        let snapshotGroups = groups.map { group in
            CloudKitStoreSnapshot.Group(
                id: group.id,
                name: group.name,
                colorHex: group.colorHex,
                recordName: groupRecordNameByID[group.id] ?? group.id.uuidString
            )
        }
        let snapshotDomains = domains.map { domain in
            CloudKitStoreSnapshot.Domain(
                id: domain.id,
                name: domain.name,
                colorHex: domain.colorHex,
                overallModeRaw: domain.overallMode.rawValue,
                recordName: domainRecordNameByID[domain.id] ?? domain.id.uuidString
            )
        }
        let snapshotLabels = categoryLabels.map { label in
            CloudKitStoreSnapshot.CategoryLabel(
                code: label.code,
                title: label.title,
                recordName: label.key
            )
        }
        let snapshotObjectives = allLearningObjectives.map { objective in
            CloudKitStoreSnapshot.LearningObjective(
                id: objective.id,
                code: objective.code,
                title: objective.title,
                objectiveDescription: objective.objectiveDescription,
                isQuantitative: objective.isQuantitative,
                parentCode: objective.parentCode,
                parentId: objective.parentId,
                sortOrder: objective.sortOrder,
                isArchived: objective.isArchived,
                recordName: learningObjectiveRecordNameByID[objective.id] ?? objective.id.uuidString
            )
        }
        let snapshotStudents = students.map { student in
            CloudKitStoreSnapshot.Student(
                id: student.id,
                name: student.name,
                createdAt: student.createdAt,
                sessionRawValue: student.session.rawValue,
                groupID: student.group?.id,
                domainID: student.domain?.id,
                recordName: studentRecordNameByID[student.id] ?? student.id.uuidString
            )
        }
        let snapshotMemberships = memberships.compactMap { membership -> CloudKitStoreSnapshot.Membership? in
            guard let studentID = membership.student?.id, let groupID = membership.group?.id else { return nil }
            return CloudKitStoreSnapshot.Membership(
                id: membership.id,
                studentID: studentID,
                groupID: groupID,
                createdAt: membership.createdAt,
                updatedAt: membership.updatedAt,
                recordName: membershipRecordNameByID[membership.id] ?? membership.id.uuidString
            )
        }
        let snapshotProgress = students.flatMap { student in
            student.progressRecords.map { progress in
                CloudKitStoreSnapshot.ObjectiveProgress(
                    id: progress.id,
                    studentID: student.id,
                    objectiveId: progress.objectiveId,
                    objectiveCode: progress.objectiveCode,
                    value: progress.value,
                    notes: progress.notes,
                    lastUpdated: progress.lastUpdated,
                    statusRawValue: progress.status.rawValue,
                    recordName: progressRecordNameByID[progress.id] ?? progress.id.uuidString
                )
            }
        }
        let snapshotExpertiseCheckScores = expertiseCheckObjectiveScores.compactMap { score -> CloudKitStoreSnapshot.ExpertiseCheckObjectiveScore? in
            guard let expertiseCheckID = score.expertiseCheckId else { return nil }
            return CloudKitStoreSnapshot.ExpertiseCheckObjectiveScore(
                id: score.id,
                expertiseCheckID: expertiseCheckID,
                objectiveId: score.objectiveId,
                objectiveCode: score.objectiveCode,
                value: score.value,
                statusRawValue: score.statusRawValue,
                createdAt: score.createdAt,
                updatedAt: score.updatedAt,
                lastEditedByDisplayName: score.lastEditedByDisplayName,
                recordName: expertiseCheckScoreRecordNameByID[score.id] ?? score.id.uuidString
            )
        }

        return CloudKitStoreSnapshot(
            schemaVersion: CloudKitStoreSnapshot.currentSchemaVersion,
            savedAt: savedAt,
            cohortRecordName: cohortRecordID?.recordName,
            lastSyncDate: lastSyncDate,
            groups: snapshotGroups,
            domains: snapshotDomains,
            categoryLabels: snapshotLabels,
            learningObjectives: snapshotObjectives,
            students: snapshotStudents,
            memberships: snapshotMemberships,
            objectiveProgress: snapshotProgress,
            expertiseCheckObjectiveScores: snapshotExpertiseCheckScores
        )
    }

    private func scheduleSnapshotPersistence() {
        guard isPreviewData == false else { return }
        guard hasLoaded else { return }
        snapshotPersistTask?.cancel()
        snapshotPersistTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.snapshotPersistDebounceNanoseconds)
            if Task.isCancelled { return }
            let snapshot = self.makeSnapshot()
            do {
                try CloudKitStoreSnapshotCache.save(snapshot, cohortId: self.activeCohortId)
                self.cachedSnapshotDate = snapshot.savedAt
                self.hasCachedSnapshotData = true
            } catch {
                self.syncLogger.error("Failed to persist snapshot: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func rebuildAllDerivedCaches() {
        rebuildGroupMembershipCaches()
        rebuildObjectiveCaches()
        rebuildProgressCaches()
    }

    private func rebuildGroupMembershipCaches() {
        let groupByID = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0) })
        var groupIDsByStudentID: [UUID: Set<UUID>] = [:]

        for membership in memberships {
            guard let studentID = membership.student?.id,
                  let groupID = membership.group?.id,
                  groupByID[groupID] != nil else {
                continue
            }
            groupIDsByStudentID[studentID, default: []].insert(groupID)
        }

        var rebuilt: [UUID: [CohortGroup]] = [:]
        for (studentID, groupIDs) in groupIDsByStudentID {
            let groups = groupIDs.compactMap { groupByID[$0] }.sorted { $0.name < $1.name }
            rebuilt[studentID] = groups
        }
        groupsByStudentIDCache = rebuilt
    }

    private func rebuildObjectiveCaches() {
        objectiveByCodeCache = objectiveDictionaryByCode(allLearningObjectives)

        let activeObjectives = learningObjectives

        let objectiveByID = Dictionary(uniqueKeysWithValues: activeObjectives.map { ($0.id, $0) })
        let objectiveByCode = objectiveDictionaryByCode(activeObjectives)

        var childrenByParent: [UUID: [LearningObjective]] = [:]
        var roots: [LearningObjective] = []

        for objective in activeObjectives {
            if let parentID = objective.parentId, objectiveByID[parentID] != nil {
                childrenByParent[parentID, default: []].append(objective)
                continue
            }
            if let parentCode = objective.parentCode,
               let parent = objectiveByCode[parentCode] {
                childrenByParent[parent.id, default: []].append(objective)
                continue
            }
            if objective.isRootCategory {
                roots.append(objective)
            }
        }

        for (parentID, children) in childrenByParent {
            childrenByParent[parentID] = children.sorted {
                if $0.sortOrder != $1.sortOrder {
                    return $0.sortOrder < $1.sortOrder
                }
                return $0.code < $1.code
            }
        }

        rootCategoryObjectivesCache = roots.sorted {
            if $0.sortOrder != $1.sortOrder {
                return $0.sortOrder < $1.sortOrder
            }
            return $0.code < $1.code
        }
        objectiveChildrenByParentID = childrenByParent
    }

    private func normalizedObjectiveCode(_ code: String) -> String {
        code.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedObjectiveCodeKey(_ code: String) -> String {
        normalizedObjectiveCode(code).lowercased()
    }

    private func hasObjectiveCodeConflict(_ code: String, excluding objectiveID: UUID?) -> Bool {
        let key = normalizedObjectiveCodeKey(code)
        guard key.isEmpty == false else { return false }
        return allLearningObjectives.contains { objective in
            if let objectiveID, objective.id == objectiveID {
                return false
            }
            return normalizedObjectiveCodeKey(objective.code) == key
        }
    }

    private func deduplicateLearningObjectivesByCode(_ objectives: [LearningObjective]) -> [LearningObjective] {
        var byCode: [String: LearningObjective] = [:]
        var duplicateKeys: Set<String> = []

        for objective in objectives {
            objective.code = normalizedObjectiveCode(objective.code)
            let key = normalizedObjectiveCodeKey(objective.code)
            guard key.isEmpty == false else { continue }
            if let existing = byCode[key] {
                duplicateKeys.insert(key)
                if shouldPreferObjective(objective, over: existing) {
                    byCode[key] = objective
                }
            } else {
                byCode[key] = objective
            }
        }

        if duplicateKeys.isEmpty == false {
            syncLogger.error("Detected duplicate LearningObjective code(s): \(duplicateKeys.sorted().joined(separator: ", "), privacy: .public). Keeping one record per code to avoid crashes.")
        }
        return Array(byCode.values)
    }

    private func objectiveDictionaryByCode(_ objectives: [LearningObjective]) -> [String: LearningObjective] {
        var map: [String: LearningObjective] = [:]
        for objective in deduplicateLearningObjectivesByCode(objectives) {
            map[normalizedObjectiveCodeKey(objective.code)] = objective
        }
        return map
    }

    private func shouldPreferObjective(_ candidate: LearningObjective, over existing: LearningObjective) -> Bool {
        if candidate.isArchived != existing.isArchived {
            return existing.isArchived && candidate.isArchived == false
        }
        if candidate.sortOrder != existing.sortOrder {
            return candidate.sortOrder < existing.sortOrder
        }
        if candidate.title.count != existing.title.count {
            return candidate.title.count > existing.title.count
        }
        return candidate.id.uuidString < existing.id.uuidString
    }

    private func rebuildProgressCaches(debounce: Bool = false) {
        if debounce {
            progressRebuildTask?.cancel()
            progressRebuildTask = Task { [weak self] in
                guard let self else { return }
                try? await Task.sleep(nanoseconds: self.progressRebuildDebounceNanoseconds)
                if Task.isCancelled { return }
                self.rebuildProgressCachesNow()
            }
            return
        }
        progressRebuildTask?.cancel()
        progressRebuildTask = nil
        rebuildProgressCachesNow()
    }

    private func rebuildProgressCachesNow() {
        var byStudentObjectiveID: [UUID: [UUID: Int]] = [:]
        var byStudentObjectiveCode: [UUID: [String: Int]] = [:]

        for student in students {
            var objectiveIDValues: [UUID: Int] = [:]
            var objectiveCodeValues: [String: Int] = [:]
            for progress in student.progressRecords {
                if let objectiveID = progress.objectiveId {
                    objectiveIDValues[objectiveID] = progress.value
                }
                objectiveCodeValues[progress.objectiveCode] = progress.value
            }
            byStudentObjectiveID[student.id] = objectiveIDValues
            byStudentObjectiveCode[student.id] = objectiveCodeValues
        }

        progressValuesByStudentObjectiveID = byStudentObjectiveID
        progressValuesByStudentObjectiveCode = byStudentObjectiveCode

        var aggregateByStudentID: [UUID: [UUID: Int]] = [:]
        var overallByStudentID: [UUID: Int] = [:]
        var cohortOverallTotal = 0

        for student in students {
            var memo: [UUID: Int] = [:]
            for objective in learningObjectives {
                _ = objectivePercentage(studentID: student.id, objective: objective, memo: &memo)
            }
            aggregateByStudentID[student.id] = memo

            let overall: Int
            if rootCategoryObjectivesCache.isEmpty {
                overall = 0
            } else {
                let total = rootCategoryObjectivesCache.reduce(0) { partial, root in
                    partial + (memo[root.id] ?? 0)
                }
                overall = total / rootCategoryObjectivesCache.count
            }
            overallByStudentID[student.id] = overall
            cohortOverallTotal += overall
        }

        objectiveAggregateByStudentID = aggregateByStudentID
        studentOverallProgressByID = overallByStudentID
        cohortOverallProgressCache = students.isEmpty ? 0 : (cohortOverallTotal / students.count)

        if hasLoaded {
            scheduleSnapshotPersistence()
        }
    }

    private func objectivePercentage(
        studentID: UUID,
        objective: LearningObjective,
        memo: inout [UUID: Int]
    ) -> Int {
        if let cached = memo[objective.id] {
            return cached
        }

        let children = objectiveChildrenByParentID[objective.id] ?? []
        if children.isEmpty {
            let value: Int
            if let objectiveValue = progressValuesByStudentObjectiveID[studentID]?[objective.id] {
                value = objectiveValue
            } else {
                value = progressValuesByStudentObjectiveCode[studentID]?[objective.code] ?? 0
            }
            memo[objective.id] = value
            return value
        }

        var total = 0
        for child in children {
            total += objectivePercentage(studentID: studentID, objective: child, memo: &memo)
        }
        let value = total / children.count
        memo[objective.id] = value
        return value
    }

    private func recordProtectionKey(recordType: String, recordName: String) -> String {
        "\(recordType)|\(recordName)"
    }

    private func markRecordRecentlyWritten(recordType: String, recordName: String) {
        recentLocalWriteRecordKeys[recordProtectionKey(recordType: recordType, recordName: recordName)] = Date()
    }

    private func unmarkRecordRecentlyWritten(recordType: String, recordName: String) {
        recentLocalWriteRecordKeys.removeValue(
            forKey: recordProtectionKey(recordType: recordType, recordName: recordName)
        )
    }

    private func isRecentlyWritten(recordType: String, recordName: String) -> Bool {
        pruneExpiredRecentWriteMarkers()
        let key = recordProtectionKey(recordType: recordType, recordName: recordName)
        guard let date = recentLocalWriteRecordKeys[key] else { return false }
        return Date().timeIntervalSince(date) < reconcileDeletionGraceInterval
    }

    private func pruneExpiredRecentWriteMarkers() {
        let now = Date()
        recentLocalWriteRecordKeys = recentLocalWriteRecordKeys.filter { _, timestamp in
            now.timeIntervalSince(timestamp) < reconcileDeletionGraceInterval
        }
    }

    private func dictionaryByRecordName<T>(
        items: [T],
        recordNameLookup: [UUID: String]
    ) -> [String: T] where T: Identifiable, T.ID == UUID {
        var map: [String: T] = [:]
        for item in items {
            let recordName = recordNameLookup[item.id] ?? item.id.uuidString
            map[recordName] = item
        }
        return map
    }

    private func mergeFetchedGroups(_ fetched: [CohortGroup]) {
        let fetchedByID = Dictionary(uniqueKeysWithValues: fetched.map { ($0.id, $0) })
        for existing in groups {
            guard let incoming = fetchedByID[existing.id] else { continue }
            existing.name = incoming.name
            existing.colorHex = incoming.colorHex
        }
        for incoming in fetched where groups.contains(where: { $0.id == incoming.id }) == false {
            groups.append(incoming)
        }
        groups.removeAll { fetchedByID[$0.id] == nil }
        groups.sort { $0.name < $1.name }
        rebuildGroupMembershipCaches()
    }

    private func mergeFetchedDomains(_ fetched: [Domain]) {
        let fetchedByID = Dictionary(uniqueKeysWithValues: fetched.map { ($0.id, $0) })
        for existing in domains {
            guard let incoming = fetchedByID[existing.id] else { continue }
            existing.name = incoming.name
            existing.colorHex = incoming.colorHex
            existing.overallMode = incoming.overallMode
        }
        for incoming in fetched where domains.contains(where: { $0.id == incoming.id }) == false {
            domains.append(incoming)
        }
        domains.removeAll { fetchedByID[$0.id] == nil }
        domains.sort { $0.name < $1.name }
    }

    private func mergeFetchedCategoryLabels(_ fetched: [CategoryLabel]) {
        let fetchedByKey = Dictionary(uniqueKeysWithValues: fetched.map { ($0.key, $0) })
        let fetchedKeys = Set(fetchedByKey.keys)
        for existing in categoryLabels {
            guard let incoming = fetchedByKey[existing.key] else { continue }
            existing.title = incoming.title
        }
        for incoming in fetched where categoryLabels.contains(where: { $0.key == incoming.key }) == false {
            categoryLabels.append(incoming)
        }
        categoryLabels.removeAll { fetchedByKey[$0.key] == nil }
        categoryLabelRecordNameByCode = categoryLabelRecordNameByCode.filter { fetchedKeys.contains($0.key) }
        categoryLabels.sort { $0.key < $1.key }
    }

    // MARK: - Live CloudKit Updates

    private func startLiveSyncIfNeeded() {
        guard syncCoordinator == nil else {
            syncLogger.debug("Sync coordinator already exists, skipping start")
            return
        }
        // Preview mode does not initialize cohortRecordID; only start after a real load.
        guard hasLoaded else {
            syncLogger.debug("Data not loaded yet, skipping sync coordinator start")
            return
        }
        guard cohortRecordID != nil else {
            syncLogger.debug("Cohort record ID unavailable, skipping sync coordinator start")
            return
        }
        syncLogger.info("Creating and starting CloudKitSyncCoordinator")
        syncCoordinator = CloudKitSyncCoordinator(store: self, service: service)
        syncCoordinator?.start()
        syncLogger.info("CloudKitSyncCoordinator started successfully")
    }

    private let syncLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "VisualTrackerApp",
        category: "CloudKitSync"
    )
    
    func performIncrementalSync() async {
        guard hasLoaded else {
            syncLogger.debug("Skipping incremental sync: not loaded yet")
            return
        }
        guard let cohortRecordID else {
            syncLogger.debug("Skipping incremental sync: no cohortRecordID")
            return
        }

        // Move cursor to the start of this sync window to avoid missing writes that happen mid-sync.
        let syncWindowStart = Date()
        let previousSync = lastSyncDate
        
        syncLogger.info("Starting incremental sync. Last sync: \(previousSync, privacy: .public)")

        let cohortRef = CKRecord.Reference(recordID: cohortRecordID, action: .none)
        let updatedAfter = previousSync.addingTimeInterval(-2) as NSDate

        do {
            // Keep group/domain instances stable by upserting in-place.
            // Note: We use 'updatedAt' (custom queryable field) instead of 'modificationDate' (system field not queryable)
            let groupPredicate = NSPredicate(format: "cohortRef == %@ AND updatedAt >= %@", cohortRef, updatedAfter)
            let domainPredicate = NSPredicate(format: "cohortRef == %@ AND updatedAt >= %@", cohortRef, updatedAfter)
            let labelPredicate = NSPredicate(format: "cohortRef == %@ AND updatedAt >= %@", cohortRef, updatedAfter)
            let objectivePredicate = NSPredicate(format: "cohortRef == %@ AND updatedAt >= %@", cohortRef, updatedAfter)
            let studentPredicate = NSPredicate(format: "cohortRef == %@ AND updatedAt >= %@", cohortRef, updatedAfter)
            let membershipPredicate = NSPredicate(format: "cohortRef == %@ AND updatedAt >= %@", cohortRef, updatedAfter)
            let progressPredicate = NSPredicate(format: "cohortRef == %@ AND updatedAt >= %@", cohortRef, updatedAfter)
            let customPropPredicate = NSPredicate(format: "cohortRef == %@ AND updatedAt >= %@", cohortRef, updatedAfter)
            let expertiseCheckScorePredicate = NSPredicate(format: "cohortRef == %@ AND updatedAt >= %@", cohortRef, updatedAfter)

            async let groupsChanged = service.queryRecords(
                ofType: RecordType.cohortGroup,
                predicate: groupPredicate
            )
            async let domainsChanged = service.queryRecords(
                ofType: RecordType.domain,
                predicate: domainPredicate
            )
            async let labelsChanged = service.queryRecords(
                ofType: RecordType.categoryLabel,
                predicate: labelPredicate
            )
            async let objectivesChanged = service.queryRecords(
                ofType: RecordType.learningObjective,
                predicate: objectivePredicate
            )
            async let studentsChanged = service.queryRecords(
                ofType: RecordType.student,
                predicate: studentPredicate
            )
            async let membershipsChanged = service.queryRecords(
                ofType: RecordType.studentGroupMembership,
                predicate: membershipPredicate
            )
            async let progressChanged = service.queryRecords(
                ofType: RecordType.objectiveProgress,
                predicate: progressPredicate
            )
            async let customPropsChanged = service.queryRecords(
                ofType: RecordType.studentCustomProperty,
                predicate: customPropPredicate
            )
            async let expertiseCheckScoresChanged = service.queryRecords(
                ofType: RecordType.expertiseCheckObjectiveScore,
                predicate: expertiseCheckScorePredicate
            )

            let (
                groupRecords,
                domainRecords,
                labelRecords,
                objectiveRecords,
                studentRecords,
                membershipRecords,
                progressRecords,
                customPropRecords,
                expertiseCheckScoreRecords
            ) = try await (
                groupsChanged,
                domainsChanged,
                labelsChanged,
                objectivesChanged,
                studentsChanged,
                membershipsChanged,
                progressChanged,
                customPropsChanged,
                expertiseCheckScoresChanged
            )

            let totalChanges = groupRecords.count + domainRecords.count + labelRecords.count +
                              objectiveRecords.count + studentRecords.count + membershipRecords.count +
                              progressRecords.count + customPropRecords.count + expertiseCheckScoreRecords.count
            
            if totalChanges == 0 {
                syncLogger.info("Incremental sync: no changes found since last sync")
                lastSyncDate = syncWindowStart
                isShowingStaleSnapshot = false
                isOfflineUsingSnapshot = false
                return
            }
            
            syncLogger.info("Incremental sync found changes: groups=\(groupRecords.count, privacy: .public) domains=\(domainRecords.count, privacy: .public) labels=\(labelRecords.count, privacy: .public) objectives=\(objectiveRecords.count, privacy: .public) students=\(studentRecords.count, privacy: .public) memberships=\(membershipRecords.count, privacy: .public) progress=\(progressRecords.count, privacy: .public) customProps=\(customPropRecords.count, privacy: .public) expertiseCheckScores=\(expertiseCheckScoreRecords.count, privacy: .public)")

            // Upsert order matters: groups/domains first, then students, then child records.
            isApplyingRemoteChanges = true
            defer { isApplyingRemoteChanges = false }
            if groupRecords.isEmpty == false {
                syncLogger.info("Applying \(groupRecords.count, privacy: .public) group changes")
                applyGroupChanges(groupRecords)
            }
            if domainRecords.isEmpty == false {
                syncLogger.info("Applying \(domainRecords.count, privacy: .public) domain changes")
                applyDomainChanges(domainRecords)
            }
            if labelRecords.isEmpty == false {
                syncLogger.info("Applying \(labelRecords.count, privacy: .public) category label changes")
                applyCategoryLabelChanges(labelRecords)
            }
            if objectiveRecords.isEmpty == false {
                syncLogger.info("Applying \(objectiveRecords.count, privacy: .public) learning objective changes")
                applyLearningObjectiveChanges(objectiveRecords)
            }
            if studentRecords.isEmpty == false {
                syncLogger.info("Applying \(studentRecords.count, privacy: .public) student changes")
                applyStudentChanges(studentRecords)
            }
            if membershipRecords.isEmpty == false {
                syncLogger.info("Applying \(membershipRecords.count, privacy: .public) membership changes")
                applyMembershipChanges(membershipRecords)
            }
            if progressRecords.isEmpty == false {
                syncLogger.info("Applying \(progressRecords.count, privacy: .public) progress changes")
                applyProgressChanges(progressRecords)
            }
            if customPropRecords.isEmpty == false {
                syncLogger.info("Applying \(customPropRecords.count, privacy: .public) custom property changes")
                applyCustomPropertyChanges(customPropRecords)
            }
            if expertiseCheckScoreRecords.isEmpty == false {
                syncLogger.info("Applying \(expertiseCheckScoreRecords.count, privacy: .public) expertise check objective score changes")
                applyExpertiseCheckObjectiveScoreChanges(expertiseCheckScoreRecords)
            }

            // Advance cursor
            lastSyncDate = syncWindowStart
            isShowingStaleSnapshot = false
            isOfflineUsingSnapshot = false
            scheduleSnapshotPersistence()
            syncLogger.info("Incremental sync complete. Applied \(totalChanges, privacy: .public) total changes. New sync date: \(syncWindowStart, privacy: .public)")
        } catch {
            // Keep it quiet; polling / next activation will retry.
            // Don't overwrite existing user-facing error unless something else does.
            if hasCachedSnapshotData {
                isOfflineUsingSnapshot = true
                isShowingStaleSnapshot = true
            }
            syncLogger.error("Incremental sync failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func fetchAndApplyRemoteRecord(recordType: String, recordID: CKRecord.ID) async {
        do {
            let record = try await service.fetchRecord(with: recordID)
            isApplyingRemoteChanges = true
            defer { isApplyingRemoteChanges = false }
            applyRemoteUpsert(recordType: recordType, record: record)
        } catch {
            // If the record can't be fetched (e.g., deleted quickly), allow reconcile/poll to handle eventual consistency.
        }
    }

    func applyRemoteDeletion(recordType: String, recordID: CKRecord.ID) {
        isApplyingRemoteChanges = true
        defer { isApplyingRemoteChanges = false }
        switch recordType {
        case RecordType.cohortGroup:
            deleteGroupByRecordID(recordID)
        case RecordType.domain:
            deleteDomainByRecordID(recordID)
        case RecordType.student:
            deleteStudentByRecordID(recordID)
        case RecordType.categoryLabel:
            deleteCategoryLabelByRecordID(recordID)
        case RecordType.learningObjective:
            deleteLearningObjectiveByRecordID(recordID)
        case RecordType.studentGroupMembership:
            deleteMembershipByRecordID(recordID)
        case RecordType.objectiveProgress:
            deleteProgressByRecordID(recordID)
        case RecordType.studentCustomProperty:
            deleteCustomPropertyByRecordID(recordID)
        case RecordType.expertiseCheckObjectiveScore:
            deleteExpertiseCheckObjectiveScoreByRecordID(recordID)
        default:
            break
        }
    }

    func reconcileWithServer() async {
        guard hasLoaded else {
            syncLogger.debug("Skipping reconcile: not loaded yet")
            return
        }
        guard let cohortRecordID else {
            syncLogger.debug("Skipping reconcile: no cohortRecordID")
            return
        }

        syncLogger.info("Starting full reconciliation (additions + updates + deletions)")
        
        let cohortRef = CKRecord.Reference(recordID: cohortRecordID, action: .none)
        let predicate = NSPredicate(format: "cohortRef == %@", cohortRef)

        do {
            // Fetch all records (not just IDs) so we can add missing ones
            async let groupRecords = service.queryRecords(ofType: RecordType.cohortGroup, predicate: predicate)
            async let domainRecords = service.queryRecords(ofType: RecordType.domain, predicate: predicate)
            async let objectiveRecords = service.queryRecords(ofType: RecordType.learningObjective, predicate: predicate)
            async let studentRecords = service.queryRecords(ofType: RecordType.student, predicate: predicate)
            async let membershipRecords = service.queryRecords(ofType: RecordType.studentGroupMembership, predicate: predicate)
            async let labelRecords = service.queryRecords(ofType: RecordType.categoryLabel, predicate: predicate)
            async let expertiseCheckScoreRecords = service.queryRecords(ofType: RecordType.expertiseCheckObjectiveScore, predicate: predicate)

            let (
                remoteGroups,
                remoteDomains,
                remoteObjectives,
                remoteStudents,
                remoteMemberships,
                remoteLabels,
                remoteExpertiseCheckScores
            ) = try await (
                groupRecords,
                domainRecords,
                objectiveRecords,
                studentRecords,
                membershipRecords,
                labelRecords,
                expertiseCheckScoreRecords
            )

            syncLogger.info("Reconciliation fetched: groups=\(remoteGroups.count, privacy: .public) domains=\(remoteDomains.count, privacy: .public) objectives=\(remoteObjectives.count, privacy: .public) students=\(remoteStudents.count, privacy: .public) memberships=\(remoteMemberships.count, privacy: .public) labels=\(remoteLabels.count, privacy: .public) expertiseCheckScores=\(remoteExpertiseCheckScores.count, privacy: .public)")

            // Apply ALL remote records - handles adds AND updates
            isApplyingRemoteChanges = true
            defer { isApplyingRemoteChanges = false }
            if remoteGroups.isEmpty == false {
                applyGroupChanges(remoteGroups)
            }
            if remoteDomains.isEmpty == false {
                applyDomainChanges(remoteDomains)
            }
            if remoteObjectives.isEmpty == false {
                applyLearningObjectiveChanges(remoteObjectives)
            }
            if remoteLabels.isEmpty == false {
                applyCategoryLabelChanges(remoteLabels)
            }
            if remoteStudents.isEmpty == false {
                applyStudentChanges(remoteStudents)
            }
            if remoteMemberships.isEmpty == false {
                applyMembershipChanges(remoteMemberships)
            }
            if remoteExpertiseCheckScores.isEmpty == false {
                applyExpertiseCheckObjectiveScoreChanges(remoteExpertiseCheckScores)
            }

            // Remove locally-held records that no longer exist on server (deletions)
            let remoteGroupIDs = Set(remoteGroups.map { $0.recordID.recordName })
            let localGroupIDs = Set(groupRecordNameByID.values)
            for recordName in localGroupIDs.subtracting(remoteGroupIDs) {
                guard isRecentlyWritten(recordType: RecordType.cohortGroup, recordName: recordName) == false else { continue }
                guard unconfirmedGroupRecordNames.contains(recordName) == false else { continue }
                deleteGroupByRecordID(CKRecord.ID(recordName: recordName))
            }

            let remoteDomainIDs = Set(remoteDomains.map { $0.recordID.recordName })
            let localDomainIDs = Set(domainRecordNameByID.values)
            for recordName in localDomainIDs.subtracting(remoteDomainIDs) {
                guard isRecentlyWritten(recordType: RecordType.domain, recordName: recordName) == false else { continue }
                guard unconfirmedDomainRecordNames.contains(recordName) == false else { continue }
                deleteDomainByRecordID(CKRecord.ID(recordName: recordName))
            }

            let remoteStudentIDs = Set(remoteStudents.map { $0.recordID.recordName })
            let localStudentIDs = Set(studentRecordNameByID.values)
            for recordName in localStudentIDs.subtracting(remoteStudentIDs) {
                guard isRecentlyWritten(recordType: RecordType.student, recordName: recordName) == false else { continue }
                deleteStudentByRecordID(CKRecord.ID(recordName: recordName))
            }

            let remoteObjectiveIDs = Set(remoteObjectives.map { $0.recordID.recordName })
            let localObjectiveIDs = Set(learningObjectiveRecordNameByID.values)
            for recordName in localObjectiveIDs.subtracting(remoteObjectiveIDs) {
                guard isRecentlyWritten(recordType: RecordType.learningObjective, recordName: recordName) == false else { continue }
                guard unconfirmedLearningObjectiveRecordNames.contains(recordName) == false else { continue }
                deleteLearningObjectiveByRecordID(CKRecord.ID(recordName: recordName))
            }

            let remoteMembershipIDs = Set(remoteMemberships.map { $0.recordID.recordName })
            let localMembershipIDs = Set(membershipRecordNameByID.values)
            for recordName in localMembershipIDs.subtracting(remoteMembershipIDs) {
                guard isRecentlyWritten(recordType: RecordType.studentGroupMembership, recordName: recordName) == false else { continue }
                deleteMembershipByRecordID(CKRecord.ID(recordName: recordName))
            }

            let remoteLabelIDs = Set(remoteLabels.map { $0.recordID.recordName })
            let localLabelIDs = Set(categoryLabels.map { $0.key })
            for key in localLabelIDs.subtracting(remoteLabelIDs) {
                guard isRecentlyWritten(recordType: RecordType.categoryLabel, recordName: key) == false else { continue }
                guard unconfirmedCategoryLabelRecordNames.contains(key) == false else { continue }
                deleteCategoryLabelByRecordID(CKRecord.ID(recordName: key))
            }

            let remoteExpertiseCheckScoreIDs = Set(remoteExpertiseCheckScores.map { $0.recordID.recordName })
            let localExpertiseCheckScoreIDs = Set(expertiseCheckScoreRecordNameByID.values)
            for recordName in localExpertiseCheckScoreIDs.subtracting(remoteExpertiseCheckScoreIDs) {
                guard isRecentlyWritten(recordType: RecordType.expertiseCheckObjectiveScore, recordName: recordName) == false else { continue }
                deleteExpertiseCheckObjectiveScoreByRecordID(CKRecord.ID(recordName: recordName))
            }

            // Progress and custom properties are only reconciled for loaded students
            // (We don't want to fetch all progress for all students - that's done on-demand)
            await reconcileProgressForLoadedStudents(cohortRef: cohortRef)
            await reconcileCustomPropertiesForLoadedStudents(cohortRef: cohortRef)

            isShowingStaleSnapshot = false
            isOfflineUsingSnapshot = false
            scheduleSnapshotPersistence()
            syncLogger.info("Full reconciliation complete")
        } catch {
            if hasCachedSnapshotData {
                isOfflineUsingSnapshot = true
                isShowingStaleSnapshot = true
            }
            syncLogger.error("Full reconciliation failed: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    private func reconcileProgressForLoadedStudents(cohortRef: CKRecord.Reference) async {
        guard progressLoadedStudentIDs.isEmpty == false else { return }
        
        do {
            let predicate = NSPredicate(format: "cohortRef == %@", cohortRef)
            let remoteProgressRecords = try await service.queryRecords(ofType: RecordType.objectiveProgress, predicate: predicate)

            let loadedStudentRecordNames = Set(progressLoadedStudentIDs.map { studentID in
                studentRecordNameByID[studentID] ?? studentID.uuidString
            })

            // Apply ALL remote progress records for loaded students (handles adds AND updates)
            let relevantRecords = remoteProgressRecords.filter { record in
                guard let studentRef = studentReference(from: record) else { return false }
                return loadedStudentRecordNames.contains(studentRef.recordID.recordName)
            }
            if relevantRecords.isEmpty == false {
                syncLogger.info("Applying \(relevantRecords.count, privacy: .public) progress records (adds + updates)")
                applyProgressChanges(relevantRecords)
            }
            
            // Remove deleted progress records
            let remoteProgressIDs = Set(remoteProgressRecords.map { $0.recordID.recordName })
            let localProgressIDs = Set(progressRecordNameByID.values)
            let deletedProgressIDs = localProgressIDs.subtracting(remoteProgressIDs)
            for recordName in deletedProgressIDs {
                guard isRecentlyWritten(recordType: RecordType.objectiveProgress, recordName: recordName) == false else { continue }
                deleteProgressByRecordID(CKRecord.ID(recordName: recordName))
            }
        } catch {
            syncLogger.error("Progress reconciliation failed: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    private func reconcileCustomPropertiesForLoadedStudents(cohortRef: CKRecord.Reference) async {
        guard customPropertiesLoadedStudentIDs.isEmpty == false else { return }
        
        do {
            let predicate = NSPredicate(format: "cohortRef == %@", cohortRef)
            let remoteCustomPropRecords = try await service.queryRecords(ofType: RecordType.studentCustomProperty, predicate: predicate)

            let loadedStudentRecordNames = Set(customPropertiesLoadedStudentIDs.map { studentID in
                studentRecordNameByID[studentID] ?? studentID.uuidString
            })

            // Apply ALL remote custom property records for loaded students (handles adds AND updates)
            let relevantRecords = remoteCustomPropRecords.filter { record in
                guard let studentRef = studentReference(from: record) else { return false }
                return loadedStudentRecordNames.contains(studentRef.recordID.recordName)
            }
            if relevantRecords.isEmpty == false {
                syncLogger.info("Applying \(relevantRecords.count, privacy: .public) custom property records (adds + updates)")
                applyCustomPropertyChanges(relevantRecords)
            }
            
            // Remove deleted custom property records
            let remoteCustomPropIDs = Set(remoteCustomPropRecords.map { $0.recordID.recordName })
            let localCustomPropIDs = Set(customPropertyRecordNameByID.values)
            let deletedCustomPropIDs = localCustomPropIDs.subtracting(remoteCustomPropIDs)
            for recordName in deletedCustomPropIDs {
                guard isRecentlyWritten(recordType: RecordType.studentCustomProperty, recordName: recordName) == false else { continue }
                deleteCustomPropertyByRecordID(CKRecord.ID(recordName: recordName))
            }
        } catch {
            syncLogger.error("Custom property reconciliation failed: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    // Keep the old function name as an alias for backwards compatibility
    func reconcileDeletionsFromServer() async {
        await reconcileWithServer()
    }

    private func applyRemoteUpsert(recordType: String, record: CKRecord) {
        isApplyingRemoteChanges = true
        defer { isApplyingRemoteChanges = false }
        switch recordType {
        case RecordType.cohortGroup:
            applyGroupChanges([record])
        case RecordType.domain:
            applyDomainChanges([record])
        case RecordType.categoryLabel:
            applyCategoryLabelChanges([record])
        case RecordType.learningObjective:
            applyLearningObjectiveChanges([record])
        case RecordType.student:
            applyStudentChanges([record])
        case RecordType.studentGroupMembership:
            applyMembershipChanges([record])
        case RecordType.objectiveProgress:
            applyProgressChanges([record])
        case RecordType.studentCustomProperty:
            applyCustomPropertyChanges([record])
        case RecordType.expertiseCheckObjectiveScore:
            applyExpertiseCheckObjectiveScoreChanges([record])
        default:
            break
        }
    }

    private func applyGroupChanges(_ records: [CKRecord]) {
        guard records.isEmpty == false else { return }

        // Notify SwiftUI that changes are coming
        objectWillChange.send()

        for record in records {
            let name = record[Field.name] as? String ?? "Untitled"
            let colorHex = record[Field.colorHex] as? String
            let uuid = resolvedStableID(forRecordName: record.recordID.recordName, lookup: groupRecordNameByID)

            if let existing = groups.first(where: { $0.id == uuid }) {
                syncLogger.info("Updating existing group: \(name, privacy: .public)")
                existing.name = name
                existing.colorHex = colorHex
            } else {
                syncLogger.info("Adding new group: \(name, privacy: .public)")
                let g = CohortGroup(name: name, colorHex: colorHex)
                g.id = uuid
                groups.append(g)
            }

            groupRecordNameByID[uuid] = record.recordID.recordName
            pendingGroupCreateIDs.remove(uuid)
            unconfirmedGroupRecordNames.remove(record.recordID.recordName)
            unmarkRecordRecentlyWritten(recordType: RecordType.cohortGroup, recordName: record.recordID.recordName)
        }

        groups.sort { $0.name < $1.name }
        rebuildGroupMembershipCaches()
    }

    private func applyDomainChanges(_ records: [CKRecord]) {
        guard records.isEmpty == false else { return }

        // Notify SwiftUI that changes are coming
        objectWillChange.send()

        for record in records {
            let name = record[Field.name] as? String ?? "Untitled"
            let colorHex = record[Field.colorHex] as? String
            let overallModeRaw = (record[Field.overallMode] as? String) ?? ExpertiseCheckOverallMode.computed.rawValue
            let overallMode = ExpertiseCheckOverallMode(rawValue: overallModeRaw) ?? .computed
            let uuid = resolvedStableID(forRecordName: record.recordID.recordName, lookup: domainRecordNameByID)

            if let existing = domains.first(where: { $0.id == uuid }) {
                syncLogger.info("Updating existing domain: \(name, privacy: .public)")
                existing.name = name
                existing.colorHex = colorHex
                existing.overallMode = overallMode
            } else {
                syncLogger.info("Adding new domain: \(name, privacy: .public)")
                let d = Domain(name: name, colorHex: colorHex, overallMode: overallMode)
                d.id = uuid
                domains.append(d)
            }

            domainRecordNameByID[uuid] = record.recordID.recordName
            pendingDomainCreateIDs.remove(uuid)
            unconfirmedDomainRecordNames.remove(record.recordID.recordName)
        }

        domains.sort { $0.name < $1.name }
    }

    private func applyCategoryLabelChanges(_ records: [CKRecord]) {
        guard records.isEmpty == false else { return }

        // Notify SwiftUI that changes are coming
        objectWillChange.send()

        for record in records {
            let code = record[Field.code] as? String ?? (record[Field.key] as? String ?? record.recordID.recordName)
            let title = record[Field.title] as? String ?? code

            if let existing = categoryLabels.first(where: { $0.key == code }) {
                syncLogger.info("Updating existing category label: \(code, privacy: .public)")
                existing.title = title
            } else {
                syncLogger.info("Adding new category label: \(code, privacy: .public)")
                categoryLabels.append(CategoryLabel(code: code, title: title))
            }
            pendingCategoryLabelCreateKeys.remove(code)
            unconfirmedCategoryLabelRecordNames.remove(record.recordID.recordName)
            unmarkRecordRecentlyWritten(recordType: RecordType.categoryLabel, recordName: record.recordID.recordName)
        }

        categoryLabels.sort { $0.key < $1.key }
    }

    private func applyLearningObjectiveChanges(_ records: [CKRecord]) {
        guard records.isEmpty == false else { return }
        objectWillChange.send()

        var mergedByRecordName: [String: CKRecord] = [:]
        for objective in allLearningObjectives {
            let recordName = learningObjectiveRecordNameByID[objective.id] ?? objective.id.uuidString
            let recordID = CKRecord.ID(recordName: recordName)
            let record = CKRecord(recordType: RecordType.learningObjective, recordID: recordID)
            record[Field.code] = objective.code
            record[Field.title] = objective.title
            record[Field.objectiveDescription] = objective.objectiveDescription
            record[Field.isQuantitative] = objective.isQuantitative ? 1 : 0
            record[Field.parentCode] = objective.parentCode
            record[Field.sortOrder] = objective.sortOrder
            record[Field.isArchived] = objective.isArchived ? 1 : 0
            mergedByRecordName[recordName] = record
        }
        for record in records {
            mergedByRecordName[record.recordID.recordName] = record
            let objectiveID = resolvedStableID(
                forRecordName: record.recordID.recordName,
                lookup: learningObjectiveRecordNameByID
            )
            pendingLearningObjectiveCreateIDs.remove(objectiveID)
            unconfirmedLearningObjectiveRecordNames.remove(record.recordID.recordName)
            unmarkRecordRecentlyWritten(recordType: RecordType.learningObjective, recordName: record.recordID.recordName)
        }

        let remapped = mapLearningObjectives(from: Array(mergedByRecordName.values))
        setLearningObjectives(remapped)
    }

    private func applyMembershipChanges(_ records: [CKRecord]) {
        guard records.isEmpty == false else { return }
        objectWillChange.send()

        let studentMap = dictionaryByRecordName(items: students, recordNameLookup: studentRecordNameByID)
        let groupMap = dictionaryByRecordName(items: groups, recordNameLookup: groupRecordNameByID)

        for record in records {
            if let mapped = mapMembership(from: record, studentMap: studentMap, groupMap: groupMap) {
                memberships.removeAll { $0.id == mapped.id }
                memberships.append(mapped)
                unmarkRecordRecentlyWritten(recordType: RecordType.studentGroupMembership, recordName: record.recordID.recordName)
            }
        }

        memberships = uniqueMemberships(memberships)
        refreshLegacyGroupConvenience()
        rebuildGroupMembershipCaches()
    }

    private func applyStudentChanges(_ records: [CKRecord]) {
        guard records.isEmpty == false else { return }

        let groupByRecordName: [String: CohortGroup] = {
            var map: [String: CohortGroup] = [:]
            for group in groups {
                let rn = groupRecordNameByID[group.id] ?? group.id.uuidString
                map[rn] = group
            }
            return map
        }()

        let domainByRecordName: [String: Domain] = {
            var map: [String: Domain] = [:]
            for domain in domains {
                let rn = domainRecordNameByID[domain.id] ?? domain.id.uuidString
                map[rn] = domain
            }
            return map
        }()

        // Notify SwiftUI that changes are coming
        objectWillChange.send()

        for record in records {
            let uuid = resolvedStableID(forRecordName: record.recordID.recordName, lookup: studentRecordNameByID)

            let name = record[Field.name] as? String ?? "Unnamed"
            let sessionRaw = record[Field.session] as? String ?? Session.morning.rawValue
            let session = Session(rawValue: sessionRaw) ?? .morning

            let group = (record[Field.group] as? CKRecord.Reference).flatMap { groupByRecordName[$0.recordID.recordName] }
            let domain = (record[Field.domain] as? CKRecord.Reference).flatMap { domainByRecordName[$0.recordID.recordName] }

            let createdAt = (record[Field.createdAt] as? Date) ?? Date()

            if let existing = students.first(where: { $0.id == uuid }) {
                syncLogger.info("Updating existing student: \(name, privacy: .public) (id: \(uuid.uuidString.prefix(8), privacy: .public))")
                existing.name = name
                existing.session = session
                existing.group = group
                existing.domain = domain
                existing.createdAt = createdAt
            } else {
                syncLogger.info("Adding new student: \(name, privacy: .public) (id: \(uuid.uuidString.prefix(8), privacy: .public))")
                let s = Student(name: name, group: group, session: session, domain: domain)
                s.id = uuid
                s.createdAt = createdAt
                students.append(s)
            }

            studentRecordNameByID[uuid] = record.recordID.recordName
            progressLoadedStudentIDs.insert(uuid)
            unmarkRecordRecentlyWritten(recordType: RecordType.student, recordName: record.recordID.recordName)
        }

        students.sort { $0.createdAt < $1.createdAt }
        refreshLegacyGroupConvenience()
        rebuildGroupMembershipCaches()
        rebuildProgressCaches(debounce: true)
        syncLogger.info("Students array now has \(self.students.count, privacy: .public) students")
    }

    private func applyProgressChanges(_ records: [CKRecord]) {
        guard records.isEmpty == false else { return }

        // Notify SwiftUI that changes are coming
        objectWillChange.send()

        let studentIDByRecordName: [String: UUID] = {
            var map: [String: UUID] = [:]
            for (id, recordName) in studentRecordNameByID {
                map[recordName] = id
            }
            return map
        }()

        var recordsByStudentID: [UUID: [CKRecord]] = [:]
        for record in records {
            guard let studentRef = studentReference(from: record) else { continue }
            guard let studentID = studentIDByRecordName[studentRef.recordID.recordName] else { continue }
            recordsByStudentID[studentID, default: []].append(record)
        }

        for (studentID, studentRecords) in recordsByStudentID {
            guard let student = students.first(where: { $0.id == studentID }) else { continue }

            guard progressLoadedStudentIDs.contains(student.id) else {
                syncLogger.debug("Skipping progress update for student \(studentID.uuidString.prefix(8), privacy: .public) - progress not loaded")
                continue
            }

            for record in studentRecords {
                let objectiveRef = record[Field.objectiveRef] as? CKRecord.Reference
                let objectiveId: UUID? = objectiveRef.flatMap { reference in
                    self.objectiveID(forRecordName: reference.recordID.recordName)
                }
                var objectiveCode = record[Field.objectiveCode] as? String ?? ""
                if objectiveCode.isEmpty, let objectiveId, let objective = objectiveByID(objectiveId) {
                    objectiveCode = objective.code
                }

                let canonicalValue = (record[Field.value] as? Int)
                    ?? (record[Field.value] as? NSNumber)?.intValue
                    ?? (record[Field.completionPercentage] as? Int)
                    ?? (record[Field.completionPercentage] as? NSNumber)?.intValue
                    ?? 0
                let notes = record[Field.notes] as? String ?? ""
                let lastUpdated = (record[Field.lastUpdated] as? Date) ?? Date()
                let statusRaw = record[Field.status] as? String
                let status = statusRaw.flatMap { ProgressStatus(rawValue: $0) } ?? ObjectiveProgress.calculateStatus(from: canonicalValue)

                let uuid = resolvedStableID(forRecordName: record.recordID.recordName, lookup: progressRecordNameByID)
                if let duplicate = student.progressRecords.first(where: { existing in
                    guard existing.id != uuid else { return false }
                    if let objectiveId {
                        return existing.objectiveId == objectiveId
                    }
                    return existing.objectiveCode == objectiveCode
                }) {
                    student.progressRecords.removeAll { $0.id == duplicate.id }
                    progressRecordNameByID.removeValue(forKey: duplicate.id)
                }

                if let existing = student.progressRecords.first(where: { $0.id == uuid }) {
                    syncLogger.info("Updating progress for \(objectiveCode, privacy: .public): \(canonicalValue, privacy: .public)%")
                    existing.objectiveId = objectiveId
                    existing.objectiveCode = objectiveCode
                    existing.updateCompletion(canonicalValue)
                    existing.notes = notes
                    existing.lastUpdated = lastUpdated
                    existing.status = status
                } else {
                    syncLogger.info("Adding new progress for \(objectiveCode, privacy: .public): \(canonicalValue, privacy: .public)%")
                    let p = ObjectiveProgress(
                        objectiveCode: objectiveCode,
                        completionPercentage: canonicalValue,
                        notes: notes,
                        objectiveId: objectiveId,
                        value: canonicalValue
                    )
                    p.id = uuid
                    p.student = student
                    p.notes = notes
                    p.lastUpdated = lastUpdated
                    p.status = status
                    student.progressRecords.append(p)
                }

                progressRecordNameByID[uuid] = record.recordID.recordName
                if let studentRef = studentReference(from: record) {
                    scheduleObjectiveRefMigrationIfNeeded(records: [record], studentRecordID: studentRef.recordID)
                }
                unmarkRecordRecentlyWritten(recordType: RecordType.objectiveProgress, recordName: record.recordID.recordName)
            }
            student.progressRecords = deduplicatedProgress(student.progressRecords).sorted { $0.objectiveCode < $1.objectiveCode }
        }
        rebuildProgressCaches(debounce: true)
    }

    private func applyCustomPropertyChanges(_ records: [CKRecord]) {
        guard records.isEmpty == false else { return }

        // Notify SwiftUI that changes are coming
        objectWillChange.send()

        let studentIDByRecordName: [String: UUID] = {
            var map: [String: UUID] = [:]
            for (id, recordName) in studentRecordNameByID {
                map[recordName] = id
            }
            return map
        }()

        for record in records {
            guard let studentRef = studentReference(from: record) else { continue }
            guard let studentID = studentIDByRecordName[studentRef.recordID.recordName] else { continue }
            guard let student = students.first(where: { $0.id == studentID }) else { continue }

            guard customPropertiesLoadedStudentIDs.contains(student.id) else {
                syncLogger.debug("Skipping custom property update for student \(studentID.uuidString.prefix(8), privacy: .public) - properties not loaded")
                continue
            }

            let key = record[Field.key] as? String ?? ""
            let value = record[Field.value] as? String ?? ""
            let sortOrder = (record[Field.sortOrder] as? Int)
                ?? (record[Field.sortOrder] as? NSNumber)?.intValue
                ?? 0

            let uuid = resolvedStableID(forRecordName: record.recordID.recordName, lookup: customPropertyRecordNameByID)

            if let existing = student.customProperties.first(where: { $0.id == uuid }) {
                syncLogger.info("Updating custom property: \(key, privacy: .public)")
                existing.key = key
                existing.value = value
                existing.sortOrder = sortOrder
            } else {
                syncLogger.info("Adding new custom property: \(key, privacy: .public)")
                let prop = StudentCustomProperty(key: key, value: value, sortOrder: sortOrder)
                prop.id = uuid
                prop.student = student
                student.customProperties.append(prop)
            }

            customPropertyRecordNameByID[uuid] = record.recordID.recordName
            student.customProperties.sort { $0.sortOrder < $1.sortOrder }
            unmarkRecordRecentlyWritten(recordType: RecordType.studentCustomProperty, recordName: record.recordID.recordName)
        }
    }

    private func applyExpertiseCheckObjectiveScoreChanges(_ records: [CKRecord]) {
        guard records.isEmpty == false else { return }
        objectWillChange.send()

        var merged: [ExpertiseCheckObjectiveScore] = expertiseCheckObjectiveScores
        var mergedByID: [UUID: Int] = [:]
        for (index, score) in merged.enumerated() {
            mergedByID[score.id] = index
        }

        for record in records {
            guard let incoming = mapExpertiseCheckObjectiveScore(from: record) else { continue }
            if let index = mergedByID[incoming.id] {
                let existing = merged[index]
                existing.expertiseCheckId = incoming.expertiseCheckId
                existing.objectiveId = incoming.objectiveId
                existing.objectiveCode = incoming.objectiveCode
                existing.value = incoming.value
                existing.statusRawValue = incoming.statusRawValue
                existing.createdAt = incoming.createdAt
                existing.updatedAt = incoming.updatedAt
                existing.lastEditedByDisplayName = incoming.lastEditedByDisplayName
            } else {
                merged.append(incoming)
                mergedByID[incoming.id] = merged.count - 1
            }
            expertiseCheckScoreRecordNameByID[incoming.id] = record.recordID.recordName
            unmarkRecordRecentlyWritten(recordType: RecordType.expertiseCheckObjectiveScore, recordName: record.recordID.recordName)
        }

        applyExpertiseCheckScores(merged)
    }

    private func deleteGroupByRecordID(_ recordID: CKRecord.ID) {
        let uuid = resolvedStableID(forRecordName: recordID.recordName, lookup: groupRecordNameByID)
        syncLogger.info("Deleting group with id: \(uuid.uuidString.prefix(8), privacy: .public)")
        objectWillChange.send()
        groups.removeAll { $0.id == uuid }
        groupRecordNameByID.removeValue(forKey: uuid)
        unmarkRecordRecentlyWritten(recordType: RecordType.cohortGroup, recordName: recordID.recordName)
        pendingGroupCreateIDs.remove(uuid)
        unconfirmedGroupRecordNames.remove(recordID.recordName)
        memberships.removeAll { $0.group?.id == uuid }
        let remainingMembershipIDs = Set(memberships.map(\.id))
        membershipRecordNameByID = membershipRecordNameByID.filter { remainingMembershipIDs.contains($0.key) }
        refreshLegacyGroupConvenience()
        rebuildGroupMembershipCaches()
    }

    private func deleteDomainByRecordID(_ recordID: CKRecord.ID) {
        let uuid = resolvedStableID(forRecordName: recordID.recordName, lookup: domainRecordNameByID)
        syncLogger.info("Deleting domain with id: \(uuid.uuidString.prefix(8), privacy: .public)")
        objectWillChange.send()
        domains.removeAll { $0.id == uuid }
        domainRecordNameByID.removeValue(forKey: uuid)
        unmarkRecordRecentlyWritten(recordType: RecordType.domain, recordName: recordID.recordName)
        pendingDomainCreateIDs.remove(uuid)
        unconfirmedDomainRecordNames.remove(recordID.recordName)
        let removedScoreIDs = expertiseCheckObjectiveScores
            .filter { $0.expertiseCheckId == uuid }
            .map(\.id)
        expertiseCheckObjectiveScores.removeAll { removedScoreIDs.contains($0.id) }
        for scoreID in removedScoreIDs {
            expertiseCheckScoreRecordNameByID.removeValue(forKey: scoreID)
        }
        rebuildExpertiseCheckScoreCaches()

        for student in students where student.domain?.id == uuid {
            student.domain = nil
        }
    }

    private func deleteStudentByRecordID(_ recordID: CKRecord.ID) {
        let uuid = resolvedStableID(forRecordName: recordID.recordName, lookup: studentRecordNameByID)
        syncLogger.info("Deleting student with id: \(uuid.uuidString.prefix(8), privacy: .public)")
        objectWillChange.send()
        students.removeAll { $0.id == uuid }
        studentRecordNameByID.removeValue(forKey: uuid)
        unmarkRecordRecentlyWritten(recordType: RecordType.student, recordName: recordID.recordName)
        memberships.removeAll { $0.student?.id == uuid }
        let remainingMembershipIDs = Set(memberships.map(\.id))
        membershipRecordNameByID = membershipRecordNameByID.filter { remainingMembershipIDs.contains($0.key) }
        progressLoadedStudentIDs.remove(uuid)
        customPropertiesLoadedStudentIDs.remove(uuid)
        rebuildGroupMembershipCaches()
        rebuildProgressCaches()
    }

    private func deleteCategoryLabelByRecordID(_ recordID: CKRecord.ID) {
        let key = categoryLabelRecordNameByCode.first(where: { $0.value == recordID.recordName })?.key ?? recordID.recordName
        syncLogger.info("Deleting category label: \(key, privacy: .public)")
        objectWillChange.send()
        categoryLabels.removeAll { $0.key == key || $0.code == key }
        categoryLabelRecordNameByCode.removeValue(forKey: key)
        unmarkRecordRecentlyWritten(recordType: RecordType.categoryLabel, recordName: recordID.recordName)
        pendingCategoryLabelCreateKeys.remove(key)
        unconfirmedCategoryLabelRecordNames.remove(recordID.recordName)
    }

    private func deleteLearningObjectiveByRecordID(_ recordID: CKRecord.ID) {
        let objectiveID = objectiveID(forRecordName: recordID.recordName)
        guard let objectiveID else { return }
        syncLogger.info("Deleting learning objective id: \(objectiveID.uuidString.prefix(8), privacy: .public)")
        objectWillChange.send()
        allLearningObjectives.removeAll { $0.id == objectiveID }
        learningObjectiveRecordNameByID.removeValue(forKey: objectiveID)
        unmarkRecordRecentlyWritten(recordType: RecordType.learningObjective, recordName: recordID.recordName)
        pendingLearningObjectiveCreateIDs.remove(objectiveID)
        unconfirmedLearningObjectiveRecordNames.remove(recordID.recordName)
        setLearningObjectives(allLearningObjectives)
    }

    private func deleteMembershipByRecordID(_ recordID: CKRecord.ID) {
        guard let membershipID = UUID(uuidString: recordID.recordName) else {
            if let resolved = membershipRecordNameByID.first(where: { $0.value == recordID.recordName })?.key {
                syncLogger.info("Deleting membership with non-UUID recordName mapped to \(resolved.uuidString.prefix(8), privacy: .public)")
                objectWillChange.send()
                memberships.removeAll { $0.id == resolved }
                membershipRecordNameByID.removeValue(forKey: resolved)
                unmarkRecordRecentlyWritten(recordType: RecordType.studentGroupMembership, recordName: recordID.recordName)
                refreshLegacyGroupConvenience()
                rebuildGroupMembershipCaches()
            }
            return
        }
        syncLogger.info("Deleting membership with id: \(membershipID.uuidString.prefix(8), privacy: .public)")
        objectWillChange.send()
        memberships.removeAll { $0.id == membershipID }
        membershipRecordNameByID.removeValue(forKey: membershipID)
        unmarkRecordRecentlyWritten(recordType: RecordType.studentGroupMembership, recordName: recordID.recordName)
        refreshLegacyGroupConvenience()
        rebuildGroupMembershipCaches()
    }

    private func deleteProgressByRecordID(_ recordID: CKRecord.ID) {
        let uuid = resolvedStableID(forRecordName: recordID.recordName, lookup: progressRecordNameByID)
        syncLogger.info("Deleting progress with id: \(uuid.uuidString.prefix(8), privacy: .public)")
        objectWillChange.send()
        progressRecordNameByID.removeValue(forKey: uuid)
        unmarkRecordRecentlyWritten(recordType: RecordType.objectiveProgress, recordName: recordID.recordName)
        for student in students {
            if progressLoadedStudentIDs.contains(student.id) {
                student.progressRecords.removeAll { $0.id == uuid }
            }
        }
        rebuildProgressCaches(debounce: true)
    }

    private func deleteCustomPropertyByRecordID(_ recordID: CKRecord.ID) {
        let uuid = resolvedStableID(forRecordName: recordID.recordName, lookup: customPropertyRecordNameByID)
        syncLogger.info("Deleting custom property with id: \(uuid.uuidString.prefix(8), privacy: .public)")
        objectWillChange.send()
        customPropertyRecordNameByID.removeValue(forKey: uuid)
        unmarkRecordRecentlyWritten(recordType: RecordType.studentCustomProperty, recordName: recordID.recordName)
        for student in students {
            if customPropertiesLoadedStudentIDs.contains(student.id) {
                student.customProperties.removeAll { $0.id == uuid }
            }
        }
    }

    private func deleteExpertiseCheckObjectiveScoreByRecordID(_ recordID: CKRecord.ID) {
        let uuid = resolvedStableID(forRecordName: recordID.recordName, lookup: expertiseCheckScoreRecordNameByID)
        syncLogger.info("Deleting expertise check score with id: \(uuid.uuidString.prefix(8), privacy: .public)")
        objectWillChange.send()
        expertiseCheckScoreRecordNameByID.removeValue(forKey: uuid)
        unmarkRecordRecentlyWritten(recordType: RecordType.expertiseCheckObjectiveScore, recordName: recordID.recordName)
        expertiseCheckObjectiveScores.removeAll { $0.id == uuid }
        rebuildExpertiseCheckScoreCaches()
    }

    // Old reconcile functions removed - now handled by reconcileWithServer()

    private enum RecordType {
        static let cohort = "Cohort"
        static let cohortGroup = "CohortGroup"
        static let domain = "Domain"
        static let categoryLabel = "CategoryLabel"
        static let learningObjective = "LearningObjective"
        static let student = "Student"
        static let studentGroupMembership = "StudentGroupMembership"
        static let studentCustomProperty = "StudentCustomProperty"
        static let objectiveProgress = "ObjectiveProgress"
        static let expertiseCheckObjectiveScore = "ExpertiseCheckObjectiveScore"
    }

    private enum Field {
        static let cohortId = "cohortId"
        static let cohortRef = "cohortRef"
        static let name = "name"
        static let colorHex = "colorHex"
        static let key = "key"
        static let code = "code"
        static let title = "title"
        static let group = "group"
        static let groupRef = "groupRef"
        static let domain = "domain"
        static let session = "session"
        static let student = "student"
        static let studentRef = "studentRef"
        static let objectiveRef = "objectiveRef"
        static let expertiseCheckRef = "expertiseCheckRef"
        static let objectiveCode = "objectiveCode"
        static let completionPercentage = "completionPercentage"
        static let status = "status"
        static let notes = "notes"
        static let lastUpdated = "lastUpdated"
        static let value = "value"
        static let parentRef = "parentRef"
        static let parentCode = "parentCode"
        static let objectiveDescription = "objectiveDescription"
        static let isQuantitative = "isQuantitative"
        static let isArchived = "isArchived"
        static let sortOrder = "sortOrder"
        static let createdAt = "createdAt"
        static let updatedAt = "updatedAt"
        static let lastEditedByDisplayName = "lastEditedByDisplayName"
        static let overallMode = "overallMode"
    }
}

extension CloudKitStore {
    func makeCSVExportPayload() -> CSVExportPayload {
        let cohortRecordName = cohortRecordID?.recordName ?? activeCohortId
        let studentRecordNameByID = self.studentRecordNameByID
        let groupRecordNameByID = self.groupRecordNameByID
        let membershipRecordNameByID = self.membershipRecordNameByID
        let domainRecordNameByID = self.domainRecordNameByID
        let learningObjectiveRecordNameByID = self.learningObjectiveRecordNameByID
        let progressRecordNameByID = self.progressRecordNameByID
        let customPropertyRecordNameByID = self.customPropertyRecordNameByID

        return CSVExportPayload(
            cohortRecordName: cohortRecordName,
            students: students,
            groups: groups,
            memberships: memberships,
            domains: domains,
            learningObjectives: learningObjectives,
            categoryLabels: categoryLabels,
            studentRecordName: { student in
                studentRecordNameByID[student.id] ?? student.id.uuidString
            },
            groupRecordName: { group in
                groupRecordNameByID[group.id] ?? group.id.uuidString
            },
            membershipRecordName: { membership in
                membershipRecordNameByID[membership.id] ?? membership.id.uuidString
            },
            domainRecordName: { domain in
                domainRecordNameByID[domain.id] ?? domain.id.uuidString
            },
            learningObjectiveRecordName: { objective in
                learningObjectiveRecordNameByID[objective.id] ?? objective.id.uuidString
            },
            progressRecordName: { progress in
                progressRecordNameByID[progress.id] ?? progress.id.uuidString
            },
            customPropertyRecordName: { property in
                customPropertyRecordNameByID[property.id] ?? property.id.uuidString
            }
        )
    }
}
