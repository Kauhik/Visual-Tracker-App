import SwiftUI
import SwiftData

struct StudentDetailView: View {
    @Binding var selectedStudent: Student?

    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Student.createdAt) private var students: [Student]
    @Query(sort: \LearningObjective.sortOrder) private var allObjectives: [LearningObjective]
    @Query(sort: \CohortGroup.name) private var groups: [CohortGroup]

    @State private var showingAddSheet: Bool = false
    @State private var studentPendingDelete: Student?

    @State private var selectedGroupFilter: GroupFilter = .all

    private var rootCategories: [LearningObjective] {
        allObjectives
            .filter { $0.parentCode == nil }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private enum HeaderMode {
        case cohort
        case group(CohortGroup?)
        case student(Student)
    }

    private var headerMode: HeaderMode {
        if let student = selectedStudent {
            return .student(student)
        }

        switch selectedGroupFilter {
        case .all:
            return .cohort
        case .ungrouped:
            return .group(nil)
        case .group(let id):
            if let group = groups.first(where: { $0.id == id }) {
                return .group(group)
            }
            return .cohort
        }
    }

    private var cohortOverall: Int {
        ProgressCalculator.cohortOverall(students: students, allObjectives: allObjectives)
    }

    private var groupStudents: [Student] {
        switch headerMode {
        case .group(let group):
            if let group {
                return students.filter { $0.group?.id == group.id }
            } else {
                return students.filter { $0.group == nil }
            }
        default:
            return []
        }
    }

    private var groupOverall: Int {
        switch headerMode {
        case .group(let group):
            if let group {
                return ProgressCalculator.groupOverall(group: group, students: students, allObjectives: allObjectives)
            } else {
                return ungroupedOverall
            }
        default:
            return 0
        }
    }

    private var ungroupedOverall: Int {
        let ungrouped = students.filter { $0.group == nil }
        guard ungrouped.isEmpty == false else { return 0 }

        var total = 0
        for s in ungrouped {
            total += ProgressCalculator.studentOverall(student: s, allObjectives: allObjectives)
        }
        return total / ungrouped.count
    }

    private var filteredStudents: [Student] {
        switch selectedGroupFilter {
        case .all:
            return students
        case .ungrouped:
            return students.filter { $0.group == nil }
        case .group(let id):
            return students.filter { $0.group?.id == id }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerCard

                studentBoardSection

                if let student = selectedStudent {
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
                } else {
                    Divider()
                        .opacity(0.25)

                    ContentUnavailableView(
                        "No Student Selected",
                        systemImage: "person.crop.circle.badge.questionmark",
                        description: Text("Select a student from the board, or use the filter to view cohort or group progress.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
            }
            .padding(20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showingAddSheet) {
            AddStudentSheet { name, group in
                addStudent(named: name, group: group)
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
            syncFilterToSelectedStudentIfNeeded()
        }
        .onChange(of: selectedStudent?.id) { _, _ in
            syncFilterToSelectedStudentIfNeeded()
        }
    }

    private var headerCard: some View {
        SwiftUI.Group {
            switch headerMode {
            case .cohort:
                cohortModeHeader
            case .group(let group):
                groupModeHeader(group: group)
            case .student(let student):
                studentModeHeader(student: student)
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

    private var cohortModeHeader: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        LinearGradient(
                            colors: [.blue.opacity(0.20), .purple.opacity(0.20)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 64, height: 64)

                Image(systemName: "person.3.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(.accentColor)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Cohort Overview")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("All students")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("Overall Progress")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    Text("\(cohortOverall)%")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(.accentColor)

                    CircularProgressView(progress: Double(cohortOverall) / 100.0)
                        .frame(width: 50, height: 50)
                }
            }
        }
    }

    private func groupModeHeader(group: CohortGroup?) -> some View {
        let title = group?.name ?? "Ungrouped"
        let count = groupStudents.count

        return HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        LinearGradient(
                            colors: [.blue.opacity(0.18), .purple.opacity(0.18)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 64, height: 64)

                Image(systemName: "folder.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(.accentColor)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Group: \(title)")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("\(count) student\(count == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("Group Progress")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    Text("\(groupOverall)%")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(.accentColor)

                    CircularProgressView(progress: Double(groupOverall) / 100.0)
                        .frame(width: 50, height: 50)
                }
            }
        }
    }

    private func studentModeHeader(student: Student) -> some View {
        let groupName = student.group?.name ?? "Ungrouped"
        let overallProgress = ProgressCalculator.studentOverall(student: student, allObjectives: allObjectives)

        let groupBinding = Binding<CohortGroup?>(
            get: { student.group },
            set: { newValue in
                student.group = newValue
                saveContext()
                syncFilterToSelectedStudentIfNeeded()
            }
        )

        return HStack(spacing: 16) {
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

            VStack(alignment: .leading, spacing: 8) {
                Text(student.name)
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text(groupName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack(spacing: 10) {
                    GroupPickerView(title: "Group", selectedGroup: groupBinding)

                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedStudent = nil
                        }
                    } label: {
                        Label("Clear Selection", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Return to cohort or group view based on the current filter")
                }
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
    }

    private var studentBoardSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("Student Board")
                    .font(.headline)

                Spacer()

                filterMenu

                Button {
                    showingAddSheet = true
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }

            if filteredStudents.isEmpty {
                ContentUnavailableView(
                    "No Students in Filter",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text("Change the group filter to see students.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(filteredStudents) { boardStudent in
                            let overall = ProgressCalculator.studentOverall(student: boardStudent, allObjectives: allObjectives)

                            StudentCardView(
                                student: boardStudent,
                                overallProgress: overall,
                                isSelected: selectedStudent?.id == boardStudent.id,
                                groups: groups,
                                onSelect: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        selectedStudent = boardStudent
                                    }
                                },
                                onRequestDelete: {
                                    studentPendingDelete = boardStudent
                                },
                                onMoveToGroup: { group in
                                    move(student: boardStudent, to: group)
                                }
                            )
                            .frame(width: 300)
                        }

                        addStudentCard
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
            }
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

    private var filterMenu: some View {
        Menu {
            Button("All") {
                selectedGroupFilter = .all
                if selectedStudent == nil {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedStudent = nil
                    }
                }
            }

            Divider()

            if groups.isEmpty == false {
                ForEach(groups) { group in
                    Button(group.name) {
                        selectedGroupFilter = .group(group.id)
                        if selectedStudent == nil {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedStudent = nil
                            }
                        }
                    }
                }
                Divider()
            }

            Button("Ungrouped") {
                selectedGroupFilter = .ungrouped
                if selectedStudent == nil {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedStudent = nil
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .foregroundColor(.secondary)

                Text("Filter:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(selectedGroupFilter.title(groups: groups))
                    .font(.caption)
                    .fontWeight(.semibold)

                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .help("Filter student cards by group")
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

    private func addStudent(named name: String, group: CohortGroup?) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }

        let newStudent = Student(name: trimmed, group: group)
        modelContext.insert(newStudent)

        do {
            try modelContext.save()
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedStudent = newStudent
            }
            syncFilterToSelectedStudentIfNeeded()
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
                syncFilterToSelectedStudentIfNeeded()
            }
        } catch {
            print("Failed to delete student: \(error)")
        }
    }

    private func move(student: Student, to group: CohortGroup?) {
        student.group = group
        saveContext()

        if selectedStudent?.id == student.id {
            syncFilterToSelectedStudentIfNeeded()
        }
    }

    private func saveContext() {
        do {
            try modelContext.save()
        } catch {
            print("Failed to save context: \(error)")
        }
    }

    private func syncFilterToSelectedStudentIfNeeded() {
        guard let selected = selectedStudent else { return }
        guard filterContainsStudent(selected) == false else { return }

        if let groupId = selected.group?.id {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedGroupFilter = .group(groupId)
            }
        } else {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedGroupFilter = .ungrouped
            }
        }
    }

    private func filterContainsStudent(_ s: Student) -> Bool {
        switch selectedGroupFilter {
        case .all:
            return true
        case .ungrouped:
            return s.group == nil
        case .group(let id):
            return s.group?.id == id
        }
    }

    private enum GroupFilter: Hashable {
        case all
        case ungrouped
        case group(UUID)

        func title(groups: [CohortGroup]) -> String {
            switch self {
            case .all:
                return "All"
            case .ungrouped:
                return "Ungrouped"
            case .group(let id):
                return groups.first(where: { $0.id == id })?.name ?? "Group"
            }
        }
    }
}
