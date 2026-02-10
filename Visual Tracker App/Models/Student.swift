import Foundation
import SwiftData

enum Session: String, Codable, CaseIterable {
    case morning = "Morning"
    case afternoon = "Afternoon"
}

@Model
final class Student {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    var session: Session

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
