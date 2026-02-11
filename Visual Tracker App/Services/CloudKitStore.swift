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

    private let service: CloudKitService
    private let cohortId: String = "main"
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
    private var allLearningObjectives: [LearningObjective] = []
    private var pendingGroupCreateIDs: Set<UUID> = []
    private var pendingDomainCreateIDs: Set<UUID> = []
    private var pendingLearningObjectiveCreateIDs: Set<UUID> = []
    private var pendingCategoryLabelCreateKeys: Set<String> = []
    private var unconfirmedGroupRecordNames: Set<String> = []
    private var unconfirmedDomainRecordNames: Set<String> = []
    private var unconfirmedLearningObjectiveRecordNames: Set<String> = []
    private var unconfirmedCategoryLabelRecordNames: Set<String> = []
    private var objectiveRefMigrationRecordNames: Set<String> = []
    private var isSeedingLearningObjectives: Bool = false
    private var isMigratingLegacyMemberships: Bool = false

    private var syncCoordinator: CloudKitSyncCoordinator?
    private var lastSyncDateDefaultsKey: String { "VisualTrackerApp.lastSyncDate.\(cohortId)" }

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

    init(service: CloudKitService = CloudKitService(), usePreviewData: Bool = false) {
        self.service = service
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
            hasLoaded = true
        }
    }

    func loadIfNeeded() async {
        guard hasLoaded == false else { return }
        await reloadAllData()
    }

    func reloadAllData(force: Bool = false) async {
        if isLoading {
            guard force else { return }
        }

        isLoading = true
        lastErrorMessage = nil
        groupRecordNameByID.removeAll()
        domainRecordNameByID.removeAll()
        learningObjectiveRecordNameByID.removeAll()
        studentRecordNameByID.removeAll()
        membershipRecordNameByID.removeAll()
        progressRecordNameByID.removeAll()
        customPropertyRecordNameByID.removeAll()
        pendingGroupCreateIDs.removeAll()
        pendingDomainCreateIDs.removeAll()
        pendingLearningObjectiveCreateIDs.removeAll()
        pendingCategoryLabelCreateKeys.removeAll()
        unconfirmedGroupRecordNames.removeAll()
        unconfirmedDomainRecordNames.removeAll()
        unconfirmedLearningObjectiveRecordNames.removeAll()
        unconfirmedCategoryLabelRecordNames.removeAll()

        do {
            let status = try await service.accountStatus()
            if status != .available {
                requiresICloudLogin = true
                lastErrorMessage = "iCloud account not available (\(status.rawValue)). Sign in to iCloud on this Mac, then relaunch the app."
                isLoading = false
                return
            }
            requiresICloudLogin = false

            let cohortRecord = try await ensureCohortRecord()
            cohortRecordID = cohortRecord.recordID

            let cohortRef = CKRecord.Reference(recordID: cohortRecord.recordID, action: .none)

            let groupRecords = try await service.queryRecords(
                ofType: RecordType.cohortGroup,
                predicate: NSPredicate(format: "cohortRef == %@", cohortRef),
                sortDescriptors: [NSSortDescriptor(key: Field.name, ascending: true)]
            )
            let domainRecords = try await service.queryRecords(
                ofType: RecordType.domain,
                predicate: NSPredicate(format: "cohortRef == %@", cohortRef),
                sortDescriptors: [NSSortDescriptor(key: Field.name, ascending: true)]
            )
            let labelRecords = try await service.queryRecords(
                ofType: RecordType.categoryLabel,
                predicate: NSPredicate(format: "cohortRef == %@", cohortRef),
                sortDescriptors: [NSSortDescriptor(key: Field.key, ascending: true)]
            )
            let learningObjectiveRecords = try await service.queryRecords(
                ofType: RecordType.learningObjective,
                predicate: NSPredicate(format: "cohortRef == %@", cohortRef),
                sortDescriptors: [NSSortDescriptor(key: Field.sortOrder, ascending: true)]
            )
            let membershipRecords = try await service.queryRecords(
                ofType: RecordType.studentGroupMembership,
                predicate: NSPredicate(format: "cohortRef == %@", cohortRef),
                sortDescriptors: [NSSortDescriptor(key: Field.createdAt, ascending: true)]
            )

            let mappedGroups = groupRecords.map { mapGroup(from: $0) }
            let mappedDomains = domainRecords.map { mapDomain(from: $0) }
            let mappedLearningObjectives = mapLearningObjectives(from: learningObjectiveRecords)

            let groupMap = dictionaryByRecordName(items: mappedGroups, recordNameLookup: groupRecordNameByID)
            let domainMap = dictionaryByRecordName(items: mappedDomains, recordNameLookup: domainRecordNameByID)

            let studentRecords = try await service.queryRecords(
                ofType: RecordType.student,
                predicate: NSPredicate(format: "cohortRef == %@", cohortRef),
                sortDescriptors: [NSSortDescriptor(key: Field.createdAt, ascending: true)]
            )

            let mappedStudents = studentRecords.map { mapStudent(from: $0, groupMap: groupMap, domainMap: domainMap) }

            let mappedLabels = labelRecords.map { mapCategoryLabel(from: $0) }
            let studentMap = dictionaryByRecordName(items: mappedStudents, recordNameLookup: studentRecordNameByID)
            let mappedMemberships = membershipRecords.compactMap { record in
                mapMembership(from: record, studentMap: studentMap, groupMap: groupMap)
            }

            mergeFetchedGroups(mappedGroups)
            mergeFetchedDomains(mappedDomains)
            mergeFetchedCategoryLabels(mappedLabels)
            memberships = uniqueMemberships(mappedMemberships)
            students = mappedStudents.sorted { $0.createdAt < $1.createdAt }
            if mappedLearningObjectives.isEmpty {
                setLearningObjectives(defaultLearningObjectivesWithResolvedParents())
            } else {
                setLearningObjectives(mappedLearningObjectives)
            }
            refreshLegacyGroupConvenience()

            progressLoadedStudentIDs.removeAll()
            customPropertiesLoadedStudentIDs.removeAll()

            // Full reload is authoritative; move the incremental sync cursor forward.
            lastSyncDate = Date()
            hasLoaded = true

            startLiveSyncIfNeeded()
            Task { [weak self] in
                guard let self else { return }
                await self.ensureLearningObjectivesSeededIfNeeded()
                await self.migrateLegacyGroupMembershipsIfNeeded()
            }
        } catch {
            let detail = service.describe(error)
            lastErrorMessage = friendlyMessage(for: error, detail: detail)
        }

        isLoading = false
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
            syncCoordinator?.noteLocalWrite()
        } catch {
            pendingGroupCreateIDs.remove(group.id)
            unconfirmedGroupRecordNames.remove(recordID.recordName)
            lastErrorMessage = "Failed to save group: \(error.localizedDescription)"
        }
    }

    func renameGroup(_ group: CohortGroup, newName: String) async {
        lastErrorMessage = nil
        guard await requireWriteAccess() else { return }
        let previousName = group.name
        group.name = newName
        groups.sort { $0.name < $1.name }

        do {
            try await saveGroupRecord(group)
        } catch {
            group.name = previousName
            groups.sort { $0.name < $1.name }
            lastErrorMessage = "Failed to rename group: \(error.localizedDescription)"
        }
    }

    func deleteGroup(_ group: CohortGroup) async {
        lastErrorMessage = nil
        guard await requireWriteAccess() else { return }
        let recordID = recordID(for: group, lookup: groupRecordNameByID)

        let affectedStudentIDs = Set(
            memberships
                .filter { $0.group?.id == group.id }
                .compactMap { $0.student?.id }
        )
        let affected = students.filter { affectedStudentIDs.contains($0.id) || $0.group?.id == group.id }

        groups.removeAll { $0.id == group.id }

        do {
            try await deleteMemberships(forGroupID: group.id)
            try await service.delete(recordID: recordID)
            refreshLegacyGroupConvenience()
            for student in affected {
                try await saveStudentRecord(student)
            }
            syncCoordinator?.noteLocalWrite()
        } catch {
            lastErrorMessage = "Failed to delete group: \(error.localizedDescription)"
            await reloadAllData()
        }
    }

    func addDomain(name: String, colorHex: String?) async {
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

        let record = CKRecord(recordType: RecordType.domain, recordID: recordID)
        record[Field.cohortRef] = CKRecord.Reference(recordID: cohortRecordID, action: .none)
        record[Field.name] = domain.name
        record[Field.colorHex] = domain.colorHex
        applyAuditFields(to: record, createdAt: Date())

        do {
            let saved = try await service.save(record: record)
            domainRecordNameByID[domain.id] = saved.recordID.recordName
            pendingDomainCreateIDs.remove(domain.id)
            unconfirmedDomainRecordNames.remove(recordID.recordName)
            unconfirmedDomainRecordNames.insert(saved.recordID.recordName)
            syncCoordinator?.noteLocalWrite()
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
            await addDomain(name: preset, colorHex: nil)
            existing.insert(normalized)
        }
    }

    func renameDomain(_ domain: Domain, newName: String) async {
        lastErrorMessage = nil
        guard await requireWriteAccess() else { return }
        let previousName = domain.name
        domain.name = newName
        domains.sort { $0.name < $1.name }

        do {
            try await saveDomainRecord(domain)
        } catch {
            domain.name = previousName
            domains.sort { $0.name < $1.name }
            lastErrorMessage = "Failed to rename domain: \(error.localizedDescription)"
        }
    }

    func deleteDomain(_ domain: Domain) async {
        lastErrorMessage = nil
        guard await requireWriteAccess() else { return }
        let recordID = recordID(for: domain, lookup: domainRecordNameByID)

        let affected = students.filter { $0.domain?.id == domain.id }
        affected.forEach { $0.domain = nil }
        domains.removeAll { $0.id == domain.id }

        do {
            try await service.delete(recordID: recordID)
            for student in affected {
                try await saveStudentRecord(student)
            }
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
        lastErrorMessage = nil
        guard await requireWriteAccess() else { return nil }
        guard let cohortRecordID else {
            await reloadAllData()
            return nil
        }

        let student = Student(name: name, group: group, session: session, domain: domain)
        students.append(student)
        students.sort { $0.createdAt < $1.createdAt }

        let recordID = CKRecord.ID(recordName: student.id.uuidString)
        studentRecordNameByID[student.id] = recordID.recordName

        let record = CKRecord(recordType: RecordType.student, recordID: recordID)
        applyStudentFields(student, to: record, cohortRecordID: cohortRecordID)

        do {
            let saved = try await service.save(record: record)
            studentRecordNameByID[student.id] = saved.recordID.recordName

            if customProperties.isEmpty == false {
                try await replaceCustomProperties(for: student, rows: customProperties)
            }
            if let group {
                try await setGroupsInternal(for: student, groups: [group], updateLegacyGroupField: false)
            }

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
        lastErrorMessage = nil
        guard await requireWriteAccess() else { return }
        student.name = name
        student.session = session
        student.domain = domain

        do {
            try await saveStudentRecord(student)
            if let group {
                try await setGroupsInternal(for: student, groups: [group], updateLegacyGroupField: true)
            } else {
                let existingExplicitGroups = explicitGroups(for: student)
                if existingExplicitGroups.count > 1 {
                    // The edit sheet is still single-group. Preserve explicit many-to-many memberships
                    // when no group is selected to avoid accidental data loss.
                    refreshLegacyGroupConvenience(for: student)
                    try await saveStudentRecord(student)
                } else {
                    try await setGroupsInternal(for: student, groups: [], updateLegacyGroupField: true)
                }
            }
            try await replaceCustomProperties(for: student, rows: customProperties)
        } catch {
            lastErrorMessage = "Failed to update student: \(error.localizedDescription)"
            await reloadAllData()
        }
    }

    func renameStudent(_ student: Student, newName: String) async {
        lastErrorMessage = nil
        guard await requireWriteAccess() else { return }
        let previousName = student.name
        student.name = newName

        do {
            try await saveStudentRecord(student)
        } catch {
            student.name = previousName
            lastErrorMessage = "Failed to rename student: \(error.localizedDescription)"
        }
    }

    func moveStudent(_ student: Student, to group: CohortGroup?) async {
        lastErrorMessage = nil
        guard await requireWriteAccess() else { return }

        do {
            try await setGroupsInternal(for: student, groups: group.map { [$0] } ?? [], updateLegacyGroupField: true)
        } catch {
            lastErrorMessage = "Failed to move student: \(error.localizedDescription)"
        }
    }

    func deleteStudent(_ student: Student) async {
        lastErrorMessage = nil
        guard await requireWriteAccess() else { return }
        let recordID = recordID(for: student, lookup: studentRecordNameByID)

        students.removeAll { $0.id == student.id }

        do {
            try await service.delete(recordID: recordID)
            try await deleteMemberships(forStudentID: student.id)
            try await deleteProgress(for: student)
            try await deleteCustomProperties(for: student)
            syncCoordinator?.noteLocalWrite()
        } catch {
            lastErrorMessage = "Failed to delete student: \(error.localizedDescription)"
            await reloadAllData()
        }
    }

    func groups(for student: Student) -> [CohortGroup] {
        let explicitGroups = memberships.compactMap { membership -> CohortGroup? in
            guard membership.student?.id == student.id else { return nil }
            return membership.group
        }
        let uniqueByID = Dictionary(grouping: explicitGroups, by: \.id).compactMap { $0.value.first }
        if uniqueByID.isEmpty {
            if let legacyGroup = student.group {
                return [legacyGroup]
            }
            return []
        }
        return uniqueByID.sorted { $0.name < $1.name }
    }

    func primaryGroup(for student: Student) -> CohortGroup? {
        let assignedGroups = groups(for: student)
        guard assignedGroups.count == 1 else { return nil }
        return assignedGroups.first
    }

    func isUngrouped(student: Student) -> Bool {
        groups(for: student).isEmpty
    }

    func setGroups(
        for student: Student,
        groups: [CohortGroup],
        updateLegacyGroupField: Bool = true
    ) async {
        lastErrorMessage = nil
        guard await requireWriteAccess() else { return }
        do {
            try await setGroupsInternal(
                for: student,
                groups: groups,
                updateLegacyGroupField: updateLegacyGroupField
            )
        } catch {
            lastErrorMessage = "Failed to update student groups: \(error.localizedDescription)"
            await reloadAllData()
        }
    }

    func addStudentToGroup(_ student: Student, group: CohortGroup) async {
        lastErrorMessage = nil
        guard await requireWriteAccess() else { return }
        do {
            try await addStudentToGroupInternal(student, group: group, updateLegacyGroupField: true)
        } catch {
            lastErrorMessage = "Failed to add student to group: \(error.localizedDescription)"
            await reloadAllData()
        }
    }

    func removeStudentFromGroup(_ student: Student, group: CohortGroup) async {
        lastErrorMessage = nil
        guard await requireWriteAccess() else { return }
        do {
            try await removeStudentFromGroupInternal(student, group: group, updateLegacyGroupField: true)
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

        let objective = LearningObjective(
            code: code,
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

        let previousCode = objective.code
        let previousTitle = objective.title
        let previousDescription = objective.objectiveDescription
        let previousIsQuantitative = objective.isQuantitative
        let previousParentId = objective.parentId
        let previousParentCode = objective.parentCode
        let previousSortOrder = objective.sortOrder
        let previousIsArchived = objective.isArchived

        objective.code = code
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
        objective.isArchived = true
        setLearningObjectives(allLearningObjectives)

        do {
            try await saveLearningObjectiveRecord(objective)
        } catch {
            objective.isArchived = false
            setLearningObjectives(allLearningObjectives)
            lastErrorMessage = "Failed to archive learning objective: \(error.localizedDescription)"
        }
    }

    func updateCategoryLabel(code: String, title: String) async {
        lastErrorMessage = nil
        guard await requireWriteAccess() else { return }
        guard let cohortRecordID else {
            await reloadAllData()
            return
        }

        let label: CategoryLabel
        let isNewLabel: Bool
        if let existing = categoryLabels.first(where: { $0.key == code }) {
            label = existing
            isNewLabel = false
            label.title = title
        } else {
            label = CategoryLabel(code: code, title: title)
            isNewLabel = true
            categoryLabels.append(label)
            pendingCategoryLabelCreateKeys.insert(code)
        }
        categoryLabels.sort { $0.key < $1.key }

        let recordID = CKRecord.ID(recordName: code)
        if isNewLabel {
            unconfirmedCategoryLabelRecordNames.insert(recordID.recordName)
        }
        let record = CKRecord(recordType: RecordType.categoryLabel, recordID: recordID)
        record[Field.cohortRef] = CKRecord.Reference(recordID: cohortRecordID, action: .none)
        record[Field.key] = label.key
        record[Field.code] = label.code
        record[Field.title] = label.title
        applyAuditFields(to: record, createdAt: Date())

        do {
            try await service.save(record: record)
            pendingCategoryLabelCreateKeys.remove(code)
            unconfirmedCategoryLabelRecordNames.insert(recordID.recordName)
            syncCoordinator?.noteLocalWrite()
        } catch {
            pendingCategoryLabelCreateKeys.remove(code)
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
        } catch {
            lastErrorMessage = "Failed to load progress: \(error.localizedDescription)"
        }
    }

    func setProgress(student: Student, objective: LearningObjective, value: Int) async {
        await setProgressInternal(student: student, objectiveCode: objective.code, objective: objective, value: value)
    }

    func setProgress(student: Student, objectiveCode: String, value: Int) async {
        await setProgressInternal(student: student, objectiveCode: objectiveCode, objective: nil, value: value)
    }

    private func setProgressInternal(
        student: Student,
        objectiveCode: String,
        objective explicitObjective: LearningObjective?,
        value: Int
    ) async {
        lastErrorMessage = nil
        guard await requireWriteAccess() else { return }
        guard let cohortRecordID else { return }
        let studentRecordID = recordID(for: student, lookup: studentRecordNameByID)
        let objective = explicitObjective ?? objectiveByCode(objectiveCode)
        let canonicalObjectiveCode = objective?.code ?? objectiveCode

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
        } else {
            progress = ObjectiveProgress(
                objectiveCode: canonicalObjectiveCode,
                completionPercentage: value,
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

        let progressRecordID = recordID(for: progress, lookup: progressRecordNameByID)
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
        isLoading = true
        resetProgress = ResetProgress(message: "Resetting data to base template...", step: 0, totalSteps: 10)
        defer {
            isLoading = false
            resetProgress = nil
        }

        do {
            let cohortRecordID = try await ensureCohortRecordIDForWrite()

            resetProgress = ResetProgress(message: "Deleting objective progress...", step: 1, totalSteps: 10)
            try await deleteAllRecords(ofType: RecordType.objectiveProgress, cohortRecordID: cohortRecordID)
            clearLocalObjectiveProgressState()

            resetProgress = ResetProgress(message: "Deleting custom properties...", step: 2, totalSteps: 10)
            try await deleteAllRecords(ofType: RecordType.studentCustomProperty, cohortRecordID: cohortRecordID)
            clearLocalCustomPropertyState()

            resetProgress = ResetProgress(message: "Deleting memberships...", step: 3, totalSteps: 10)
            try await deleteAllRecords(ofType: RecordType.studentGroupMembership, cohortRecordID: cohortRecordID)
            clearLocalMembershipState()

            resetProgress = ResetProgress(message: "Deleting students...", step: 4, totalSteps: 10)
            try await deleteAllRecords(ofType: RecordType.student, cohortRecordID: cohortRecordID)
            clearLocalStudentState()

            resetProgress = ResetProgress(message: "Deleting groups...", step: 5, totalSteps: 10)
            try await deleteAllRecords(ofType: RecordType.cohortGroup, cohortRecordID: cohortRecordID)
            clearLocalGroupState()

            resetProgress = ResetProgress(message: "Deleting category labels...", step: 6, totalSteps: 10)
            try await deleteAllRecords(ofType: RecordType.categoryLabel, cohortRecordID: cohortRecordID)
            clearLocalCategoryLabelState()

            resetProgress = ResetProgress(message: "Resetting Expertise Check to base defaults...", step: 7, totalSteps: 10)
            try await deleteAllRecords(ofType: RecordType.domain, cohortRecordID: cohortRecordID)
            clearLocalDomainState()

            resetProgress = ResetProgress(message: "Deleting Success Criteria and Milestones...", step: 8, totalSteps: 10)
            try await deleteAllRecords(ofType: RecordType.learningObjective, cohortRecordID: cohortRecordID)
            clearLocalLearningObjectiveState()

            resetProgress = ResetProgress(message: "Restoring default Success Criteria and Milestones...", step: 9, totalSteps: 10)
            let defaults = defaultLearningObjectivesWithResolvedParents()
            try await seedLearningObjectives(defaults)

            resetProgress = ResetProgress(message: "Restoring base Expertise Check defaults...", step: 10, totalSteps: 10)
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
        isLoading = true
        resetProgress = ResetProgress(message: "Resetting...", step: 0, totalSteps: 7)
        defer {
            isLoading = false
            resetProgress = nil
        }

        do {
            let cohortRecordID = try await ensureCohortRecordIDForWrite()

            resetProgress = ResetProgress(message: "Deleting progress...", step: 1, totalSteps: 7)
            try await deleteAllRecords(ofType: RecordType.objectiveProgress, cohortRecordID: cohortRecordID)
            resetProgress = ResetProgress(message: "Deleting custom properties...", step: 2, totalSteps: 7)
            try await deleteAllRecords(ofType: RecordType.studentCustomProperty, cohortRecordID: cohortRecordID)
            resetProgress = ResetProgress(message: "Deleting students...", step: 3, totalSteps: 7)
            try await deleteAllRecords(ofType: RecordType.student, cohortRecordID: cohortRecordID)
            resetProgress = ResetProgress(message: "Deleting category labels...", step: 4, totalSteps: 7)
            try await deleteAllRecords(ofType: RecordType.categoryLabel, cohortRecordID: cohortRecordID)
            resetProgress = ResetProgress(message: "Deleting memberships...", step: 5, totalSteps: 7)
            try await deleteAllRecords(ofType: RecordType.studentGroupMembership, cohortRecordID: cohortRecordID)
            resetProgress = ResetProgress(message: "Deleting groups...", step: 6, totalSteps: 7)
            try await deleteAllRecords(ofType: RecordType.cohortGroup, cohortRecordID: cohortRecordID)
            resetProgress = ResetProgress(message: "Deleting domains...", step: 7, totalSteps: 7)
            try await deleteAllRecords(ofType: RecordType.domain, cohortRecordID: cohortRecordID)

            resetProgress = ResetProgress(message: "Reloading data...", step: 7, totalSteps: 7)
            await reloadAllData()
            await ensurePresetDomains()
            syncCoordinator?.noteLocalWrite()
        } catch {
            lastErrorMessage = "Failed to reset data: \(error.localizedDescription)"
        }
    }

    private func ensureCohortRecord() async throws -> CKRecord {
        if let cohortRecordID {
            return try await service.fetchRecord(with: cohortRecordID)
        }

        let predicate = NSPredicate(format: "cohortId == %@", cohortId)
        let records = try await service.queryRecords(ofType: RecordType.cohort, predicate: predicate)

        if let existing = records.first {
            return existing
        }

        let recordID = CKRecord.ID(recordName: cohortId)
        let record = CKRecord(recordType: RecordType.cohort, recordID: recordID)
        record[Field.cohortId] = cohortId
        record[Field.name] = "Main Cohort"
        applyAuditFields(to: record, createdAt: Date())
        return try await service.save(record: record)
    }

    private func saveGroupRecord(_ group: CohortGroup) async throws {
        guard let cohortRecordID else { return }
        let recordID = recordID(for: group, lookup: groupRecordNameByID)
        let record = CKRecord(recordType: RecordType.cohortGroup, recordID: recordID)
        record[Field.cohortRef] = CKRecord.Reference(recordID: cohortRecordID, action: .none)
        record[Field.name] = group.name
        record[Field.colorHex] = group.colorHex
        applyAuditFields(to: record, createdAt: Date())
        let saved = try await service.save(record: record)
        groupRecordNameByID[group.id] = saved.recordID.recordName
        pendingGroupCreateIDs.remove(group.id)
        unconfirmedGroupRecordNames.insert(saved.recordID.recordName)
        syncCoordinator?.noteLocalWrite()
    }

    private func saveDomainRecord(_ domain: Domain) async throws {
        guard let cohortRecordID else { return }
        let recordID = recordID(for: domain, lookup: domainRecordNameByID)
        let record = CKRecord(recordType: RecordType.domain, recordID: recordID)
        record[Field.cohortRef] = CKRecord.Reference(recordID: cohortRecordID, action: .none)
        record[Field.name] = domain.name
        record[Field.colorHex] = domain.colorHex
        applyAuditFields(to: record, createdAt: Date())
        let saved = try await service.save(record: record)
        domainRecordNameByID[domain.id] = saved.recordID.recordName
        pendingDomainCreateIDs.remove(domain.id)
        unconfirmedDomainRecordNames.insert(saved.recordID.recordName)
        syncCoordinator?.noteLocalWrite()
    }

    private func saveStudentRecord(_ student: Student) async throws {
        guard let cohortRecordID else { return }
        let recordID = recordID(for: student, lookup: studentRecordNameByID)
        let record = CKRecord(recordType: RecordType.student, recordID: recordID)
        applyStudentFields(student, to: record, cohortRecordID: cohortRecordID)
        let saved = try await service.save(record: record)
        studentRecordNameByID[student.id] = saved.recordID.recordName
        syncCoordinator?.noteLocalWrite()
    }

    private func saveLearningObjectiveRecord(
        _ objective: LearningObjective,
        allObjectives: [LearningObjective]? = nil
    ) async throws {
        guard let cohortRecordID else { return }
        let learningObjectiveRecordID = recordID(for: objective, lookup: learningObjectiveRecordNameByID)
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
        let record = CKRecord(recordType: RecordType.studentCustomProperty, recordID: recordID)
        record[Field.cohortRef] = CKRecord.Reference(recordID: cohortRecordID, action: .none)
        record[Field.student] = CKRecord.Reference(recordID: studentRecordID, action: .none)
        record[Field.key] = property.key
        record[Field.value] = property.value
        record[Field.sortOrder] = property.sortOrder
        applyAuditFields(to: record, createdAt: Date())

        let saved = try await service.save(record: record)
        customPropertyRecordNameByID[property.id] = saved.recordID.recordName
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
        let domain = Domain(name: name, colorHex: colorHex)
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
        let objectiveId = objectiveRef.flatMap { objectiveID(forRecordName: $0.recordID.recordName) }
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

    private func setLearningObjectives(_ objectives: [LearningObjective]) {
        allLearningObjectives = objectives.sorted {
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
    }

    private func defaultLearningObjectivesWithResolvedParents() -> [LearningObjective] {
        let defaults = LearningObjectiveCatalog.defaultObjectives()
        let objectiveByCode = Dictionary(uniqueKeysWithValues: defaults.map { ($0.code, $0) })
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
            return allObjectives.first { $0.code == parentCode }
        }
        return nil
    }

    private func objectiveByCode(_ code: String) -> LearningObjective? {
        allLearningObjectives.first { $0.code == code }
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
        memberships.compactMap { membership -> CohortGroup? in
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
        let record = CKRecord(recordType: RecordType.studentGroupMembership, recordID: recordID)
        record[Field.cohortRef] = CKRecord.Reference(recordID: cohortRecordID, action: .none)
        record[Field.studentRef] = CKRecord.Reference(recordID: studentRecordID, action: .none)
        record[Field.groupRef] = CKRecord.Reference(recordID: groupRecordID, action: .none)
        applyAuditFields(to: record, createdAt: membership.createdAt)

        let saved = try await service.save(record: record)
        membership.updatedAt = Date()
        membershipRecordNameByID[membership.id] = saved.recordID.recordName
        syncCoordinator?.noteLocalWrite()
    }

    private func deleteMembershipRecord(_ membership: StudentGroupMembership) async throws {
        let recordID = recordID(for: membership, lookup: membershipRecordNameByID)
        try await service.delete(recordID: recordID)
        memberships.removeAll { $0.id == membership.id }
        membershipRecordNameByID.removeValue(forKey: membership.id)
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
    }

    private func clearLocalGroupState() {
        groups.removeAll()
        groupRecordNameByID.removeAll()
        pendingGroupCreateIDs.removeAll()
        unconfirmedGroupRecordNames.removeAll()
        refreshLegacyGroupConvenience()
    }

    private func clearLocalCategoryLabelState() {
        categoryLabels.removeAll()
        pendingCategoryLabelCreateKeys.removeAll()
        unconfirmedCategoryLabelRecordNames.removeAll()
    }

    private func clearLocalDomainState() {
        domains.removeAll()
        domainRecordNameByID.removeAll()
        pendingDomainCreateIDs.removeAll()
        unconfirmedDomainRecordNames.removeAll()
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
    }

    private func mergeFetchedDomains(_ fetched: [Domain]) {
        let fetchedByID = Dictionary(uniqueKeysWithValues: fetched.map { ($0.id, $0) })
        for existing in domains {
            guard let incoming = fetchedByID[existing.id] else { continue }
            existing.name = incoming.name
            existing.colorHex = incoming.colorHex
        }
        for incoming in fetched where domains.contains(where: { $0.id == incoming.id }) == false {
            domains.append(incoming)
        }
        domains.removeAll { fetchedByID[$0.id] == nil }
        domains.sort { $0.name < $1.name }
    }

    private func mergeFetchedCategoryLabels(_ fetched: [CategoryLabel]) {
        let fetchedByKey = Dictionary(uniqueKeysWithValues: fetched.map { ($0.key, $0) })
        for existing in categoryLabels {
            guard let incoming = fetchedByKey[existing.key] else { continue }
            existing.title = incoming.title
        }
        for incoming in fetched where categoryLabels.contains(where: { $0.key == incoming.key }) == false {
            categoryLabels.append(incoming)
        }
        categoryLabels.removeAll { fetchedByKey[$0.key] == nil }
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
        let updatedAfter = previousSync as NSDate

        do {
            // Keep group/domain instances stable by upserting in-place.
            // Note: We use 'updatedAt' (custom queryable field) instead of 'modificationDate' (system field not queryable)
            let groupPredicate = NSPredicate(format: "cohortRef == %@ AND updatedAt > %@", cohortRef, updatedAfter)
            let domainPredicate = NSPredicate(format: "cohortRef == %@ AND updatedAt > %@", cohortRef, updatedAfter)
            let labelPredicate = NSPredicate(format: "cohortRef == %@ AND updatedAt > %@", cohortRef, updatedAfter)
            let objectivePredicate = NSPredicate(format: "cohortRef == %@ AND updatedAt > %@", cohortRef, updatedAfter)
            let studentPredicate = NSPredicate(format: "cohortRef == %@ AND updatedAt > %@", cohortRef, updatedAfter)
            let membershipPredicate = NSPredicate(format: "cohortRef == %@ AND updatedAt > %@", cohortRef, updatedAfter)
            let progressPredicate = NSPredicate(format: "cohortRef == %@ AND updatedAt > %@", cohortRef, updatedAfter)
            let customPropPredicate = NSPredicate(format: "cohortRef == %@ AND updatedAt > %@", cohortRef, updatedAfter)

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

            let (groupRecords, domainRecords, labelRecords, objectiveRecords, studentRecords, membershipRecords, progressRecords, customPropRecords) =
            try await (groupsChanged, domainsChanged, labelsChanged, objectivesChanged, studentsChanged, membershipsChanged, progressChanged, customPropsChanged)

            let totalChanges = groupRecords.count + domainRecords.count + labelRecords.count +
                              objectiveRecords.count + studentRecords.count + membershipRecords.count +
                              progressRecords.count + customPropRecords.count
            
            if totalChanges == 0 {
                syncLogger.info("Incremental sync: no changes found since last sync")
                lastSyncDate = syncWindowStart
                return
            }
            
            syncLogger.info("Incremental sync found changes: groups=\(groupRecords.count, privacy: .public) domains=\(domainRecords.count, privacy: .public) labels=\(labelRecords.count, privacy: .public) objectives=\(objectiveRecords.count, privacy: .public) students=\(studentRecords.count, privacy: .public) memberships=\(membershipRecords.count, privacy: .public) progress=\(progressRecords.count, privacy: .public) customProps=\(customPropRecords.count, privacy: .public)")

            // Upsert order matters: groups/domains first, then students, then child records.
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

            // Advance cursor
            lastSyncDate = syncWindowStart
            syncLogger.info("Incremental sync complete. Applied \(totalChanges, privacy: .public) total changes. New sync date: \(syncWindowStart, privacy: .public)")
        } catch {
            // Keep it quiet; polling / next activation will retry.
            // Don't overwrite existing user-facing error unless something else does.
            syncLogger.error("Incremental sync failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func fetchAndApplyRemoteRecord(recordType: String, recordID: CKRecord.ID) async {
        do {
            let record = try await service.fetchRecord(with: recordID)
            applyRemoteUpsert(recordType: recordType, record: record)
        } catch {
            // If the record can't be fetched (e.g., deleted quickly), allow reconcile/poll to handle eventual consistency.
        }
    }

    func applyRemoteDeletion(recordType: String, recordID: CKRecord.ID) {
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

            let (remoteGroups, remoteDomains, remoteObjectives, remoteStudents, remoteMemberships, remoteLabels) =
            try await (groupRecords, domainRecords, objectiveRecords, studentRecords, membershipRecords, labelRecords)

            syncLogger.info("Reconciliation fetched: groups=\(remoteGroups.count, privacy: .public) domains=\(remoteDomains.count, privacy: .public) objectives=\(remoteObjectives.count, privacy: .public) students=\(remoteStudents.count, privacy: .public) memberships=\(remoteMemberships.count, privacy: .public) labels=\(remoteLabels.count, privacy: .public)")

            // Apply ALL remote records - handles adds AND updates
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

            // Remove locally-held records that no longer exist on server (deletions)
            let remoteGroupIDs = Set(remoteGroups.map { $0.recordID.recordName })
            let localGroupIDs = Set(groupRecordNameByID.values)
            for recordName in localGroupIDs.subtracting(remoteGroupIDs) {
                guard unconfirmedGroupRecordNames.contains(recordName) == false else { continue }
                deleteGroupByRecordID(CKRecord.ID(recordName: recordName))
            }

            let remoteDomainIDs = Set(remoteDomains.map { $0.recordID.recordName })
            let localDomainIDs = Set(domainRecordNameByID.values)
            for recordName in localDomainIDs.subtracting(remoteDomainIDs) {
                guard unconfirmedDomainRecordNames.contains(recordName) == false else { continue }
                deleteDomainByRecordID(CKRecord.ID(recordName: recordName))
            }

            let remoteStudentIDs = Set(remoteStudents.map { $0.recordID.recordName })
            let localStudentIDs = Set(studentRecordNameByID.values)
            for recordName in localStudentIDs.subtracting(remoteStudentIDs) {
                deleteStudentByRecordID(CKRecord.ID(recordName: recordName))
            }

            let remoteObjectiveIDs = Set(remoteObjectives.map { $0.recordID.recordName })
            let localObjectiveIDs = Set(learningObjectiveRecordNameByID.values)
            for recordName in localObjectiveIDs.subtracting(remoteObjectiveIDs) {
                guard unconfirmedLearningObjectiveRecordNames.contains(recordName) == false else { continue }
                deleteLearningObjectiveByRecordID(CKRecord.ID(recordName: recordName))
            }

            let remoteMembershipIDs = Set(remoteMemberships.map { $0.recordID.recordName })
            let localMembershipIDs = Set(membershipRecordNameByID.values)
            for recordName in localMembershipIDs.subtracting(remoteMembershipIDs) {
                deleteMembershipByRecordID(CKRecord.ID(recordName: recordName))
            }

            let remoteLabelIDs = Set(remoteLabels.map { $0.recordID.recordName })
            let localLabelIDs = Set(categoryLabels.map { $0.key })
            for key in localLabelIDs.subtracting(remoteLabelIDs) {
                guard unconfirmedCategoryLabelRecordNames.contains(key) == false else { continue }
                deleteCategoryLabelByRecordID(CKRecord.ID(recordName: key))
            }

            // Progress and custom properties are only reconciled for loaded students
            // (We don't want to fetch all progress for all students - that's done on-demand)
            await reconcileProgressForLoadedStudents(cohortRef: cohortRef)
            await reconcileCustomPropertiesForLoadedStudents(cohortRef: cohortRef)
            
            syncLogger.info("Full reconciliation complete")
        } catch {
            syncLogger.error("Full reconciliation failed: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    private func reconcileProgressForLoadedStudents(cohortRef: CKRecord.Reference) async {
        guard progressLoadedStudentIDs.isEmpty == false else { return }
        
        do {
            let predicate = NSPredicate(format: "cohortRef == %@", cohortRef)
            let remoteProgressRecords = try await service.queryRecords(ofType: RecordType.objectiveProgress, predicate: predicate)
            
            // Apply ALL remote progress records for loaded students (handles adds AND updates)
            let relevantRecords = remoteProgressRecords.filter { record in
                guard let studentRef = studentReference(from: record) else { return false }
                guard let uuid = UUID(uuidString: studentRef.recordID.recordName) else { return false }
                return progressLoadedStudentIDs.contains(uuid)
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
            
            // Apply ALL remote custom property records for loaded students (handles adds AND updates)
            let relevantRecords = remoteCustomPropRecords.filter { record in
                guard let studentRef = studentReference(from: record) else { return false }
                guard let uuid = UUID(uuidString: studentRef.recordID.recordName) else { return false }
                return customPropertiesLoadedStudentIDs.contains(uuid)
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
        }

        groups.sort { $0.name < $1.name }
    }

    private func applyDomainChanges(_ records: [CKRecord]) {
        guard records.isEmpty == false else { return }

        // Notify SwiftUI that changes are coming
        objectWillChange.send()

        for record in records {
            let name = record[Field.name] as? String ?? "Untitled"
            let colorHex = record[Field.colorHex] as? String
            let uuid = resolvedStableID(forRecordName: record.recordID.recordName, lookup: domainRecordNameByID)

            if let existing = domains.first(where: { $0.id == uuid }) {
                syncLogger.info("Updating existing domain: \(name, privacy: .public)")
                existing.name = name
                existing.colorHex = colorHex
            } else {
                syncLogger.info("Adding new domain: \(name, privacy: .public)")
                let d = Domain(name: name, colorHex: colorHex)
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
            }
        }

        memberships = uniqueMemberships(memberships)
        refreshLegacyGroupConvenience()
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
        }

        students.sort { $0.createdAt < $1.createdAt }
        refreshLegacyGroupConvenience()
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

        for record in records {
            guard let studentRef = studentReference(from: record) else { continue }
            guard let studentID = studentIDByRecordName[studentRef.recordID.recordName] else { continue }
            guard let student = students.first(where: { $0.id == studentID }) else { continue }

            // Only mutate loaded progress arrays to avoid unexpected heavy loads.
            guard progressLoadedStudentIDs.contains(student.id) else {
                syncLogger.debug("Skipping progress update for student \(studentID.uuidString.prefix(8), privacy: .public) - progress not loaded")
                continue
            }

            let objectiveRef = record[Field.objectiveRef] as? CKRecord.Reference
            let objectiveId = objectiveRef.flatMap { objectiveID(forRecordName: $0.recordID.recordName) }
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
                existing.notes = notes
                existing.lastUpdated = lastUpdated
                existing.status = status
                existing.updateCompletion(canonicalValue)
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
            student.progressRecords.sort { $0.objectiveCode < $1.objectiveCode }
            scheduleObjectiveRefMigrationIfNeeded(records: [record], studentRecordID: studentRef.recordID)
        }
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
        }
    }

    private func deleteGroupByRecordID(_ recordID: CKRecord.ID) {
        let uuid = resolvedStableID(forRecordName: recordID.recordName, lookup: groupRecordNameByID)
        syncLogger.info("Deleting group with id: \(uuid.uuidString.prefix(8), privacy: .public)")
        objectWillChange.send()
        groups.removeAll { $0.id == uuid }
        groupRecordNameByID.removeValue(forKey: uuid)
        pendingGroupCreateIDs.remove(uuid)
        unconfirmedGroupRecordNames.remove(recordID.recordName)
        memberships.removeAll { $0.group?.id == uuid }
        let remainingMembershipIDs = Set(memberships.map(\.id))
        membershipRecordNameByID = membershipRecordNameByID.filter { remainingMembershipIDs.contains($0.key) }
        refreshLegacyGroupConvenience()
    }

    private func deleteDomainByRecordID(_ recordID: CKRecord.ID) {
        let uuid = resolvedStableID(forRecordName: recordID.recordName, lookup: domainRecordNameByID)
        syncLogger.info("Deleting domain with id: \(uuid.uuidString.prefix(8), privacy: .public)")
        objectWillChange.send()
        domains.removeAll { $0.id == uuid }
        domainRecordNameByID.removeValue(forKey: uuid)
        pendingDomainCreateIDs.remove(uuid)
        unconfirmedDomainRecordNames.remove(recordID.recordName)

        for student in students where student.domain?.id == uuid {
            student.domain = nil
        }
    }

    private func deleteStudentByRecordID(_ recordID: CKRecord.ID) {
        guard let uuid = UUID(uuidString: recordID.recordName) else { return }
        syncLogger.info("Deleting student with id: \(uuid.uuidString.prefix(8), privacy: .public)")
        objectWillChange.send()
        students.removeAll { $0.id == uuid }
        studentRecordNameByID.removeValue(forKey: uuid)
        memberships.removeAll { $0.student?.id == uuid }
        let remainingMembershipIDs = Set(memberships.map(\.id))
        membershipRecordNameByID = membershipRecordNameByID.filter { remainingMembershipIDs.contains($0.key) }
        progressLoadedStudentIDs.remove(uuid)
        customPropertiesLoadedStudentIDs.remove(uuid)
    }

    private func deleteCategoryLabelByRecordID(_ recordID: CKRecord.ID) {
        let key = recordID.recordName
        syncLogger.info("Deleting category label: \(key, privacy: .public)")
        objectWillChange.send()
        categoryLabels.removeAll { $0.key == key || $0.code == key }
        pendingCategoryLabelCreateKeys.remove(key)
        unconfirmedCategoryLabelRecordNames.remove(key)
    }

    private func deleteLearningObjectiveByRecordID(_ recordID: CKRecord.ID) {
        let objectiveID = objectiveID(forRecordName: recordID.recordName)
        guard let objectiveID else { return }
        syncLogger.info("Deleting learning objective id: \(objectiveID.uuidString.prefix(8), privacy: .public)")
        objectWillChange.send()
        allLearningObjectives.removeAll { $0.id == objectiveID }
        learningObjectiveRecordNameByID.removeValue(forKey: objectiveID)
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
                refreshLegacyGroupConvenience()
            }
            return
        }
        syncLogger.info("Deleting membership with id: \(membershipID.uuidString.prefix(8), privacy: .public)")
        objectWillChange.send()
        memberships.removeAll { $0.id == membershipID }
        membershipRecordNameByID.removeValue(forKey: membershipID)
        refreshLegacyGroupConvenience()
    }

    private func deleteProgressByRecordID(_ recordID: CKRecord.ID) {
        guard let uuid = UUID(uuidString: recordID.recordName) else { return }
        syncLogger.info("Deleting progress with id: \(uuid.uuidString.prefix(8), privacy: .public)")
        objectWillChange.send()
        progressRecordNameByID.removeValue(forKey: uuid)
        for student in students {
            if progressLoadedStudentIDs.contains(student.id) {
                student.progressRecords.removeAll { $0.id == uuid }
            }
        }
    }

    private func deleteCustomPropertyByRecordID(_ recordID: CKRecord.ID) {
        guard let uuid = UUID(uuidString: recordID.recordName) else { return }
        syncLogger.info("Deleting custom property with id: \(uuid.uuidString.prefix(8), privacy: .public)")
        objectWillChange.send()
        customPropertyRecordNameByID.removeValue(forKey: uuid)
        for student in students {
            if customPropertiesLoadedStudentIDs.contains(student.id) {
                student.customProperties.removeAll { $0.id == uuid }
            }
        }
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
    }
}

extension CloudKitStore {
    func makeCSVExportPayload() -> CSVExportPayload {
        let cohortRecordName = cohortRecordID?.recordName ?? cohortId
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
