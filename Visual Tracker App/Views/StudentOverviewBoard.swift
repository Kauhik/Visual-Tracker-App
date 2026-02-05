import SwiftUI

struct StudentOverviewBoard: View {
    @EnvironmentObject private var store: CloudKitStore

    @Binding var selectedStudent: Student?

    @State private var showingManageStudents: Bool = false
    @State private var studentToEdit: Student?
    @State private var showingManageGroups: Bool = false
    @State private var showingManageDomains: Bool = false
    @State private var studentPendingDelete: Student?
    @State private var searchText: String = ""
    @State private var debouncedSearchText: String = ""
    @State private var searchDebounceTask: Task<Void, Never>?

    @State private var editingStudentId: UUID?
    @State private var editingStudentName: String = ""

    @FocusState private var renameFocusedStudentId: UUID?

    @State private var showingRenameError: Bool = false
    @State private var renameErrorMessage: String = ""

    @State private var editingCategoryTarget: CategoryEditTarget?

    private var students: [Student] { store.students }
    private var allObjectives: [LearningObjective] { store.learningObjectives }
    private var categoryLabels: [CategoryLabel] { store.categoryLabels }

    private var rootCategories: [LearningObjective] {
        allObjectives
            .filter { $0.parentCode == nil }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private var cohortOverall: Int {
        ProgressCalculator.cohortOverall(students: students, allObjectives: allObjectives)
    }

    private var trimmedSearchText: String {
        debouncedSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredStudents: [Student] {
        let query = trimmedSearchText.lowercased()
        guard query.isEmpty == false else { return students }

        return students.filter { student in
            let nameMatches = student.name.lowercased().contains(query)
            let groupName = student.group?.name.lowercased() ?? ""
            let groupMatches = groupName.contains(query)
            let ungroupedMatches = query.contains("ungrouped") && student.group == nil
            let sessionMatches = student.session.rawValue.lowercased().contains(query)
            let domainName = student.domain?.name.lowercased() ?? ""
            let domainMatches = domainName.contains(query)
            let noDomainMatches = (query.contains("no domain") || query.contains("nodomain")) && student.domain == nil

            return nameMatches || groupMatches || ungroupedMatches || sessionMatches || domainMatches || noDomainMatches
        }
    }

    private var studentsHeaderText: String {
        if trimmedSearchText.isEmpty {
            return "Students"
        }

        return "Students (\(filteredStudents.count))"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)

            sidebarSearchBar
                .padding(.horizontal, 12)
                .padding(.bottom, 6)

            List(selection: $selectedStudent) {
                Section {
                    cohortOverviewRow
                        .selectionDisabled(true)

                    ForEach(rootCategories) { category in
                        cohortCategoryRow(category)
                            .selectionDisabled(true)
                    }

                    Button {
                        showingManageGroups = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "folder.badge.gearshape")
                            Text("Manage Groups")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .foregroundColor(.primary)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)

                    Button {
                        showingManageDomains = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "tag")
                            Text("Manage Domains")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .foregroundColor(.primary)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text("Cohort Overview")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section {
                    ForEach(filteredStudents, id: \.id) { student in
                        studentRow(student)
                            .tag(student as Student?)
                            .contextMenu {
                                Button("Edit Student…") {
                                    beginEdit(student)
                                }

                                Button("Rename") {
                                    beginRename(student)
                                }

                                Divider()

                                Button("Delete Student", role: .destructive) {
                                    studentPendingDelete = student
                                }
                            }
                    }
                } header: {
                    Text(studentsHeaderText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .listStyle(.sidebar)
        }
        .sheet(isPresented: $showingManageStudents) {
            ManageStudentsSheet { name, group, session, domain, customProperties in
                addStudent(named: name, group: group, session: session, domain: domain, customProperties: customProperties)
            }
        }
        .sheet(item: $studentToEdit) { student in
            AddStudentSheet(studentToEdit: student) { name, group, session, domain, customProperties in
                saveEditedStudent(student, name: name, group: group, session: session, domain: domain, customProperties: customProperties)
            }
        }
        .sheet(isPresented: $showingManageGroups) {
            ManageGroupsSheet()
        }
        .sheet(isPresented: $showingManageDomains) {
            ManageDomainsSheet()
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
        .alert("Rename Failed", isPresented: $showingRenameError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(renameErrorMessage)
        }
        .onAppear {
            if selectedStudent == nil {
                selectedStudent = students.first
            }
            if debouncedSearchText != searchText {
                debouncedSearchText = searchText
            }
        }
        .onChange(of: searchText) { _, newValue in
            searchDebounceTask?.cancel()
            searchDebounceTask = Task {
                try? await Task.sleep(nanoseconds: 250_000_000)
                if Task.isCancelled { return }
                await MainActor.run {
                    debouncedSearchText = newValue
                }
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
                showingManageStudents = true
            } label: {
                Label("Manage Students", systemImage: "person.2.badge.gearshape")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var sidebarSearchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField("Search students or groups", text: $searchText)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .controlSize(.small)
    }

    private func studentRow(_ student: Student) -> some View {
        let isEditing = editingStudentId == student.id

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

            VStack(alignment: .leading, spacing: 2) {
                if isEditing {
                    TextField("", text: $editingStudentName)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .focused($renameFocusedStudentId, equals: student.id)
                        .onSubmit {
                            commitRename(for: student)
                        }
                        .onChange(of: renameFocusedStudentId) { _, newValue in
                            if editingStudentId == student.id, newValue != student.id {
                                commitRename(for: student)
                            }
                        }
                        .onExitCommand {
                            cancelRename()
                        }
                        .onAppear {
                            if editingStudentName.isEmpty {
                                editingStudentName = student.name
                            }
                            DispatchQueue.main.async {
                                renameFocusedStudentId = student.id
                            }
                        }
                } else {
                    Text(student.name)
                        .font(.body)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }

                HStack(spacing: 4) {
                    Text(student.group?.name ?? "Ungrouped")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    Text("•")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.6))

                    Text(student.domain?.name ?? "No Domain")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
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

            Text(categoryDisplayTitle(for: category))
                .font(.caption)
                .foregroundColor(.primary)
                .lineLimit(1)
                .contextMenu {
                    Button("Edit Title...") {
                        editingCategoryTarget = CategoryEditTarget(code: category.code, fallbackTitle: category.title)
                    }
                }

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

    private func addStudent(named name: String, group: CohortGroup?, session: Session, domain: Domain?, customProperties: [CustomPropertyRow]) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        Task {
            if let newStudent = await store.addStudent(
                name: trimmed,
                group: group,
                session: session,
                domain: domain,
                customProperties: customProperties
            ) {
                selectedStudent = newStudent
            }
        }
    }

    private func beginEdit(_ student: Student) {
        Task {
            await store.loadCustomPropertiesIfNeeded(for: student)
            studentToEdit = student
        }
    }

    private func saveEditedStudent(_ student: Student, name: String, group: CohortGroup?, session: Session, domain: Domain?, customProperties: [CustomPropertyRow]) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        Task {
            await store.updateStudent(
                student,
                name: trimmed,
                group: group,
                session: session,
                domain: domain,
                customProperties: customProperties
            )
            studentToEdit = nil
        }
    }

    private func deleteStudent(_ student: Student) {
        if selectedStudent?.id == student.id {
            selectedStudent = nil
        }
        Task {
            await store.deleteStudent(student)
            if selectedStudent == nil {
                selectedStudent = students.first
            }
        }
    }

    private func beginRename(_ student: Student) {
        editingStudentId = student.id
        editingStudentName = student.name
        renameFocusedStudentId = student.id
    }

    private func cancelRename() {
        editingStudentId = nil
        editingStudentName = ""
        renameFocusedStudentId = nil
    }

    private func commitRename(for student: Student) {
        guard editingStudentId == student.id else { return }

        let trimmed = editingStudentName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.isEmpty == false else {
            renameErrorMessage = "Name cannot be empty."
            showingRenameError = true
            DispatchQueue.main.async {
                renameFocusedStudentId = student.id
            }
            return
        }

        if trimmed == student.name {
            cancelRename()
            return
        }

        Task {
            await store.renameStudent(student, newName: trimmed)
            cancelRename()
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
