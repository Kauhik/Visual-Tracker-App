//
//  ContentView.swift
//  Visual Tracker App
//
//  Created by Kaushik Manian on 27/1/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var students: [Student]
    
    var body: some View {
        NavigationStack {
            Group {
                if let firstStudent = students.first {
                    StudentDetailView(student: firstStudent)
                } else {
                    ContentUnavailableView(
                        "No Students",
                        systemImage: "person.crop.circle.badge.questionmark",
                        description: Text("No student data found. The app will seed sample data on first launch.")
                    )
                }
            }
            .navigationTitle("Visual Tracker")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Reset Data") {
                            resetData()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }
    
    private func resetData() {
        // Delete all existing data
        do {
            try modelContext.delete(model: ObjectiveProgress.self)
            try modelContext.delete(model: Student.self)
            try modelContext.delete(model: LearningObjective.self)
            try modelContext.save()
            
            // Re-seed
            SeedDataService.seedIfNeeded(modelContext: modelContext)
        } catch {
            print("Failed to reset data: \(error)")
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Student.self, LearningObjective.self, ObjectiveProgress.self], inMemory: true)
}
