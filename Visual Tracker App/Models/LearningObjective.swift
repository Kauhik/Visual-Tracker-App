//
//  LearningObjective.swift
//  Visual Tracker App
//
//  Created by Kaushik Manian on 27/1/26.
//

import Foundation
import SwiftData

@Model
final class LearningObjective {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var code: String
    var title: String
    var objectiveDescription: String
    var isQuantitative: Bool
    var parentCode: String?
    var sortOrder: Int
    
    init(code: String, title: String, description: String = "", isQuantitative: Bool = false, parentCode: String? = nil, sortOrder: Int = 0) {
        self.id = UUID()
        self.code = code
        self.title = title
        self.objectiveDescription = description
        self.isQuantitative = isQuantitative
        self.parentCode = parentCode
        self.sortOrder = sortOrder
    }
    
    var isRootCategory: Bool {
        return parentCode == nil
    }
    
    var depth: Int {
        let parts = code.split(separator: ".")
        return parts.count - 1
    }
    
    var categoryLetter: String {
        return String(code.prefix(1))
    }
}