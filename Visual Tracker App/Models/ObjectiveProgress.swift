//
//  ObjectiveProgress.swift
//  Visual Tracker App
//
//  Created by Kaushik Manian on 27/1/26.
//

import Foundation
import SwiftData

enum ProgressStatus: String, Codable, CaseIterable {
    case notStarted = "Not Started"
    case inProgress = "In Progress"
    case complete = "Complete"
    
    var indicator: String {
        switch self {
        case .notStarted: return "⬜"
        case .inProgress: return "☑️"
        case .complete: return "✅"
        }
    }
}

@Model
final class ObjectiveProgress {
    @Attribute(.unique) var id: UUID
    var objectiveId: UUID?
    var objectiveCode: String
    var value: Int
    var completionPercentage: Int
    var status: ProgressStatus
    var notes: String
    var lastUpdated: Date
    
    var student: Student?
    
    init(
        objectiveCode: String,
        completionPercentage: Int = 0,
        notes: String = "",
        objectiveId: UUID? = nil,
        value: Int? = nil
    ) {
        let canonicalValue = max(0, min(100, value ?? completionPercentage))
        self.id = UUID()
        self.objectiveId = objectiveId
        self.objectiveCode = objectiveCode
        self.value = canonicalValue
        self.completionPercentage = canonicalValue
        self.notes = notes
        self.lastUpdated = Date()
        self.status = ObjectiveProgress.calculateStatus(from: canonicalValue)
    }
    
    static func calculateStatus(from percentage: Int) -> ProgressStatus {
        switch percentage {
        case 0: return .notStarted
        case 100: return .complete
        default: return .inProgress
        }
    }
    
    func updateCompletion(_ percentage: Int) {
        let canonicalValue = max(0, min(100, percentage))
        self.value = canonicalValue
        self.completionPercentage = canonicalValue
        self.status = ObjectiveProgress.calculateStatus(from: canonicalValue)
        self.lastUpdated = Date()
    }
}
