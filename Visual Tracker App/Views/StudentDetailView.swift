//
//  StudentDetailView.swift
//  Visual Tracker App
//
//  Created by Kaushik Manian on 27/1/26.
//

import SwiftUI
import SwiftData

struct StudentDetailView: View {
    let student: Student
    
    @Query(sort: \LearningObjective.sortOrder) private var allObjectives: [LearningObjective]
    
    private var rootCategories: [LearningObjective] {
        return allObjectives
            .filter { $0.parentCode == nil }
            .sorted { $0.sortOrder < $1.sortOrder }
    }
    
    private var overallProgress: Int {
        guard !rootCategories.isEmpty else { return 0 }
        var total = 0
        for category in rootCategories {
            total += calculateCategoryPercentage(for: category)
        }
        return total / rootCategories.count
    }
    
    private func calculateCategoryPercentage(for objective: LearningObjective) -> Int {
        let children = allObjectives.filter { $0.parentCode == objective.code }
        if children.isEmpty {
            return student.completionPercentage(for: objective.code)
        }
        
        var total = 0
        for child in children {
            total += calculateCategoryPercentage(for: child)
        }
        return children.count > 0 ? total / children.count : 0
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Student Header
                studentHeader
                
                // Legend
                legendView
                
                Divider()
                
                // Category Sections
                ForEach(rootCategories) { category in
                    CategorySectionView(
                        categoryObjective: category,
                        student: student,
                        allObjectives: allObjectives
                    )
                }
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    private var studentHeader: some View {
        HStack(spacing: 16) {
            // Avatar
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 64, height: 64)
                
                Text(student.name.prefix(1).uppercased())
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(student.name)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Challenge-Based Learning Progress")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Overall Progress
            VStack(alignment: .trailing, spacing: 4) {
                Text("Overall Progress")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 8) {
                    Text("\(overallProgress)%")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(.accentColor)
                    
                    CircularProgressView(progress: Double(overallProgress) / 100.0)
                        .frame(width: 50, height: 50)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
        )
    }
    
    private var legendView: some View {
        HStack(spacing: 24) {
            Text("Legend:")
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack(spacing: 6) {
                Text("✅")
                Text("Complete (100%)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack(spacing: 6) {
                Text("☑️")
                Text("In Progress (1-99%)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack(spacing: 6) {
                Text("⬜")
                Text("Not Started (0%)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text("Click the slider icon to toggle completion")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
    }
}

struct CircularProgressView: View {
    let progress: Double
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.2), lineWidth: 6)
            
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.3), value: progress)
        }
    }
}