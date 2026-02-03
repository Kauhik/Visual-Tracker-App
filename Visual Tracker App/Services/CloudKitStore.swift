import AppKit
import CloudKit
import Combine
import Foundation

@MainActor
final class CloudKitStore: ObservableObject {
    @Published var isLoading: Bool = false
    @Published var lastErrorMessage: String?
    @Published var requiresICloudLogin: Bool = false

    @Published var students: [Student] = []
    @Published var groups: [CohortGroup] = []
    @Published var domains: [Domain] = []
    @Published var categoryLabels: [CategoryLabel] = []
    @Published var learningObjectives: [LearningObjective] = LearningObjectiveCatalog.defaultObjectives()

    private let service: CloudKitService
    private let cohortId: String = "main"
    private var cohortRecordID: CKRecord.ID?
    private var hasLoaded: Bool = false

    private var progressLoadedStudentIDs: Set<UUID> = []
    private var customPropertiesLoadedStudentIDs: Set<UUID> = []

    private var groupRecordNameByID: [UUID: String] = [:]
    private var domainRecordNameByID: [UUID: String] = [:]
    private var studentRecordNameByID: [UUID: String] = [:]
    private var progressRecordNameByID: [UUID: String] = [:]
    private var customPropertyRecordNameByID: [UUID: String] = [:]

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
            learningObjectives = LearningObjectiveCatalog.defaultObjectives()
            hasLoaded = true
        }
    }

    func loadIfNeeded() async {
        guard hasLoaded == false else { return }
        await reloadAllData()
    }

    func reloadAllData() async {
        isLoading = true
        lastErrorMessage = nil
        groupRecordNameByID.removeAll()
        domainRecordNameByID.removeAll()
        studentRecordNameByID.removeAll()
        progressRecordNameByID.removeAll()
        customPropertyRecordNameByID.removeAll()

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

            let mappedGroups = groupRecords.map { mapGroup(from: $0) }
            let mappedDomains = domainRecords.map { mapDomain(from: $0) }

            let groupMap = dictionaryByRecordName(items: mappedGroups, recordNameLookup: groupRecordNameByID)
            let domainMap = dictionaryByRecordName(items: mappedDomains, recordNameLookup: domainRecordNameByID)

            let studentRecords = try await service.queryRecords(
                ofType: RecordType.student,
                predicate: NSPredicate(format: "cohortRef == %@", cohortRef),
                sortDescriptors: [NSSortDescriptor(key: Field.createdAt, ascending: true)]
            )

            let mappedStudents = studentRecords.map { mapStudent(from: $0, groupMap: groupMap, domainMap: domainMap) }

            let mappedLabels = labelRecords.map { mapCategoryLabel(from: $0) }

            groups = mappedGroups.sorted { $0.name < $1.name }
            domains = mappedDomains.sorted { $0.name < $1.name }
            categoryLabels = mappedLabels.sorted { $0.key < $1.key }
            students = mappedStudents.sorted { $0.createdAt < $1.createdAt }

            progressLoadedStudentIDs.removeAll()
            customPropertiesLoadedStudentIDs.removeAll()

            // Full reload is authoritative; move the incremental sync cursor forward.
            lastSyncDate = Date()
            hasLoaded = true

            startLiveSyncIfNeeded()
        } catch {
            let detail = service.describe(error)
            lastErrorMessage = friendlyMessage(for: error, detail: detail)
        }

        isLoading = false
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

        let recordID = CKRecord.ID(recordName: group.id.uuidString)
        groupRecordNameByID[group.id] = recordID.recordName

        let record = CKRecord(recordType: RecordType.cohortGroup, recordID: recordID)
        record[Field.cohortRef] = CKRecord.Reference(recordID: cohortRecordID, action: .none)
        record[Field.name] = group.name
        record[Field.colorHex] = group.colorHex
        applyAuditFields(to: record, createdAt: Date())

        do {
            let saved = try await service.save(record: record)
            groupRecordNameByID[group.id] = saved.recordID.recordName
            syncCoordinator?.noteLocalWrite()
        } catch {
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

        let affected = students.filter { $0.group?.id == group.id }
        affected.forEach { $0.group = nil }
        groups.removeAll { $0.id == group.id }

        do {
            try await service.delete(recordID: recordID)
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

        let recordID = CKRecord.ID(recordName: domain.id.uuidString)
        domainRecordNameByID[domain.id] = recordID.recordName

        let record = CKRecord(recordType: RecordType.domain, recordID: recordID)
        record[Field.cohortRef] = CKRecord.Reference(recordID: cohortRecordID, action: .none)
        record[Field.name] = domain.name
        record[Field.colorHex] = domain.colorHex
        applyAuditFields(to: record, createdAt: Date())

        do {
            let saved = try await service.save(record: record)
            domainRecordNameByID[domain.id] = saved.recordID.recordName
        } catch {
            domains.removeAll { $0.id == domain.id }
            lastErrorMessage = "Failed to add domain: \(error.localizedDescription)"
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
        student.group = group
        student.session = session
        student.domain = domain

        do {
            try await saveStudentRecord(student)
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
        let previousGroup = student.group
        student.group = group

        do {
            try await saveStudentRecord(student)
        } catch {
            student.group = previousGroup
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
            try await deleteProgress(for: student)
            try await deleteCustomProperties(for: student)
            syncCoordinator?.noteLocalWrite()
        } catch {
            lastErrorMessage = "Failed to delete student: \(error.localizedDescription)"
            await reloadAllData()
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
        if let existing = categoryLabels.first(where: { $0.key == code }) {
            label = existing
            label.title = title
        } else {
            label = CategoryLabel(code: code, title: title)
            categoryLabels.append(label)
        }
        categoryLabels.sort { $0.key < $1.key }

        let recordID = CKRecord.ID(recordName: code)
        let record = CKRecord(recordType: RecordType.categoryLabel, recordID: recordID)
        record[Field.cohortRef] = CKRecord.Reference(recordID: cohortRecordID, action: .none)
        record[Field.key] = label.key
        record[Field.code] = label.code
        record[Field.title] = label.title
        applyAuditFields(to: record, createdAt: Date())

        do {
            try await service.save(record: record)
        } catch {
            lastErrorMessage = "Failed to update category label: \(error.localizedDescription)"
        }
    }

    func loadProgressIfNeeded(for student: Student) async {
        lastErrorMessage = nil
        guard progressLoadedStudentIDs.contains(student.id) == false else { return }
        guard let cohortRecordID else { return }
        let studentRecordID = recordID(for: student, lookup: studentRecordNameByID)

        let cohortRef = CKRecord.Reference(recordID: cohortRecordID, action: .none)
        let studentRef = CKRecord.Reference(recordID: studentRecordID, action: .none)

        do {
            let predicate = NSPredicate(format: "cohortRef == %@ AND student == %@", cohortRef, studentRef)
            let records = try await service.queryRecords(ofType: RecordType.objectiveProgress, predicate: predicate)
            let mapped = records.map { mapProgress(from: $0, student: student) }
            student.progressRecords = mapped.sorted { $0.objectiveCode < $1.objectiveCode }
            progressLoadedStudentIDs.insert(student.id)
        } catch {
            lastErrorMessage = "Failed to load progress: \(error.localizedDescription)"
        }
    }

    func setProgress(student: Student, objectiveCode: String, value: Int) async {
        lastErrorMessage = nil
        guard await requireWriteAccess() else { return }
        guard let cohortRecordID else { return }
        let studentRecordID = recordID(for: student, lookup: studentRecordNameByID)

        let progress: ObjectiveProgress
        if let existing = student.progressRecords.first(where: { $0.objectiveCode == objectiveCode }) {
            progress = existing
            progress.updateCompletion(value)
        } else {
            progress = ObjectiveProgress(objectiveCode: objectiveCode, completionPercentage: value)
            progress.student = student
            student.progressRecords.append(progress)
        }

        let recordID = recordID(for: progress, lookup: progressRecordNameByID)
        let record = CKRecord(recordType: RecordType.objectiveProgress, recordID: recordID)
        record[Field.cohortRef] = CKRecord.Reference(recordID: cohortRecordID, action: .none)
        record[Field.student] = CKRecord.Reference(recordID: studentRecordID, action: .none)
        record[Field.objectiveCode] = progress.objectiveCode
        record[Field.completionPercentage] = progress.completionPercentage
        record[Field.status] = progress.status.rawValue
        record[Field.notes] = progress.notes
        record[Field.lastUpdated] = progress.lastUpdated
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

    func resetAllData() async {
        lastErrorMessage = nil
        guard await requireWriteAccess() else { return }
        isLoading = true

        do {
            guard let cohortRecordID else {
                await reloadAllData()
                return
            }

            try await deleteAllRecords(ofType: RecordType.objectiveProgress, cohortRecordID: cohortRecordID)
            try await deleteAllRecords(ofType: RecordType.studentCustomProperty, cohortRecordID: cohortRecordID)
            try await deleteAllRecords(ofType: RecordType.student, cohortRecordID: cohortRecordID)
            try await deleteAllRecords(ofType: RecordType.categoryLabel, cohortRecordID: cohortRecordID)
            try await deleteAllRecords(ofType: RecordType.cohortGroup, cohortRecordID: cohortRecordID)
            try await deleteAllRecords(ofType: RecordType.domain, cohortRecordID: cohortRecordID)

            await reloadAllData()
            syncCoordinator?.noteLocalWrite()
        } catch {
            lastErrorMessage = "Failed to reset data: \(error.localizedDescription)"
        }

        isLoading = false
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
        let studentRef = CKRecord.Reference(recordID: studentRecordID, action: .none)
        let predicate = NSPredicate(format: "cohortRef == %@ AND student == %@", cohortRef, studentRef)
        let records = try await service.queryRecords(ofType: RecordType.objectiveProgress, predicate: predicate)
        for record in records {
            try await service.delete(recordID: record.recordID)
        }
    }

    private func deleteAllRecords(ofType recordType: String, cohortRecordID: CKRecord.ID) async throws {
        let cohortRef = CKRecord.Reference(recordID: cohortRecordID, action: .none)
        let predicate = NSPredicate(format: "cohortRef == %@", cohortRef)
        let records = try await service.queryRecords(ofType: recordType, predicate: predicate)
        for record in records {
            try await service.delete(recordID: record.recordID)
        }
    }

    private func mapGroup(from record: CKRecord) -> CohortGroup {
        let name = record[Field.name] as? String ?? "Untitled"
        let colorHex = record[Field.colorHex] as? String
        let group = CohortGroup(name: name, colorHex: colorHex)

        if let uuid = UUID(uuidString: record.recordID.recordName) {
            group.id = uuid
            groupRecordNameByID[uuid] = record.recordID.recordName
        } else {
            groupRecordNameByID[group.id] = record.recordID.recordName
        }

        return group
    }

    private func mapDomain(from record: CKRecord) -> Domain {
        let name = record[Field.name] as? String ?? "Untitled"
        let colorHex = record[Field.colorHex] as? String
        let domain = Domain(name: name, colorHex: colorHex)

        if let uuid = UUID(uuidString: record.recordID.recordName) {
            domain.id = uuid
            domainRecordNameByID[uuid] = record.recordID.recordName
        } else {
            domainRecordNameByID[domain.id] = record.recordID.recordName
        }

        return domain
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

        if let uuid = UUID(uuidString: record.recordID.recordName) {
            student.id = uuid
            studentRecordNameByID[uuid] = record.recordID.recordName
        } else {
            studentRecordNameByID[student.id] = record.recordID.recordName
        }

        return student
    }

    private func mapCategoryLabel(from record: CKRecord) -> CategoryLabel {
        let code = record[Field.code] as? String ?? (record[Field.key] as? String ?? record.recordID.recordName)
        let title = record[Field.title] as? String ?? code
        return CategoryLabel(code: code, title: title)
    }

    private func mapProgress(from record: CKRecord, student: Student) -> ObjectiveProgress {
        let objectiveCode = record[Field.objectiveCode] as? String ?? ""
        let percentage = (record[Field.completionPercentage] as? Int)
            ?? (record[Field.completionPercentage] as? NSNumber)?.intValue
            ?? 0
        let notes = record[Field.notes] as? String ?? ""
        let progress = ObjectiveProgress(objectiveCode: objectiveCode, completionPercentage: percentage, notes: notes)
        progress.student = student
        if let lastUpdated = record[Field.lastUpdated] as? Date {
            progress.lastUpdated = lastUpdated
        }
        if let statusRaw = record[Field.status] as? String, let status = ProgressStatus(rawValue: statusRaw) {
            progress.status = status
        }

        if let uuid = UUID(uuidString: record.recordID.recordName) {
            progress.id = uuid
            progressRecordNameByID[uuid] = record.recordID.recordName
        } else {
            progressRecordNameByID[progress.id] = record.recordID.recordName
        }

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

        if let uuid = UUID(uuidString: record.recordID.recordName) {
            property.id = uuid
            customPropertyRecordNameByID[uuid] = record.recordID.recordName
        } else {
            customPropertyRecordNameByID[property.id] = record.recordID.recordName
        }

        return property
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

    private func recordID<T>(for item: T, lookup: [UUID: String]) -> CKRecord.ID where T: Identifiable, T.ID == UUID {
        let recordName = lookup[item.id] ?? item.id.uuidString
        return CKRecord.ID(recordName: recordName)
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

    // MARK: - Live CloudKit Updates

    private func startLiveSyncIfNeeded() {
        guard syncCoordinator == nil else { return }
        // Preview mode does not initialize cohortRecordID; only start after a real load.
        guard hasLoaded else { return }
        syncCoordinator = CloudKitSyncCoordinator(store: self, service: service)
        syncCoordinator?.start()
    }

    func performIncrementalSync() async {
        guard hasLoaded else { return }
        guard let cohortRecordID else { return }

        // Move cursor to the start of this sync window to avoid missing writes that happen mid-sync.
        let syncWindowStart = Date()
        let previousSync = lastSyncDate

        let cohortRef = CKRecord.Reference(recordID: cohortRecordID, action: .none)
        let updatedAfter = previousSync as NSDate

        do {
            // Keep group/domain instances stable by upserting in-place.
            let groupPredicate = NSPredicate(format: "cohortRef == %@ AND modificationDate > %@", cohortRef, updatedAfter)
            let domainPredicate = NSPredicate(format: "cohortRef == %@ AND modificationDate > %@", cohortRef, updatedAfter)
            let labelPredicate = NSPredicate(format: "cohortRef == %@ AND modificationDate > %@", cohortRef, updatedAfter)
            let studentPredicate = NSPredicate(format: "cohortRef == %@ AND modificationDate > %@", cohortRef, updatedAfter)
            let progressPredicate = NSPredicate(format: "cohortRef == %@ AND modificationDate > %@", cohortRef, updatedAfter)
            let customPropPredicate = NSPredicate(format: "cohortRef == %@ AND modificationDate > %@", cohortRef, updatedAfter)

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
            async let studentsChanged = service.queryRecords(
                ofType: RecordType.student,
                predicate: studentPredicate
            )
            async let progressChanged = service.queryRecords(
                ofType: RecordType.objectiveProgress,
                predicate: progressPredicate
            )
            async let customPropsChanged = service.queryRecords(
                ofType: RecordType.studentCustomProperty,
                predicate: customPropPredicate
            )

            let (groupRecords, domainRecords, labelRecords, studentRecords, progressRecords, customPropRecords) =
            try await (groupsChanged, domainsChanged, labelsChanged, studentsChanged, progressChanged, customPropsChanged)

            if groupRecords.isEmpty &&
                domainRecords.isEmpty &&
                labelRecords.isEmpty &&
                studentRecords.isEmpty &&
                progressRecords.isEmpty &&
                customPropRecords.isEmpty {
                lastSyncDate = syncWindowStart
                return
            }

            // Upsert order matters: groups/domains first, then students, then child records.
            applyGroupChanges(groupRecords)
            applyDomainChanges(domainRecords)
            applyCategoryLabelChanges(labelRecords)
            applyStudentChanges(studentRecords)
            applyProgressChanges(progressRecords)
            applyCustomPropertyChanges(customPropRecords)

            // Advance cursor
            lastSyncDate = syncWindowStart
        } catch {
            // Keep it quiet; polling / next activation will retry.
            // Don't overwrite existing user-facing error unless something else does.
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
        case RecordType.objectiveProgress:
            deleteProgressByRecordID(recordID)
        case RecordType.studentCustomProperty:
            deleteCustomPropertyByRecordID(recordID)
        default:
            break
        }
    }

    func reconcileDeletionsFromServer() async {
        guard hasLoaded else { return }
        guard let cohortRecordID else { return }

        let cohortRef = CKRecord.Reference(recordID: cohortRecordID, action: .none)
        let predicate = NSPredicate(format: "cohortRef == %@", cohortRef)

        do {
            async let groupIDs = service.queryRecordIDs(ofType: RecordType.cohortGroup, predicate: predicate)
            async let domainIDs = service.queryRecordIDs(ofType: RecordType.domain, predicate: predicate)
            async let studentIDs = service.queryRecordIDs(ofType: RecordType.student, predicate: predicate)
            async let labelIDs = service.queryRecordIDs(ofType: RecordType.categoryLabel, predicate: predicate)
            async let progressIDs = service.queryRecordIDs(ofType: RecordType.objectiveProgress, predicate: predicate)
            async let customPropIDs = service.queryRecordIDs(ofType: RecordType.studentCustomProperty, predicate: predicate)

            let (remoteGroupIDs, remoteDomainIDs, remoteStudentIDs, remoteLabelIDs, remoteProgressIDs, remoteCustomPropIDs) =
            try await (groupIDs, domainIDs, studentIDs, labelIDs, progressIDs, customPropIDs)

            reconcileGroups(remote: Set(remoteGroupIDs.map(\.recordName)))
            reconcileDomains(remote: Set(remoteDomainIDs.map(\.recordName)))
            reconcileStudents(remote: Set(remoteStudentIDs.map(\.recordName)))
            reconcileLabels(remote: Set(remoteLabelIDs.map(\.recordName)))
            reconcileProgress(remote: Set(remoteProgressIDs.map(\.recordName)))
            reconcileCustomProperties(remote: Set(remoteCustomPropIDs.map(\.recordName)))
        } catch {
            // Ignore; will retry later.
        }
    }

    private func applyRemoteUpsert(recordType: String, record: CKRecord) {
        switch recordType {
        case RecordType.cohortGroup:
            applyGroupChanges([record])
        case RecordType.domain:
            applyDomainChanges([record])
        case RecordType.categoryLabel:
            applyCategoryLabelChanges([record])
        case RecordType.student:
            applyStudentChanges([record])
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

        for record in records {
            let name = record[Field.name] as? String ?? "Untitled"
            let colorHex = record[Field.colorHex] as? String
            let uuid = UUID(uuidString: record.recordID.recordName) ?? UUID()

            if let existing = groups.first(where: { $0.id == uuid }) {
                existing.name = name
                existing.colorHex = colorHex
            } else {
                let g = CohortGroup(name: name, colorHex: colorHex)
                g.id = uuid
                groups.append(g)
            }

            groupRecordNameByID[uuid] = record.recordID.recordName
        }

        groups.sort { $0.name < $1.name }
    }

    private func applyDomainChanges(_ records: [CKRecord]) {
        guard records.isEmpty == false else { return }

        for record in records {
            let name = record[Field.name] as? String ?? "Untitled"
            let colorHex = record[Field.colorHex] as? String
            let uuid = UUID(uuidString: record.recordID.recordName) ?? UUID()

            if let existing = domains.first(where: { $0.id == uuid }) {
                existing.name = name
                existing.colorHex = colorHex
            } else {
                let d = Domain(name: name, colorHex: colorHex)
                d.id = uuid
                domains.append(d)
            }

            domainRecordNameByID[uuid] = record.recordID.recordName
        }

        domains.sort { $0.name < $1.name }
    }

    private func applyCategoryLabelChanges(_ records: [CKRecord]) {
        guard records.isEmpty == false else { return }

        for record in records {
            let code = record[Field.code] as? String ?? (record[Field.key] as? String ?? record.recordID.recordName)
            let title = record[Field.title] as? String ?? code

            if let existing = categoryLabels.first(where: { $0.key == code }) {
                existing.title = title
            } else {
                categoryLabels.append(CategoryLabel(code: code, title: title))
            }
        }

        categoryLabels.sort { $0.key < $1.key }
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

        for record in records {
            let uuid = UUID(uuidString: record.recordID.recordName) ?? UUID()

            let name = record[Field.name] as? String ?? "Unnamed"
            let sessionRaw = record[Field.session] as? String ?? Session.morning.rawValue
            let session = Session(rawValue: sessionRaw) ?? .morning

            let group = (record[Field.group] as? CKRecord.Reference).flatMap { groupByRecordName[$0.recordID.recordName] }
            let domain = (record[Field.domain] as? CKRecord.Reference).flatMap { domainByRecordName[$0.recordID.recordName] }

            let createdAt = (record[Field.createdAt] as? Date) ?? Date()

            if let existing = students.first(where: { $0.id == uuid }) {
                existing.name = name
                existing.session = session
                existing.group = group
                existing.domain = domain
                existing.createdAt = createdAt
            } else {
                let s = Student(name: name, group: group, session: session, domain: domain)
                s.id = uuid
                s.createdAt = createdAt
                students.append(s)
            }

            studentRecordNameByID[uuid] = record.recordID.recordName
        }

        students.sort { $0.createdAt < $1.createdAt }
    }

    private func applyProgressChanges(_ records: [CKRecord]) {
        guard records.isEmpty == false else { return }

        let studentIDByRecordName: [String: UUID] = {
            var map: [String: UUID] = [:]
            for (id, recordName) in studentRecordNameByID {
                map[recordName] = id
            }
            return map
        }()

        for record in records {
            guard let studentRef = record[Field.student] as? CKRecord.Reference else { continue }
            guard let studentID = studentIDByRecordName[studentRef.recordID.recordName] else { continue }
            guard let student = students.first(where: { $0.id == studentID }) else { continue }

            // Only mutate loaded progress arrays to avoid unexpected heavy loads.
            guard progressLoadedStudentIDs.contains(student.id) else {
                continue
            }

            let objectiveCode = record[Field.objectiveCode] as? String ?? ""
            let percentage = (record[Field.completionPercentage] as? Int)
                ?? (record[Field.completionPercentage] as? NSNumber)?.intValue
                ?? 0
            let notes = record[Field.notes] as? String ?? ""
            let lastUpdated = (record[Field.lastUpdated] as? Date) ?? Date()
            let statusRaw = record[Field.status] as? String
            let status = statusRaw.flatMap { ProgressStatus(rawValue: $0) } ?? ObjectiveProgress.calculateStatus(from: percentage)

            let uuid = UUID(uuidString: record.recordID.recordName) ?? UUID()

            if let existing = student.progressRecords.first(where: { $0.id == uuid }) {
                existing.objectiveCode = objectiveCode
                existing.notes = notes
                existing.lastUpdated = lastUpdated
                existing.status = status
                existing.updateCompletion(percentage)
            } else {
                let p = ObjectiveProgress(objectiveCode: objectiveCode, completionPercentage: percentage, notes: notes)
                p.id = uuid
                p.student = student
                p.notes = notes
                p.lastUpdated = lastUpdated
                p.status = status
                student.progressRecords.append(p)
            }

            progressRecordNameByID[uuid] = record.recordID.recordName
            student.progressRecords.sort { $0.objectiveCode < $1.objectiveCode }
        }
    }

    private func applyCustomPropertyChanges(_ records: [CKRecord]) {
        guard records.isEmpty == false else { return }

        let studentIDByRecordName: [String: UUID] = {
            var map: [String: UUID] = [:]
            for (id, recordName) in studentRecordNameByID {
                map[recordName] = id
            }
            return map
        }()

        for record in records {
            guard let studentRef = record[Field.student] as? CKRecord.Reference else { continue }
            guard let studentID = studentIDByRecordName[studentRef.recordID.recordName] else { continue }
            guard let student = students.first(where: { $0.id == studentID }) else { continue }

            guard customPropertiesLoadedStudentIDs.contains(student.id) else {
                continue
            }

            let key = record[Field.key] as? String ?? ""
            let value = record[Field.value] as? String ?? ""
            let sortOrder = (record[Field.sortOrder] as? Int)
                ?? (record[Field.sortOrder] as? NSNumber)?.intValue
                ?? 0

            let uuid = UUID(uuidString: record.recordID.recordName) ?? UUID()

            if let existing = student.customProperties.first(where: { $0.id == uuid }) {
                existing.key = key
                existing.value = value
                existing.sortOrder = sortOrder
            } else {
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
        guard let uuid = UUID(uuidString: recordID.recordName) else { return }
        groups.removeAll { $0.id == uuid }
        groupRecordNameByID.removeValue(forKey: uuid)

        for student in students where student.group?.id == uuid {
            student.group = nil
        }
    }

    private func deleteDomainByRecordID(_ recordID: CKRecord.ID) {
        guard let uuid = UUID(uuidString: recordID.recordName) else { return }
        domains.removeAll { $0.id == uuid }
        domainRecordNameByID.removeValue(forKey: uuid)

        for student in students where student.domain?.id == uuid {
            student.domain = nil
        }
    }

    private func deleteStudentByRecordID(_ recordID: CKRecord.ID) {
        guard let uuid = UUID(uuidString: recordID.recordName) else { return }
        students.removeAll { $0.id == uuid }
        studentRecordNameByID.removeValue(forKey: uuid)
        progressLoadedStudentIDs.remove(uuid)
        customPropertiesLoadedStudentIDs.remove(uuid)
    }

    private func deleteCategoryLabelByRecordID(_ recordID: CKRecord.ID) {
        let key = recordID.recordName
        categoryLabels.removeAll { $0.key == key || $0.code == key }
    }

    private func deleteProgressByRecordID(_ recordID: CKRecord.ID) {
        guard let uuid = UUID(uuidString: recordID.recordName) else { return }
        progressRecordNameByID.removeValue(forKey: uuid)
        for student in students {
            if progressLoadedStudentIDs.contains(student.id) {
                student.progressRecords.removeAll { $0.id == uuid }
            }
        }
    }

    private func deleteCustomPropertyByRecordID(_ recordID: CKRecord.ID) {
        guard let uuid = UUID(uuidString: recordID.recordName) else { return }
        customPropertyRecordNameByID.removeValue(forKey: uuid)
        for student in students {
            if customPropertiesLoadedStudentIDs.contains(student.id) {
                student.customProperties.removeAll { $0.id == uuid }
            }
        }
    }

    private func reconcileGroups(remote: Set<String>) {
        let local = Set(groupRecordNameByID.values)
        let missing = local.subtracting(remote)
        for recordName in missing {
            deleteGroupByRecordID(CKRecord.ID(recordName: recordName))
        }
    }

    private func reconcileDomains(remote: Set<String>) {
        let local = Set(domainRecordNameByID.values)
        let missing = local.subtracting(remote)
        for recordName in missing {
            deleteDomainByRecordID(CKRecord.ID(recordName: recordName))
        }
    }

    private func reconcileStudents(remote: Set<String>) {
        let local = Set(studentRecordNameByID.values)
        let missing = local.subtracting(remote)
        for recordName in missing {
            deleteStudentByRecordID(CKRecord.ID(recordName: recordName))
        }
    }

    private func reconcileLabels(remote: Set<String>) {
        let local = Set(categoryLabels.map { $0.key })
        let missing = local.subtracting(remote)
        for key in missing {
            deleteCategoryLabelByRecordID(CKRecord.ID(recordName: key))
        }
    }

    private func reconcileProgress(remote: Set<String>) {
        let local = Set(progressRecordNameByID.values)
        let missing = local.subtracting(remote)
        for recordName in missing {
            deleteProgressByRecordID(CKRecord.ID(recordName: recordName))
        }
    }

    private func reconcileCustomProperties(remote: Set<String>) {
        let local = Set(customPropertyRecordNameByID.values)
        let missing = local.subtracting(remote)
        for recordName in missing {
            deleteCustomPropertyByRecordID(CKRecord.ID(recordName: recordName))
        }
    }

    private enum RecordType {
        static let cohort = "Cohort"
        static let cohortGroup = "CohortGroup"
        static let domain = "Domain"
        static let categoryLabel = "CategoryLabel"
        static let student = "Student"
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
        static let domain = "domain"
        static let session = "session"
        static let student = "student"
        static let objectiveCode = "objectiveCode"
        static let completionPercentage = "completionPercentage"
        static let status = "status"
        static let notes = "notes"
        static let lastUpdated = "lastUpdated"
        static let value = "value"
        static let sortOrder = "sortOrder"
        static let createdAt = "createdAt"
        static let updatedAt = "updatedAt"
        static let lastEditedByDisplayName = "lastEditedByDisplayName"
    }
}
