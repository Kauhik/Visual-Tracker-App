import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Student.createdAt) private var students: [Student]

    @State private var selectedStudent: Student?
    @State private var selectedGroup: CohortGroup?

    var body: some View {
        NavigationSplitView {
            StudentOverviewBoard(selectedStudent: $selectedStudent)
                .navigationTitle("Students")
        } detail: {
            SwiftUI.Group {
                if students.isEmpty {
                    ContentUnavailableView(
                        "No Students",
                        systemImage: "person.3",
                        description: Text("Add a student to start tracking progress.")
                    )
                } else {
                    StudentDetailView(
                        selectedStudent: $selectedStudent,
                        selectedGroup: $selectedGroup
                    )
                }
            }
            .navigationTitle("Visual Tracker")
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Reset Data", role: .destructive) {
                        resetData()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onAppear {
            if selectedStudent == nil, let first = students.first {
                selectedStudent = first
            }
        }
        .onChange(of: students.count) { _, _ in
            if let selected = selectedStudent, students.contains(where: { $0.id == selected.id }) == false {
                selectedStudent = students.first
            } else if selectedStudent == nil, let first = students.first {
                selectedStudent = first
            }
        }
    }

    private func resetData() {
        do {
            try modelContext.delete(model: ObjectiveProgress.self)
            try modelContext.delete(model: Student.self)
            try modelContext.delete(model: LearningObjective.self)
            try modelContext.delete(model: CohortGroup.self)
            try modelContext.save()

            selectedStudent = nil
            selectedGroup = nil

            SeedDataService.seedIfNeeded(modelContext: modelContext)

            if let first = students.first {
                selectedStudent = first
            }
        } catch {
            print("Failed to reset data: \(error)")
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Student.self, LearningObjective.self, ObjectiveProgress.self, CohortGroup.self, CategoryLabel.self, StudentCustomProperty.self], inMemory: true)
}
