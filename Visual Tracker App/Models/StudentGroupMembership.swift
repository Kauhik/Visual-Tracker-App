import Foundation
import SwiftData

@Model
final class StudentGroupMembership {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var updatedAt: Date

    var student: Student?
    var group: CohortGroup?

    init(student: Student?, group: CohortGroup?, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = UUID()
        self.student = student
        self.group = group
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
