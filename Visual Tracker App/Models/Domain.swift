import Foundation
import SwiftData

enum ExpertiseCheckOverallMode: String, Codable, CaseIterable {
    case computed
    case expertReview
}

@Model
final class Domain {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var name: String
    var colorHex: String?
    var overallModeRaw: String

    var overallMode: ExpertiseCheckOverallMode {
        get { ExpertiseCheckOverallMode(rawValue: overallModeRaw) ?? .computed }
        set { overallModeRaw = newValue.rawValue }
    }

    init(name: String, colorHex: String? = nil, overallMode: ExpertiseCheckOverallMode = .computed) {
        self.id = UUID()
        self.name = name
        self.colorHex = colorHex
        self.overallModeRaw = overallMode.rawValue
    }
}

@Model
final class ExpertiseCheckObjectiveScore {
    @Attribute(.unique) var id: UUID
    var expertiseCheckId: UUID?
    var objectiveId: UUID?
    var objectiveCode: String
    var value: Int
    var statusRawValue: String
    var createdAt: Date
    var updatedAt: Date
    var lastEditedByDisplayName: String?

    var status: ProgressStatus {
        get { ProgressStatus(rawValue: statusRawValue) ?? ObjectiveProgress.calculateStatus(from: value) }
        set { statusRawValue = newValue.rawValue }
    }

    init(
        expertiseCheckId: UUID?,
        objectiveId: UUID?,
        objectiveCode: String,
        value: Int,
        status: ProgressStatus? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastEditedByDisplayName: String? = nil
    ) {
        let canonicalValue = max(0, min(100, value))
        self.id = UUID()
        self.expertiseCheckId = expertiseCheckId
        self.objectiveId = objectiveId
        self.objectiveCode = objectiveCode
        self.value = canonicalValue
        self.statusRawValue = (status ?? ObjectiveProgress.calculateStatus(from: canonicalValue)).rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastEditedByDisplayName = lastEditedByDisplayName
    }
}
