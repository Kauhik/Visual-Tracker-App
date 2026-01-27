import SwiftUI
import SwiftData

struct StudentOverviewBoard: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Student.createdAt) private var students: [Student]
    @Query(sort: \LearningObjective.sortOrder) private var allObjectives: [LearningObjective]

    @Binding var selectedStudent: Student?

    @State private var showingAddSheet: Bool = false
    @State private var studentPendingDelete: Student?

    private var rootCategories: [LearningObjective] {
        allObjectives
            .filter { $0.parentCode == nil }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private var cohortOverall: Int {
        ProgressCalculator.cohortOverall(students: students, allObjectives: allObjectives)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if students.isEmpty {
                    emptyState
                } else {
                    cohortOverviewSection
                    studentsGrid
                }
            }
            .padding(16)
        }
        .sheet(isPresented: $showingAddSheet) {
            AddStudentSheet { name in
                addStudent(named: name)
            }
        }
        .confirmationDialog(
            "Delete Student",
            isPresented: Binding(
                get: { studentPendingDelete != nil },
                set: { if $0 == false { studentPendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let student = studentPendingDelete {
                    deleteStudent(student)
                }
                studentPendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                studentPendingDelete = nil
            }
        } message: {
            if let student = studentPendingDelete {
                Text("Delete \(student.name)? This action cannot be undone.")
            }
        }
        .onAppear {
            if selectedStudent == nil {
                selectedStudent = students.first
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Students")
                    .font(.title2)
                    .fontWeight(.bold)

                Text(students.isEmpty ? "No students yet" : "\(students.count) student\(students.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button {
                showingAddSheet = true
            } label: {
                Label("Add Student", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            ContentUnavailableView(
                "No Students",
                systemImage: "person.3",
                description: Text("Add a student to start tracking progress across the fixed learning objectives.")
            )

            Button {
                showingAddSheet = true
            } label: {
                Label("Add Student", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 6)
    }

    private var cohortOverviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cohort Overview")
                .font(.headline)

            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Overall")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(spacing: 10) {
                        Text("\(cohortOverall)%")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(.accentColor)

                        CircularProgressView(progress: Double(cohortOverall) / 100.0)
                            .frame(width: 44, height: 44)
                    }
                }

                Spacer()
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )

            VStack(spacing: 8) {
                ForEach(rootCategories) { category in
                    let value = ProgressCalculator.cohortObjectiveAverage(
                        objectiveCode: category.code,
                        students: students,
                        allObjectives: allObjectives
                    )

                    HStack(spacing: 10) {
                        Text(category.code)
                            .font(.system(.subheadline, design: .rounded))
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(categoryColor(for: category.code))
                            )

                        Text(category.title)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        Spacer()

                        Text("\(value)%")
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(categoryColor(for: category.code).opacity(0.10))
                    )
                }
            }
        }
    }

    private var studentsGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Student Board")
                .font(.headline)

            let columns = [
                GridItem(.adaptive(minimum: 260), spacing: 12, alignment: .top)
            ]

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(students) { student in
                    let overall = ProgressCalculator.studentOverall(student: student, allObjectives: allObjectives)

                    StudentCardView(
                        student: student,
                        overallProgress: overall,
                        isSelected: selectedStudent?.id == student.id,
                        onSelect: {
                            selectedStudent = student
                        },
                        onRequestDelete: {
                            studentPendingDelete = student
                        }
                    )
                }
            }
        }
        .padding(.top, 6)
    }

    private func addStudent(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }

        let newStudent = Student(name: trimmed)
        modelContext.insert(newStudent)

        do {
            try modelContext.save()
            selectedStudent = newStudent
        } catch {
            print("Failed to add student: \(error)")
        }
    }

    private func deleteStudent(_ student: Student) {
        if selectedStudent?.id == student.id {
            selectedStudent = nil
        }

        modelContext.delete(student)

        do {
            try modelContext.save()
            if selectedStudent == nil {
                selectedStudent = students.first
            }
        } catch {
            print("Failed to delete student: \(error)")
        }
    }

    private func categoryColor(for code: String) -> Color {
        switch code {
        case "A": return .blue
        case "B": return .green
        case "C": return .orange
        case "D": return .purple
        case "E": return .pink
        default: return .gray
        }
    }
}