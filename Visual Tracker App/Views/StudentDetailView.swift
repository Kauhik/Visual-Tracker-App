import SwiftUI
import SwiftData

struct StudentDetailView: View {
    let student: Student
    @Binding var selectedStudent: Student?

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Student.createdAt) private var students: [Student]
    @Query(sort: \LearningObjective.sortOrder) private var allObjectives: [LearningObjective]

    @State private var showingAddSheet: Bool = false
    @State private var studentPendingDelete: Student?

    private var rootCategories: [LearningObjective] {
        allObjectives
            .filter { $0.parentCode == nil }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private var overallProgress: Int {
        ProgressCalculator.studentOverall(student: student, allObjectives: allObjectives)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                studentHeader

                studentBoardSection

                legendView
                    .padding(.top, 2)

                Divider()
                    .opacity(0.25)

                ForEach(rootCategories) { category in
                    CategorySectionView(
                        categoryObjective: category,
                        student: student,
                        allObjectives: allObjectives
                    )
                }
            }
            .padding(20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
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
    }

    private var studentHeader: some View {
        HStack(spacing: 16) {
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
                .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private var studentBoardSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Student Board")
                    .font(.headline)

                Spacer()

                Button {
                    showingAddSheet = true
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }

            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(students) { boardStudent in
                        let overall = ProgressCalculator.studentOverall(student: boardStudent, allObjectives: allObjectives)

                        StudentCardView(
                            student: boardStudent,
                            overallProgress: overall,
                            isSelected: selectedStudent?.id == boardStudent.id,
                            onSelect: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedStudent = boardStudent
                                }
                            },
                            onRequestDelete: {
                                studentPendingDelete = boardStudent
                            }
                        )
                        .frame(width: 280)
                    }

                    addStudentCard
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private var addStudentCard: some View {
        Button {
            showingAddSheet = true
        } label: {
            VStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundColor(.accentColor)

                Text("Add Student")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(width: 160, height: 120)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help("Add a new student")
    }

    private var legendView: some View {
        HStack(spacing: 18) {
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

            Text("Click the status pill to edit progress")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
    }

    private func addStudent(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }

        let newStudent = Student(name: trimmed)
        modelContext.insert(newStudent)

        do {
            try modelContext.save()
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedStudent = newStudent
            }
        } catch {
            print("Failed to add student: \(error)")
        }
    }

    private func deleteStudent(_ studentToDelete: Student) {
        let deletingSelected = selectedStudent?.id == studentToDelete.id

        modelContext.delete(studentToDelete)

        do {
            try modelContext.save()
            if deletingSelected {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedStudent = students.first
                }
            }
        } catch {
            print("Failed to delete student: \(error)")
        }
    }
}