import SwiftUI
import SwiftData

struct StudentDetailView: View {
    @Binding var selectedStudent: Student?
    @Binding var selectedGroup: CohortGroup?

    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Student.createdAt) private var students: [Student]
    @Query(sort: \LearningObjective.sortOrder) private var allObjectives: [LearningObjective]
    @Query(sort: \CohortGroup.name) private var groups: [CohortGroup]
    @Query(sort: \CategoryLabel.key) private var categoryLabels: [CategoryLabel]

    @State private var showingAddSheet: Bool = false
    @State private var studentPendingDelete: Student?

    @State private var selectedGroupFilter: GroupFilter = .all
    @State private var isSwitchingScope: Bool = false

    @State private var editingCategoryTarget: CategoryEditTarget?

    private var rootCategories: [LearningObjective] {
        allObjectives
            .filter { $0.parentCode == nil }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private var ungroupedStudents: [Student] {
        students.filter { $0.group == nil }
    }

    private var filteredStudents: [Student] {
        switch selectedGroupFilter {
        case .all:
            return students
        case .ungrouped:
            return ungroupedStudents
        case .group(let id):
            return students.filter { $0.group?.id == id }
        }
    }

    private var breakdownStudents: [Student] {
        filteredStudents
    }

    private var eligibleStudentCount: Int {
        breakdownStudents.count
    }

    private var scopeTitle: String {
        switch selectedGroupFilter {
        case .all:
            return "Overall"
        case .ungrouped:
            return "Ungrouped"
        case .group(let id):
            return groups.first(where: { $0.id == id })?.name ?? (selectedGroup?.name ?? "Group")
        }
    }

    private var scopeSubtitle: String {
        let count = eligibleStudentCount
        switch selectedGroupFilter {
        case .all:
            return "\(count) student\(count == 1 ? "" : "s")"
        case .ungrouped:
            return "\(count) student\(count == 1 ? "" : "s")"
        case .group:
            return "\(count) student\(count == 1 ? "" : "s")"
        }
    }

    private var scopeIconSystemName: String {
        switch selectedGroupFilter {
        case .all:
            return "chart.bar.fill"
        case .ungrouped:
            return "tray.fill"
        case .group:
            return "folder.fill"
        }
    }

    private var scopeOverallProgress: Int {
        switch selectedGroupFilter {
        case .all:
            return ProgressCalculator.cohortOverall(students: students, allObjectives: allObjectives)
        case .ungrouped:
            return ProgressCalculator.cohortOverall(students: ungroupedStudents, allObjectives: allObjectives)
        case .group(let id):
            if let group = groups.first(where: { $0.id == id }) {
                return ProgressCalculator.groupOverall(group: group, students: students, allObjectives: allObjectives)
            }
            if let group = selectedGroup {
                return ProgressCalculator.groupOverall(group: group, students: students, allObjectives: allObjectives)
            }
            return 0
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                unifiedOverviewContainer

                studentBoardSection

                if let student = selectedStudent, eligibleStudentCount > 0 {
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

                    if eligibleStudentCount == 0 {
                        ContentUnavailableView(
                            "No Students in Scope",
                            systemImage: "person.3",
                            description: Text(emptyScopeDescription)
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    } else {
                        ContentUnavailableView(
                            "No Student Selected",
                            systemImage: "person.crop.circle.badge.questionmark",
                            description: Text("Select a student from the board to view progress details.")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                }
            }
            .padding(20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showingAddSheet) {
            AddStudentSheet { name, group, session, domain, customProperties in
                addStudent(named: name, group: group, session: session, domain: domain, customProperties: customProperties)
            }
        }
        .sheet(item: $editingCategoryTarget) { target in
            EditCategoryTitleSheet(
                code: target.code,
                fallbackTitle: target.fallbackTitle
            )
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
                if let studentPendingDelete {
                    deleteStudent(studentPendingDelete)
                }
                studentPendingDelete = nil
            }

            Button("Cancel", role: .cancel) {
                studentPendingDelete = nil
            }
        } message: {
            if let studentPendingDelete {
                Text("Delete \(studentPendingDelete.name)? This action cannot be undone.")
            }
        }
    }

    private var unifiedOverviewContainer: some View {
        VStack(alignment: .leading, spacing: 14) {
            overviewHeaderRow

            if eligibleStudentCount == 0 {
                Divider()
                    .opacity(0.22)

                ContentUnavailableView(
                    emptyScopeTitle,
                    systemImage: "person.3",
                    description: Text(emptyScopeDescription)
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            } else {
                Divider()
                    .opacity(0.22)

                overviewBreakdownSection
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

    private var overviewHeaderRow: some View {
        HStack(spacing: 16) {
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

                Image(systemName: scopeIconSystemName)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(.accentColor)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(scopeTitle)
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text(scopeSubtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                overviewFilterMenu
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("Overall Progress")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    Text("\(scopeOverallProgress)%")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(.accentColor)

                    CircularProgressView(progress: Double(scopeOverallProgress) / 100.0)
                        .frame(width: 50, height: 50)
                }
            }
        }
    }

    private var overviewBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("A–E Summary")
                    .font(.headline)

                Spacer()

                Text(scopeTitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 10) {
                ForEach(rootCategories) { category in
                    overviewCategoryRow(category)
                }
            }
        }
    }

    private func overviewCategoryRow(_ category: LearningObjective) -> some View {
        let avg = ProgressCalculator.cohortObjectiveAverage(
            objectiveCode: category.code,
            students: breakdownStudents,
            allObjectives: allObjectives
        )

        return HStack(spacing: 12) {
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

            VStack(alignment: .leading, spacing: 2) {
                Text(categoryDisplayTitle(for: category))
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .contextMenu {
                        Button("Edit Title...") {
                            editingCategoryTarget = CategoryEditTarget(code: category.code, fallbackTitle: category.title)
                        }
                    }

                Text("Average for \(category.code)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if isSwitchingScope {
                Text("Select a student to see their progress")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            } else {
                HStack(spacing: 10) {
                    Text("\(avg)%")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)

                    CircularProgressView(progress: Double(avg) / 100.0)
                        .frame(width: 28, height: 28)
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private var emptyScopeTitle: String {
        switch selectedGroupFilter {
        case .all:
            return "No Students Yet"
        case .ungrouped:
            return "No Students in Ungrouped"
        case .group:
            return "No Students in Group"
        }
    }

    private var emptyScopeDescription: String {
        switch selectedGroupFilter {
        case .all:
            return "Add a student to see overall progress."
        case .ungrouped:
            return "No students in this scope. Add a student or move students to Ungrouped."
        case .group:
            return "No students in this scope. Add a student or move students into this group."
        }
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

    private var studentBoardSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("Student Board")
                    .font(.headline)

                Spacer()

                studentBoardFilterMenu
                    .buttonStyle(.bordered)
            }

            if filteredStudents.isEmpty {
                ContentUnavailableView(
                    "No Students in Filter",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text("Change the filter to see students.")
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
                            .frame(width: 240)
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

    private var studentBoardFilterMenu: some View {
        filterMenuView(style: .standard)
            .help("Filter student cards by group (also sets the scope shown in header and A–E breakdown)")
    }

    private var overviewFilterMenu: some View {
        filterMenuView(style: .compact)
            .help("Change the scope shown in the overview container")
    }

    private func filterMenuView(style: FilterMenuStyle) -> some View {
        Menu {
            Button("Overall") {
                beginScopeSwitch(to: .all, group: nil)
            }

            Divider()

            if groups.isEmpty == false {
                ForEach(groups) { group in
                    Button(group.name) {
                        beginScopeSwitch(to: .group(group.id), group: group)
                    }
                }
                Divider()
            }

            Button("Ungrouped") {
                beginScopeSwitch(to: .ungrouped, group: nil)
            }
        } label: {
            HStack(spacing: style == .compact ? 6 : 8) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .foregroundColor(.secondary)

                Text(style == .compact ? "Scope:" : "Filter:")
                    .font(style == .compact ? .caption2 : .caption)
                    .foregroundColor(.secondary)

                Text(selectedGroupFilter.title(groups: groups))
                    .font(style == .compact ? .caption2 : .caption)
                    .fontWeight(.semibold)

                Image(systemName: "chevron.down")
                    .font(style == .compact ? .caption2 : .caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, style == .compact ? 8 : 10)
            .padding(.vertical, style == .compact ? 4 : 6)
            .background(
                RoundedRectangle(cornerRadius: style == .compact ? 8 : 10)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: style == .compact ? 8 : 10)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
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

    private func beginScopeSwitch(to newFilter: GroupFilter, group: CohortGroup?) {
        isSwitchingScope = true

        withAnimation(.easeInOut(duration: 0.15)) {
            selectedGroupFilter = newFilter
            selectedGroup = group
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            reconcileSelectedStudentForCurrentScope()
            isSwitchingScope = false
        }
    }

    private func reconcileSelectedStudentForCurrentScope() {
        let scopeStudents = filteredStudents

        guard scopeStudents.isEmpty == false else {
            selectedStudent = nil
            return
        }

        if let selectedStudent, scopeStudents.contains(where: { $0.id == selectedStudent.id }) {
            return
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            selectedStudent = scopeStudents.first
        }
    }

    private func addStudent(named name: String, group: CohortGroup?, session: Session, domain: Domain?, customProperties: [CustomPropertyRow]) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }

        let newStudent = Student(name: trimmed, group: group, session: session, domain: domain)
        modelContext.insert(newStudent)

        // Add custom properties
        for (index, row) in customProperties.enumerated() {
            let property = StudentCustomProperty(
                key: row.key.trimmingCharacters(in: .whitespacesAndNewlines),
                value: row.value.trimmingCharacters(in: .whitespacesAndNewlines),
                sortOrder: index
            )
            property.student = newStudent
            modelContext.insert(property)
            newStudent.customProperties.append(property)
        }

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
                    selectedStudent = filteredStudents.first
                }
            }
        } catch {
            print("Failed to delete student: \(error)")
        }
    }

    private func move(student: Student, to group: CohortGroup?) {
        student.group = group
        saveContext()

        if filteredStudents.contains(where: { $0.id == student.id }) == false, selectedStudent?.id == student.id {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedStudent = filteredStudents.first
            }
        }
    }

    private func saveContext() {
        do {
            try modelContext.save()
        } catch {
            print("Failed to save context: \(error)")
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

    private enum GroupFilter: Hashable {
        case all
        case ungrouped
        case group(UUID)

        func title(groups: [CohortGroup]) -> String {
            switch self {
            case .all:
                return "Overall"
            case .ungrouped:
                return "Ungrouped"
            case .group(let id):
                return groups.first(where: { $0.id == id })?.name ?? "Group"
            }
        }
    }

    private func categoryDisplayTitle(for objective: LearningObjective) -> String {
        if let label = categoryLabels.first(where: { $0.key == objective.code }) {
            return label.title
        }
        return objective.title
    }

    private struct CategoryEditTarget: Identifiable {
        let id: String
        let code: String
        let fallbackTitle: String

        init(code: String, fallbackTitle: String) {
            self.id = code
            self.code = code
            self.fallbackTitle = fallbackTitle
        }
    }

    private enum FilterMenuStyle {
        case standard
        case compact
    }
}
