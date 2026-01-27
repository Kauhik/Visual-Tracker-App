//
//  ObjectiveRowView.swift
//  Visual Tracker App
//
//  Created by Kaushik Manian on 27/1/26.
//

import SwiftUI
import SwiftData

struct ObjectiveRowView: View {
    let objective: LearningObjective
    let student: Student
    let allObjectives: [LearningObjective]
    let indentLevel: Int
    
    @Environment(\.modelContext) private var modelContext
    
    private var progress: ObjectiveProgress? {
        student.progress(for: objective.code)
    }
    
    private var completionPercentage: Int {
        if hasChildren {
            return calculateAggregatePercentage()
        }
        return progress?.completionPercentage ?? 0
    }
    
    private var status: ProgressStatus {
        let percentage = completionPercentage
        return ObjectiveProgress.calculateStatus(from: percentage)
    }

    private var hasChildren: Bool {
        return allObjectives.contains { $0.parentCode == objective.code }
    }
    
    private var childObjectives: [LearningObjective] {
        return allObjectives
            .filter { $0.parentCode == objective.code }
            .sorted { $0.sortOrder < $1.sortOrder }
    }
    
    private func calculateAggregatePercentage() -> Int {
        let children = childObjectives
        if children.isEmpty { return progress?.completionPercentage ?? 0 }
        
        var totalPercentage = 0
        var count = 0
        
        for child in children {
            let childPercentage = getPercentageForObjective(child)
            totalPercentage += childPercentage
            count += 1
        }
        
        return count > 0 ? totalPercentage / count : 0
    }
    
    private func getPercentageForObjective(_ obj: LearningObjective) -> Int {
        let objChildren = allObjectives.filter { $0.parentCode == obj.code }
        if objChildren.isEmpty {
            return student.completionPercentage(for: obj.code)
        }
        
        var total = 0
        for child in objChildren {
            total += getPercentageForObjective(child)
        }
        return objChildren.count > 0 ? total / objChildren.count : 0
    }
    
    private var indentString: String {
        if indentLevel == 0 { return "" }
        var indent = ""
        for i in 0..<indentLevel {
            if i == indentLevel - 1 {
                indent += "|--- "
            } else {
                indent += "|    "
            }
        }
        return indent
    }
    
    var body: some View {
        HStack(spacing: 8) {
            // Indent visualization
            if indentLevel > 0 {
                Text(indentString)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            
            // Code
            Text(objective.code)
                .font(.system(.body, design: .monospaced))
                .fontWeight(.semibold)
                .foregroundColor(.primary)
                .frame(minWidth: 50, alignment: .leading)
            
            // Title
            Text(objective.title)
                .font(.body)
                .foregroundColor(.primary)
                .lineLimit(2)
            
            Spacer()
            
            // Status indicator
            Text(status.indicator)
                .font(.title3)
            
            // Percentage for quantitative objectives
            if objective.isQuantitative || hasChildren {
                Text("\(completionPercentage)%")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(minWidth: 45, alignment: .trailing)
            }
            
            // Edit button for leaf nodes
            if !hasChildren {
                Button(action: {
                    cycleCompletion()
                }) {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.borderless)
                .help("Toggle completion status")
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(indentLevel == 0 ? Color.accentColor.opacity(0.1) : Color.clear)
        )
    }
    
    private func cycleCompletion() {
        let currentPercentage = progress?.completionPercentage ?? 0
        let newPercentage: Int
        
        switch currentPercentage {
        case 0:
            newPercentage = 50
        case 1..<100:
            newPercentage = 100
        default:
            newPercentage = 0
        }
        
        if let existingProgress = progress {
            existingProgress.updateCompletion(newPercentage)
        } else {
            let newProgress = ObjectiveProgress(objectiveCode: objective.code, completionPercentage: newPercentage)
            newProgress.student = student
            modelContext.insert(newProgress)
            student.progressRecords.append(newProgress)
        }
        
        try? modelContext.save()
    }
}
