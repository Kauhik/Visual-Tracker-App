import Foundation

final class ExpertiseCheckProgress: Identifiable {
    var id: UUID
    var domainId: UUID
    var objectiveId: UUID?
    var objectiveCode: String
    var value: Int
    var status: ProgressStatus
    var updatedAt: Date
    var editedByDisplayName: String?

    init(
        domainId: UUID,
        objectiveId: UUID?,
        objectiveCode: String,
        value: Int,
        updatedAt: Date = Date(),
        editedByDisplayName: String? = nil
    ) {
        let canonicalValue = max(0, min(100, value))
        self.id = UUID()
        self.domainId = domainId
        self.objectiveId = objectiveId
        self.objectiveCode = objectiveCode
        self.value = canonicalValue
        self.status = ObjectiveProgress.calculateStatus(from: canonicalValue)
        self.updatedAt = updatedAt
        self.editedByDisplayName = editedByDisplayName
    }

    func updateValue(_ newValue: Int, editedByDisplayName: String?) {
        let canonicalValue = max(0, min(100, newValue))
        value = canonicalValue
        status = ObjectiveProgress.calculateStatus(from: canonicalValue)
        updatedAt = Date()
        self.editedByDisplayName = editedByDisplayName
    }
}
