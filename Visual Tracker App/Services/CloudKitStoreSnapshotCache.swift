import Foundation

struct CloudKitStoreSnapshot: Codable {
    static let currentSchemaVersion: Int = 1

    struct Group: Codable {
        let id: UUID
        let name: String
        let colorHex: String?
        let recordName: String
    }

    struct Domain: Codable {
        let id: UUID
        let name: String
        let colorHex: String?
        let progressMode: String?
        let criteriaProgressUpdatedAt: Date?
        let criteriaProgressEditedByDisplayName: String?
        let recordName: String
    }

    struct CategoryLabel: Codable {
        let code: String
        let title: String
        let recordName: String
    }

    struct LearningObjective: Codable {
        let id: UUID
        let code: String
        let title: String
        let objectiveDescription: String
        let isQuantitative: Bool
        let parentCode: String?
        let parentId: UUID?
        let sortOrder: Int
        let isArchived: Bool
        let recordName: String
    }

    struct Student: Codable {
        let id: UUID
        let name: String
        let createdAt: Date
        let sessionRawValue: String
        let groupID: UUID?
        let domainID: UUID?
        let overallProgressMode: String?
        let overallManualProgress: Int?
        let overallManualProgressUpdatedAt: Date?
        let overallManualProgressEditedByDisplayName: String?
        let recordName: String
    }

    struct Membership: Codable {
        let id: UUID
        let studentID: UUID
        let groupID: UUID
        let createdAt: Date
        let updatedAt: Date
        let recordName: String
    }

    struct ObjectiveProgress: Codable {
        let id: UUID
        let studentID: UUID
        let objectiveId: UUID?
        let objectiveCode: String
        let value: Int
        let notes: String
        let lastUpdated: Date
        let statusRawValue: String
        let recordName: String
    }

    struct ExpertiseCheckProgress: Codable {
        let id: UUID
        let domainID: UUID
        let objectiveId: UUID?
        let objectiveCode: String
        let value: Int
        let statusRawValue: String
        let updatedAt: Date
        let editedByDisplayName: String?
        let recordName: String
    }

    let schemaVersion: Int
    let savedAt: Date
    let cohortRecordName: String?
    let lastSyncDate: Date
    let groups: [Group]
    let domains: [Domain]
    let categoryLabels: [CategoryLabel]
    let learningObjectives: [LearningObjective]
    let students: [Student]
    let memberships: [Membership]
    let objectiveProgress: [ObjectiveProgress]
    let expertiseCheckProgress: [ExpertiseCheckProgress]?
}

enum CloudKitStoreSnapshotCache {
    private static func snapshotURL(cohortId: String) throws -> URL {
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let bundleID = Bundle.main.bundleIdentifier ?? "VisualTrackerApp"
        let sanitizedCohortID = cohortId.replacingOccurrences(of: "/", with: "_")
        let directory = applicationSupport
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("Snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("cloudkit-store-\(sanitizedCohortID).json")
    }

    static func load(cohortId: String) -> CloudKitStoreSnapshot? {
        do {
            let url = try snapshotURL(cohortId: cohortId)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let snapshot = try decoder.decode(CloudKitStoreSnapshot.self, from: data)
            guard snapshot.schemaVersion == CloudKitStoreSnapshot.currentSchemaVersion else {
                return nil
            }
            return snapshot
        } catch {
            return nil
        }
    }

    static func save(_ snapshot: CloudKitStoreSnapshot, cohortId: String) throws {
        let url = try snapshotURL(cohortId: cohortId)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        try data.write(to: url, options: [.atomic])
    }
}
