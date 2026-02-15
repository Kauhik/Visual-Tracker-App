import Foundation

struct CohortSheet: Identifiable, Equatable, Hashable {
    let id: String // CloudKit recordName
    var cohortId: String
    var name: String
    var createdAt: Date
    var updatedAt: Date
}
