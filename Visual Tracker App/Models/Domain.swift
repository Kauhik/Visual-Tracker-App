import Foundation
import SwiftData

enum ExpertiseCheckProgressMode: String, Codable, CaseIterable {
    case computed = "computed"
    case criteria = "criteria"
}

@Model
final class Domain {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var name: String
    var colorHex: String?
    var progressMode: String?
    var criteriaProgressUpdatedAt: Date?
    var criteriaProgressEditedByDisplayName: String?

    init(
        name: String,
        colorHex: String? = nil,
        progressMode: String? = nil,
        criteriaProgressUpdatedAt: Date? = nil,
        criteriaProgressEditedByDisplayName: String? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.colorHex = colorHex
        self.progressMode = progressMode
        self.criteriaProgressUpdatedAt = criteriaProgressUpdatedAt
        self.criteriaProgressEditedByDisplayName = criteriaProgressEditedByDisplayName
    }

    var resolvedProgressMode: ExpertiseCheckProgressMode {
        ExpertiseCheckProgressMode(rawValue: progressMode ?? "") ?? .computed
    }
}
