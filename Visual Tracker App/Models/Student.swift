import Foundation
import SwiftData

enum Session: String, Codable, CaseIterable {
    case morning = "Morning"
    case afternoon = "Afternoon"
}

enum OverallProgressMode: String, Codable, CaseIterable {
    case computed = "computed"
    case manual = "manual"
}

@Model
final class Student {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    var session: Session
    var overallProgressMode: String?
    var overallManualProgress: Int?
    var overallManualProgressUpdatedAt: Date?
    var overallManualProgressEditedByDisplayName: String?

    @Relationship(deleteRule: .cascade, inverse: \ObjectiveProgress.student)
    var progressRecords: [ObjectiveProgress] = []

    @Relationship(deleteRule: .cascade, inverse: \StudentCustomProperty.student)
    var customProperties: [StudentCustomProperty] = []

    // Keep these as plain properties to avoid relationship macro circular expansion issues
    var group: CohortGroup?
    var domain: Domain?

    init(
        name: String,
        group: CohortGroup? = nil,
        session: Session = .morning,
        domain: Domain? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.group = group
        self.session = session
        self.domain = domain
        self.overallProgressMode = nil
        self.overallManualProgress = nil
        self.overallManualProgressUpdatedAt = nil
        self.overallManualProgressEditedByDisplayName = nil
    }

    var resolvedOverallProgressMode: OverallProgressMode {
        OverallProgressMode(rawValue: overallProgressMode ?? "") ?? .computed
    }

    func progress(for objectiveCode: String) -> ObjectiveProgress? {
        return progressRecords.first { $0.objectiveCode == objectiveCode }
    }

    func progress(for objective: LearningObjective) -> ObjectiveProgress? {
        return progressRecords.first { progress in
            if let objectiveId = progress.objectiveId {
                return objectiveId == objective.id
            }
            return progress.objectiveCode == objective.code
        }
    }

    func completionPercentage(for objectiveCode: String) -> Int {
        return progress(for: objectiveCode)?.value ?? 0
    }

    func completionPercentage(for objective: LearningObjective) -> Int {
        return progress(for: objective)?.value ?? 0
    }
}
