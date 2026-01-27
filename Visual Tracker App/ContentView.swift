import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Student.createdAt) private var students: [Student]

    @State private var selectedStudent: Student?

    var body: some View {
        NavigationSplitView {
            StudentOverviewBoard(selectedStudent: $selectedStudent)
                .navigationTitle("Students")
        } detail: {
            Group {
                if let student = selectedStudent {
                    StudentDetailView(student: student)
                } else if students.isEmpty {
                    ContentUnavailableView(
                        "No Students",
                        systemImage: "person.3",
                        description: Text("Add a student to start tracking progress.")
                    )
                } else {
                    ContentUnavailableView(
                        "Select a Student",
                        systemImage: "person.crop.circle",
                        description: Text("Choose a student from the sidebar to view and edit progress.")
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
            try modelContext.save()

            selectedStudent = nil

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
        .modelContainer(for: [Student.self, LearningObjective.self, ObjectiveProgress.self], inMemory: true)
}
