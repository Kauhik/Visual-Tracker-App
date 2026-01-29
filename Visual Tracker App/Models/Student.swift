import Foundation
import SwiftData

enum Session: String, Codable, CaseIterable {
    case morning = "Morning"
    case afternoon = "Afternoon"
}

enum Domain: String, Codable, CaseIterable {
    case design = "Design"
    case tech = "Tech"
}

@Model
final class Student {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    var session: Session
    var domain: Domain

    @Relationship(deleteRule: .cascade, inverse: \ObjectiveProgress.student)
    var progressRecords: [ObjectiveProgress] = []

    @Relationship(deleteRule: .cascade, inverse: \StudentCustomProperty.student)
    var customProperties: [StudentCustomProperty] = []

    // Keep this as a plain property to avoid SwiftData relationship macro circular expansion
    var group: CohortGroup?

    init(name: String, group: CohortGroup? = nil, session: Session = .morning, domain: Domain = .tech) {
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

    func completionPercentage(for objectiveCode: String) -> Int {
        return progress(for: objectiveCode)?.completionPercentage ?? 0
    }
}
