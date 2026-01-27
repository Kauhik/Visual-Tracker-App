//
//  Student.swift
//  Visual Tracker App
//
//  Created by Kaushik Manian on 27/1/26.
//

import Foundation
import SwiftData

@Model
final class Student {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    
    @Relationship(deleteRule: .cascade, inverse: \ObjectiveProgress.student)
    var progressRecords: [ObjectiveProgress] = []
    
    init(name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
    }
    
    func progress(for objectiveCode: String) -> ObjectiveProgress? {
        return progressRecords.first { $0.objectiveCode == objectiveCode }
    }
    
    func completionPercentage(for objectiveCode: String) -> Int {
        return progress(for: objectiveCode)?.completionPercentage ?? 0
    }
}