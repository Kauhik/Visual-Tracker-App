import Foundation
import SwiftData

@Model
final class Student {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \ObjectiveProgress.student)
    var progressRecords: [ObjectiveProgress] = []

    // Keep this as a plain property to avoid SwiftData relationship macro circular expansion
    var group: CohortGroup?

    init(name: String, group: CohortGroup? = nil) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.group = group
    }

    func progress(for objectiveCode: String) -> ObjectiveProgress? {
        return progressRecords.first { $0.objectiveCode == objectiveCode }
    }

    func completionPercentage(for objectiveCode: String) -> Int {
        return progress(for: objectiveCode)?.completionPercentage ?? 0
    }
}
