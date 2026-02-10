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
    var parentId: UUID?
    var sortOrder: Int
    var isArchived: Bool

    init(
        code: String,
        title: String,
        description: String = "",
        isQuantitative: Bool = false,
        parentCode: String? = nil,
        parentId: UUID? = nil,
        sortOrder: Int = 0,
        isArchived: Bool = false
    ) {
        self.id = UUID()
        self.code = code
        self.title = title
        self.objectiveDescription = description
        self.isQuantitative = isQuantitative
        self.parentCode = parentCode
        self.parentId = parentId
        self.sortOrder = sortOrder
        self.isArchived = isArchived
    }
    
    var isRootCategory: Bool {
        return parentId == nil && parentCode == nil
    }

    func isChild(of parent: LearningObjective) -> Bool {
        if let parentId {
            return parentId == parent.id
        }
        return parentCode == parent.code
    }
    
    var depth: Int {
        let parts = code.split(separator: ".")
        return parts.count - 1
    }
    
    var categoryLetter: String {
        return String(code.prefix(1))
    }
}
