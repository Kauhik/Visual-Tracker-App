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
    var objectiveCode: String
    var completionPercentage: Int
    var status: ProgressStatus
    var notes: String
    var lastUpdated: Date
    
    var student: Student?
    
    init(objectiveCode: String, completionPercentage: Int = 0, notes: String = "") {
        self.id = UUID()
        self.objectiveCode = objectiveCode
        self.completionPercentage = max(0, min(100, completionPercentage))
        self.notes = notes
        self.lastUpdated = Date()
        self.status = ObjectiveProgress.calculateStatus(from: completionPercentage)
    }
    
    static func calculateStatus(from percentage: Int) -> ProgressStatus {
        switch percentage {
        case 0: return .notStarted
        case 100: return .complete
        default: return .inProgress
        }
    }
    
    func updateCompletion(_ percentage: Int) {
        self.completionPercentage = max(0, min(100, percentage))
        self.status = ObjectiveProgress.calculateStatus(from: self.completionPercentage)
        self.lastUpdated = Date()
    }
}