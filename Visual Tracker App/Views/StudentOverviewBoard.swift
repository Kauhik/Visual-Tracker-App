import SwiftUI

struct StudentOverviewBoard: View {
    @EnvironmentObject private var store: CloudKitStore
    @EnvironmentObject private var activityCenter: ActivityCenter
    @Environment(ZoomManager.self) private var zoomManager
    @Binding var selectedStudentId: UUID?

    @State private var showingManageStudents: Bool = false
    @State private var studentToEdit: Student?
    @State private var showingManageGroups: Bool = false
    @State private var showingManageDomains: Bool = false
    @State private var showingManageSuccessCriteria: Bool = false
    @State private var showingManageMilestones: Bool = false
    @State private var showingManageSheets: Bool = false
    @State private var studentPendingDelete: Student?
    @State private var searchText: String = ""
    @State private var debouncedSearchText: String = ""
    @State private var searchDebounceTask: Task<Void, Never>?

    @State private var editingStudentId: UUID?
    @State private var editingStudentName: String = ""

    @FocusState private var renameFocusedStudentId: UUID?

    @State private var showingRenameError: Bool = false
    @State private var renameErrorMessage: String = ""

    private var students: [Student] { store.students }
    private var categoryLabels: [CategoryLabel] { store.categoryLabels }

    private var rootCategories: [LearningObjective] {
        store.rootCategoryObjectives()
    }

    private var cohortOverall: Int {
        store.cohortOverallProgress(students: students)
    }

