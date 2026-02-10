//
//  ObjectiveTreeView.swift
//  Visual Tracker App
//
//  Created by Kaushik Manian on 27/1/26.
//

import SwiftUI

struct ObjectiveTreeView: View {
    let rootObjective: LearningObjective
    let student: Student
    let allObjectives: [LearningObjective]
    let startIndentLevel: Int

    @Environment(ZoomManager.self) private var zoomManager
    
    private var childObjectives: [LearningObjective] {
        return allObjectives
            .filter { $0.isChild(of: rootObjective) && $0.isArchived == false }
            .sorted { $0.sortOrder < $1.sortOrder }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: zoomManager.scaled(2)) {
            // Display the root objective
            ObjectiveRowView(
                objective: rootObjective,
                student: student,
                allObjectives: allObjectives,
                indentLevel: startIndentLevel
            )
            
            // Recursively display children
            ForEach(childObjectives) { child in
                ObjectiveTreeView(
                    rootObjective: child,
                    student: student,
                    allObjectives: allObjectives,
                    startIndentLevel: startIndentLevel + 1
                )
            }
        }
    }
}
