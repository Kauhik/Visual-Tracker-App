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
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)

            List(selection: $selectedStudent) {
                Section {
                    ForEach(students) { student in
                        studentRow(student)
                            .tag(student as Student?)
                            .contextMenu {
                                Button("Delete Student", role: .destructive) {
                                    studentPendingDelete = student
                                }
                            }
                    }
                } header: {
                    Text("Students")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section {
                    cohortOverviewRow
                        .selectionDisabled(true)

                    ForEach(rootCategories) { category in
                        cohortCategoryRow(category)
                            .selectionDisabled(true)
                    }
                } header: {
                    Text("Cohort Overview")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .listStyle(.sidebar)
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

    private func studentRow(_ student: Student) -> some View {
        let overall = ProgressCalculator.studentOverall(student: student, allObjectives: allObjectives)

        return HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 28, height: 28)

                Text(student.name.prefix(1).uppercased())
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }

            Text(student.name)
                .font(.body)
                .foregroundColor(.primary)
                .lineLimit(1)

            Spacer()

            HStack(spacing: 8) {
                CircularProgressView(progress: Double(overall) / 100.0)
                    .frame(width: 18, height: 18)

                Text("\(overall)%")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private var cohortOverviewRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Overall")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("\(cohortOverall)%")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.accentColor)
            }

            Spacer()

            CircularProgressView(progress: Double(cohortOverall) / 100.0)
                .frame(width: 34, height: 34)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .listRowInsets(EdgeInsets(top: 8, leading: 10, bottom: 6, trailing: 10))
    }

    private func cohortCategoryRow(_ category: LearningObjective) -> some View {
        let value = ProgressCalculator.cohortObjectiveAverage(
            objectiveCode: category.code,
            students: students,
            allObjectives: allObjectives
        )

        return HStack(spacing: 10) {
            Text(category.code)
                .font(.system(.caption, design: .rounded))
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(categoryColor(for: category.code))
                )

            Text(category.title)
                .font(.caption)
                .foregroundColor(.primary)
                .lineLimit(1)

            Spacer()

            Text("\(value)%")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(categoryColor(for: category.code).opacity(0.10))
        )
        .listRowInsets(EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10))
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