    private var trimmedSearchText: String {
        debouncedSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredStudents: [Student] {
        let query = trimmedSearchText.lowercased()
        guard query.isEmpty == false else { return students }

        return students.filter { student in
            let nameMatches = student.name.lowercased().contains(query)
            let studentGroups = store.groups(for: student)
            let groupMatches = studentGroups.contains { $0.name.lowercased().contains(query) }
            let ungroupedMatches = query.contains("ungrouped") && store.isUngrouped(student: student)
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
                .padding(.horizontal, zoomManager.scaled(12))
                .padding(.top, zoomManager.scaled(12))
                .padding(.bottom, zoomManager.scaled(8))

            sidebarSearchBar
                .padding(.horizontal, zoomManager.scaled(12))
                .padding(.bottom, zoomManager.scaled(6))

            List(selection: $selectedStudentId) {
                Section {
                    cohortOverviewRow
                        .selectionDisabled(true)

                    ForEach(rootCategories) { category in
                        cohortCategoryRow(category)
                            .selectionDisabled(true)
                    }

                    ManageSidebarRow(
                        title: "Manage Groups",
                        systemImage: "folder.badge.gearshape",
                        onOpen: { showingManageGroups = true }
                    )

                    ManageSidebarRow(
                        title: "Manage Expertise Check",
                        systemImage: "graduationcap",
                        onOpen: { showingManageDomains = true }
                    )

                    ManageSidebarRow(
                        title: "Manage Success Criteria",
                        systemImage: "list.bullet.rectangle",
                        onOpen: { showingManageSuccessCriteria = true }
                    )

                    ManageSidebarRow(
                        title: "Manage Milestones",
                        systemImage: "list.number",
                        onOpen: { showingManageMilestones = true }
                    )
                } header: {
                    Text("Cohort Overview")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section {
                    ForEach(filteredStudents, id: \.id) { student in
                        studentRow(student)
                            .tag(student.id)
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
            ManageStudentsSheet { name, groups, session, domain, customProperties in
                addStudent(
                    named: name,
                    groups: groups,
                    session: session,
                    domain: domain,
                    customProperties: customProperties
                )
            }
        }
        .sheet(item: $studentToEdit) { student in
            AddStudentSheet(studentToEdit: student) { name, groups, session, domain, customProperties in
                saveEditedStudent(
                    student,
                    name: name,
                    groups: groups,
                    session: session,
                    domain: domain,
                    customProperties: customProperties
                )
            }
        }
        .sheet(isPresented: $showingManageGroups) {
            ManageGroupsSheet()
        }
        .sheet(isPresented: $showingManageDomains) {
            ManageDomainsSheet()
        }
        .sheet(isPresented: $showingManageSuccessCriteria) {
            ManageSuccessCriteriaSheet()
        }
        .sheet(isPresented: $showingManageMilestones) {
            ManageMilestonesSheet()
        }
        .sheet(isPresented: $showingManageSheets) {
            ManageSheetsSheet()
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
        HStack(spacing: zoomManager.scaled(12)) {
            VStack(alignment: .leading, spacing: zoomManager.scaled(2)) {
                Text("Students")
                    .font(.title2)
                    .fontWeight(.bold)

                Text(students.isEmpty ? "No students yet" : "\(students.count) student\(students.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let activeSheet = store.activeSheet {
                    Text("Sheet: \(activeSheet.name)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Button {
                showingManageSheets = true
            } label: {
                Label("Manage Sheets", systemImage: "square.stack.3d.up")
            }
            .buttonStyle(.bordered)

            Button {
                showingManageStudents = true
            } label: {
                Label("Manage Students", systemImage: "person.2.badge.gearshape")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var sidebarSearchBar: some View {
        HStack(spacing: zoomManager.scaled(8)) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField("Search students or groups", text: $searchText)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, zoomManager.scaled(8))
        .padding(.vertical, zoomManager.scaled(6))
        .background(
            RoundedRectangle(cornerRadius: zoomManager.scaled(8))
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: zoomManager.scaled(8))
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .controlSize(.small)
    }

    private func studentRow(_ student: Student) -> some View {
        let isEditing = editingStudentId == student.id
        let studentGroupSummary = groupSummary(for: student)

        return HStack(spacing: zoomManager.scaled(10)) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                .frame(width: zoomManager.scaled(28), height: zoomManager.scaled(28))

            Text(student.name.prefix(1).uppercased())
                .font(zoomManager.scaledFont(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }

        VStack(alignment: .leading, spacing: zoomManager.scaled(2)) {
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
                        .truncationMode(.tail)
                        .help(student.name)
                }

                HStack(spacing: zoomManager.scaled(4)) {
                    Text(studentGroupSummary)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(studentGroupSummary)

                    Text("•")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.6))

                    Text(student.domain?.name ?? "No Expertise Check")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(student.domain?.name ?? "No Expertise Check")
                }
            }
            .layoutPriority(1)

            Spacer()
        }
        .padding(.vertical, zoomManager.scaled(6))
        .contentShape(Rectangle())
        .onTapGesture {
            if isEditing == false {
                selectedStudentId = student.id
            }
        }
    }

    private var cohortOverviewRow: some View {
        Button {
            selectedStudentId = nil
        } label: {
            HStack(spacing: zoomManager.scaled(12)) {
                VStack(alignment: .leading, spacing: zoomManager.scaled(4)) {
                    Text("Overall")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("\(cohortOverall)%")
                        .font(zoomManager.scaledFont(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.accentColor)
                }

                Spacer()

                CircularProgressView(progress: Double(cohortOverall) / 100.0)
                    .frame(width: zoomManager.scaled(34), height: zoomManager.scaled(34))
            }
            .padding(.vertical, zoomManager.scaled(10))
            .padding(.horizontal, zoomManager.scaled(10))
            .background(
                RoundedRectangle(cornerRadius: zoomManager.scaled(12))
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: zoomManager.scaled(12))
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help("Show cohort overview")
        .listRowInsets(
            EdgeInsets(
                top: zoomManager.scaled(8),
                leading: zoomManager.scaled(10),
                bottom: zoomManager.scaled(6),
                trailing: zoomManager.scaled(10)
            )
        )
    }

    private func cohortCategoryRow(_ category: LearningObjective) -> some View {
        let value = store.cohortObjectiveAverage(objective: category, students: students)

        return HStack(spacing: zoomManager.scaled(10)) {
            SuccessCriteriaBadge(
                code: category.code,
                font: zoomManager.scaledFont(size: 14, weight: .bold, design: .rounded),
                horizontalPadding: zoomManager.scaled(8),
                verticalPadding: zoomManager.scaled(4),
                cornerRadius: zoomManager.scaled(8),
                minWidth: zoomManager.scaled(22)
            )

            Text(categoryDisplayTitle(for: category))
                .font(.callout)
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(categoryDisplayTitle(for: category))
                .layoutPriority(1)
                .contextMenu {
                    Button("Manage Success Criteria…") {
                        showingManageSuccessCriteria = true
                    }

                    Button("Manage Milestones…") {
                        showingManageMilestones = true
                    }
                }

            Spacer()

            Text("\(value)%")
                .font(zoomManager.scaledFont(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(minWidth: zoomManager.scaled(32), alignment: .trailing)
        }
        .padding(.vertical, zoomManager.scaled(8))
        .padding(.horizontal, zoomManager.scaled(10))
        .background(
            RoundedRectangle(cornerRadius: zoomManager.scaled(12))
                .fill(SuccessCriteriaStyle.subtleFill(for: category.code))
        )
        .listRowInsets(
            EdgeInsets(
                top: zoomManager.scaled(4),
                leading: zoomManager.scaled(10),
                bottom: zoomManager.scaled(4),
                trailing: zoomManager.scaled(10)
            )
        )
    }

    private func addStudent(
        named name: String,
        groups: [CohortGroup],
        session: Session,
        domain: Domain?,
        customProperties: [CustomPropertyRow]
    ) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        Task {
            if let newStudent = await store.addStudent(
                name: trimmed,
                groups: groups,
                session: session,
                domain: domain,
                customProperties: customProperties
            ) {
                selectedStudentId = newStudent.id
            }
        }
    }

    private func beginEdit(_ student: Student) {
        Task {
            await activityCenter.run(message: "Loading student details…", tag: .detail) {
                await store.loadCustomPropertiesIfNeeded(for: student)
            }
            studentToEdit = student
        }
    }

    private func saveEditedStudent(
        _ student: Student,
        name: String,
        groups: [CohortGroup],
        session: Session,
        domain: Domain?,
        customProperties: [CustomPropertyRow]
    ) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        Task {
            await store.updateStudent(
                student,
                name: trimmed,
                groups: groups,
                session: session,
                domain: domain,
                customProperties: customProperties
            )
            studentToEdit = nil
        }
    }

    private func deleteStudent(_ student: Student) {
        if selectedStudentId == student.id {
            selectedStudentId = nil
        }
        Task {
            await store.deleteStudent(student)
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
        let canonical = objective.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if canonical.isEmpty, let label = categoryLabels.first(where: { $0.key == objective.code }) {
            return label.title
        }
        return canonical.isEmpty ? objective.code : objective.title
    }

    private func groupSummary(for student: Student) -> String {
        let studentGroups = store.groups(for: student)
        if studentGroups.isEmpty {
            return "Ungrouped"
        }
        if studentGroups.count == 1 {
            return studentGroups[0].name
        }
        return "\(studentGroups[0].name) +\(studentGroups.count - 1)"
    }

}

private struct ManageSidebarRow: View {
    @Environment(ZoomManager.self) private var zoomManager
    @State private var isHovering: Bool = false

    let title: String
    let systemImage: String
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: zoomManager.scaled(10)) {
                Image(systemName: systemImage)
                Text(title)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .foregroundColor(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, zoomManager.scaled(6))
            .padding(.horizontal, zoomManager.scaled(8))
            .background(
                RoundedRectangle(cornerRadius: zoomManager.scaled(8))
                    .fill(isHovering ? Color.primary.opacity(0.08) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
        .contextMenu {
            Button("Open \(title)") {
                onOpen()
            }
        }
    }
}
