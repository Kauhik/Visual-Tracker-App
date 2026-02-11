import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct StudentDetailView: View {
    @Binding var selectedStudent: Student?
    @Binding var selectedGroup: CohortGroup?

    @EnvironmentObject private var store: CloudKitStore
    @EnvironmentObject private var activityCenter: ActivityCenter
    @Environment(ZoomManager.self) private var zoomManager

    @State private var showingAddSheet: Bool = false
    @State private var studentPendingDelete: Student?

    @State private var editingCategoryTarget: CategoryEditTarget?
    @State private var isExportingData: Bool = false
    @State private var showingExportSuccess: Bool = false
    @State private var showingExportError: Bool = false
    @State private var exportSuccessMessage: String = ""
    @State private var exportErrorMessage: String = ""

    private var students: [Student] { store.students }
    private var allObjectives: [LearningObjective] { store.learningObjectives }
    private var groups: [CohortGroup] { store.groups }
    private var domains: [Domain] { store.domains }
    private var categoryLabels: [CategoryLabel] { store.categoryLabels }

    private var displayMode: DisplayMode {
        if let selectedStudent {
            return .student(selectedStudent)
        }
        return .overview
    }

    private var selectedScope: StudentFilterScope {
        store.selectedScope
    }

    private var rootCategories: [LearningObjective] {
        store.rootCategoryObjectives()
    }

    private var ungroupedStudents: [Student] {
        students.filter { store.isUngrouped(student: $0) }
    }

    private var noDomainStudents: [Student] {
        students.filter { $0.domain == nil }
    }

    private var isStudentDetailMode: Bool {
        if case .student = displayMode {
            return true
        }
        return false
    }

    private var filteredStudents: [Student] {
        switch selectedScope {
        case .overall:
            return students
        case .ungrouped:
            return ungroupedStudents
        case .group(let id):
            return students.filter { student in
                store.groups(for: student).contains { $0.id == id }
            }
        case .domain(let id):
            return students.filter { $0.domain?.id == id }
        case .noDomain:
            return noDomainStudents
        }
    }

    private var boardStudents: [Student] {
        filteredStudents
    }

    private var breakdownStudents: [Student] {
        switch displayMode {
        case .student(let student):
            return [student]
        case .overview:
            return filteredStudents
        }
    }

    private var eligibleStudentCount: Int {
        breakdownStudents.count
    }

    private var scopeTitle: String {
        switch selectedScope {
        case .overall:
            return "Overall"
        case .ungrouped:
            return "Ungrouped"
        case .group(let id):
            return groups.first(where: { $0.id == id })?.name ?? (selectedGroup?.name ?? "Group")
        case .domain(let id):
            return domains.first(where: { $0.id == id })?.name ?? "Expertise Check"
        case .noDomain:
            return "No Expertise Check"
        }
    }

    private var scopeSubtitle: String {
        let count = eligibleStudentCount
        switch selectedScope {
        case .overall, .ungrouped, .group, .domain, .noDomain:
            return "\(count) student\(count == 1 ? "" : "s")"
        }
    }

    private var scopeIconSystemName: String {
        switch selectedScope {
        case .overall:
            return "person.3"
        case .ungrouped:
            return "person.2.slash"
        case .group:
            return "person.2"
        case .domain(let id):
            return iconForExpertiseCheck(named: domains.first(where: { $0.id == id })?.name)
        case .noDomain:
            return "graduationcap.slash"
        }
    }

    private var scopeOverallProgress: Int {
        switch selectedScope {
        case .overall:
            return store.cohortOverallProgress(students: students)
        case .ungrouped:
            return store.cohortOverallProgress(students: ungroupedStudents)
        case .group(let id):
            if let group = groups.first(where: { $0.id == id }) {
                return store.groupOverallProgress(group: group, students: students)
            }
            if let group = selectedGroup {
                return store.groupOverallProgress(group: group, students: students)
            }
            return store.cohortOverallProgress(students: filteredStudents)
        case .domain, .noDomain:
            return store.cohortOverallProgress(students: filteredStudents)
        }
    }

    private var headerTitle: String {
        switch displayMode {
        case .student(let student):
            return student.name
        case .overview:
            return scopeTitle
        }
    }

    private var headerSubtitle: String {
        switch displayMode {
        case .student(let student):
            return studentMetadata(for: student)
        case .overview:
            return scopeSubtitle
        }
    }

    private var headerOverallProgress: Int {
        switch displayMode {
        case .student(let student):
            return store.studentOverallProgress(student: student)
        case .overview:
            return scopeOverallProgress
        }
    }

    private var summaryContextTitle: String {
        switch displayMode {
        case .student(let student):
            return student.name
        case .overview:
            return scopeTitle
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: zoomManager.scaled(18)) {
                if activityCenter.isVisible && activityCenter.tag == .detail {
                    HStack(spacing: zoomManager.scaled(8)) {
                        ProgressView()
                            .controlSize(.small)

                        Text(activityCenter.message ?? "Loading…")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, zoomManager.scaled(4))
                }

                unifiedOverviewContainer

                studentBoardSection

                if let student = selectedStudent, eligibleStudentCount > 0 {
                    legendView
                        .padding(.top, zoomManager.scaled(2))

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
                        .padding(.vertical, zoomManager.scaled(12))
                    } else {
                        ContentUnavailableView(
                            "No Student Selected",
                            systemImage: "person.crop.circle.badge.questionmark",
                            description: Text("Select a student from the board to view progress details.")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, zoomManager.scaled(12))
                    }
                }
            }
            .padding(zoomManager.scaled(20))
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showingAddSheet) {
            AddStudentSheet { name, selectedGroups, session, domain, customProperties in
                addStudent(
                    named: name,
                    groups: selectedGroups,
                    session: session,
                    domain: domain,
                    customProperties: customProperties
                )
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
        .alert("Export Complete", isPresented: $showingExportSuccess) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(exportSuccessMessage)
        }
        .alert("Export Failed", isPresented: $showingExportError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(exportErrorMessage)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                toolbarFilterMenu
                hardRefreshToolbarButton
                exportToolbarButton
                resetToolbarButton
            }
        }
        .task(id: selectedStudent?.id) {
            if let selectedStudent {
                await activityCenter.run(message: "Loading student details…", tag: .detail) {
                    await store.loadProgressIfNeeded(for: selectedStudent)
                    await store.loadCustomPropertiesIfNeeded(for: selectedStudent)
                }
            }
        }
    }

    private var unifiedOverviewContainer: some View {
        VStack(alignment: .leading, spacing: zoomManager.scaled(14)) {
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
                .padding(.vertical, zoomManager.scaled(6))
            } else {
                Divider()
                    .opacity(0.22)

                overviewBreakdownSection
            }
        }
        .padding(zoomManager.scaled(20))
        .background(
            RoundedRectangle(cornerRadius: zoomManager.scaled(16))
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.12), radius: zoomManager.scaled(6), x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: zoomManager.scaled(16))
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private var overviewHeaderRow: some View {
        HStack(spacing: zoomManager.scaled(16)) {
            if let selectedStudent {
                studentAvatar(for: selectedStudent)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: zoomManager.scaled(14))
                        .fill(
                            LinearGradient(
                                colors: [.blue.opacity(0.18), .purple.opacity(0.18)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: zoomManager.scaled(64), height: zoomManager.scaled(64))

                    Image(systemName: scopeIconSystemName)
                        .font(zoomManager.scaledFont(size: 26, weight: .semibold))
                        .foregroundColor(.accentColor)
                }
            }

            VStack(alignment: .leading, spacing: zoomManager.scaled(8)) {
                Text(headerTitle)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(headerTitle)

                Text(headerSubtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(headerSubtitle)
            }
            .layoutPriority(1)

            Spacer()

            VStack(alignment: .trailing, spacing: zoomManager.scaled(4)) {
                Text("Overall Progress")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: zoomManager.scaled(8)) {
                    Text("\(headerOverallProgress)%")
                        .font(zoomManager.scaledFont(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(.accentColor)

                    CircularProgressView(progress: Double(headerOverallProgress) / 100.0)
                        .frame(width: zoomManager.scaled(50), height: zoomManager.scaled(50))
                }
            }
        }
    }

    private var overviewBreakdownSection: some View {
        VStack(alignment: .leading, spacing: zoomManager.scaled(12)) {
            HStack {
                Text("Summary")
                    .font(.headline)

                Spacer()

                Text(summaryContextTitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(summaryContextTitle)
                    .layoutPriority(1)
            }

            VStack(spacing: zoomManager.scaled(10)) {
                ForEach(rootCategories) { category in
                    overviewCategoryRow(category)
                }
            }
        }
    }

    private func overviewCategoryRow(_ category: LearningObjective) -> some View {
        let value: Int

        switch displayMode {
        case .student(let student):
            value = store.objectivePercentage(student: student, objective: category)
        case .overview:
            value = store.cohortObjectiveAverage(objective: category, students: breakdownStudents)
        }

        return HStack(spacing: zoomManager.scaled(12)) {
            SuccessCriteriaBadge(
                code: category.code,
                font: zoomManager.scaledFont(size: 15, weight: .bold, design: .rounded),
                horizontalPadding: zoomManager.scaled(8),
                verticalPadding: zoomManager.scaled(4),
                cornerRadius: zoomManager.scaled(8),
                minWidth: zoomManager.scaled(24)
            )

            VStack(alignment: .leading, spacing: zoomManager.scaled(2)) {
                Text(categoryDisplayTitle(for: category))
                    .font(.callout)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(categoryDisplayTitle(for: category))
                    .layoutPriority(1)
            }

            Spacer()

            HStack(spacing: zoomManager.scaled(10)) {
                Text("\(value)%")
                    .font(zoomManager.scaledFont(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(minWidth: zoomManager.scaled(32), alignment: .trailing)

                CircularProgressView(progress: Double(value) / 100.0)
                    .frame(width: zoomManager.scaled(28), height: zoomManager.scaled(28))
            }
        }
        .padding(.vertical, zoomManager.scaled(10))
        .padding(.horizontal, zoomManager.scaled(12))
        .background(
            RoundedRectangle(cornerRadius: zoomManager.scaled(12))
                .fill(SuccessCriteriaStyle.subtleFill(for: category.code))
        )
        .overlay(
            RoundedRectangle(cornerRadius: zoomManager.scaled(12))
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .contextMenu {
            Button("Edit Title...") {
                editingCategoryTarget = CategoryEditTarget(code: category.code, fallbackTitle: category.title)
            }
        }
    }

    private var emptyScopeTitle: String {
        switch selectedScope {
        case .overall:
            return "No Students Yet"
        case .ungrouped:
            return "No Students in Ungrouped"
        case .group:
            return "No Students in Group"
        case .domain:
            return "No Students in Expertise Check"
        case .noDomain:
            return "No Students with No Expertise Check"
        }
    }

    private var emptyScopeDescription: String {
        switch selectedScope {
        case .overall:
            return "Add a student to see overall progress."
        case .ungrouped:
            return "No students in this scope. Add a student or move students to Ungrouped."
        case .group:
            return "No students in this scope. Add a student or move students into this group."
        case .domain:
            return "No students in this scope. Add a student or assign students to this expertise check."
        case .noDomain:
            return "No students in this scope. Add a student or remove their expertise check assignment."
        }
    }

    private var legendView: some View {
        HStack(spacing: zoomManager.scaled(18)) {
            Text("Legend:")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: zoomManager.scaled(6)) {
                Text("✅")
                Text("Complete (100%)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: zoomManager.scaled(6)) {
                Text("☑️")
                Text("In Progress (1-99%)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: zoomManager.scaled(6)) {
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
        .padding(.horizontal, zoomManager.scaled(8))
    }

    private var studentBoardSection: some View {
        VStack(alignment: .leading, spacing: zoomManager.scaled(10)) {
            HStack(spacing: zoomManager.scaled(10)) {
                Text("Student Board")
                    .font(.headline)

                Spacer()
            }

            if boardStudents.isEmpty {
                ContentUnavailableView(
                    "No Students in Filter",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text("Change the filter to see students.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, zoomManager.scaled(12))
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: zoomManager.scaled(12)) {
                        ForEach(boardStudents) { boardStudent in
                            let overall = store.studentOverallProgress(student: boardStudent)

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
                                onUpdateGroups: { updatedGroups in
                                    setGroups(for: boardStudent, groups: updatedGroups)
                                }
                            )
                            .frame(width: zoomManager.scaled(240))
                            .task {
                                await store.loadProgressIfNeeded(for: boardStudent)
                            }
                        }

                        if isStudentDetailMode == false {
                            addStudentCard
                        }
                    }
                    .padding(.vertical, zoomManager.scaled(2))
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(zoomManager.scaled(16))
        .background(
            RoundedRectangle(cornerRadius: zoomManager.scaled(16))
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: zoomManager.scaled(16))
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private var toolbarFilterMenu: some View {
        filterMenuView()
            .help("Filter student cards by group or expertise check (also sets the scope shown in header and A-E breakdown)")
    }

    private func filterMenuView() -> some View {
        Menu {
            Button {
                beginScopeSwitch(to: .overall)
            } label: {
                Label("Overview", systemImage: "person.3")
            }

            Divider()

            Menu {
                Button {
                    beginScopeSwitch(to: .overall)
                } label: {
                    Label("All Groups...", systemImage: "person.2")
                }

                Divider()

                Button {
                    beginScopeSwitch(to: .ungrouped)
                } label: {
                    Label("Ungrouped", systemImage: "person.2.slash")
                }

                if groups.isEmpty == false {
                    Divider()

                    ForEach(groups) { group in
                        Button {
                            beginScopeSwitch(to: .group(group.id), group: group)
                        } label: {
                            Label(group.name, systemImage: "person.2")
                        }
                    }
                }
            } label: {
                Label("Groups", systemImage: "person.2")
            }

            Divider()

            Menu {
                Button {
                    beginScopeSwitch(to: .overall)
                } label: {
                    Label("All Expertise Check...", systemImage: "graduationcap")
                }

                Divider()

                Button {
                    beginScopeSwitch(to: .noDomain)
                } label: {
                    Label("No Expertise Check", systemImage: "graduationcap.slash")
                }

                if domains.isEmpty == false {
                    Divider()

                    ForEach(domains) { domain in
                        Button {
                            beginScopeSwitch(to: .domain(domain.id))
                        } label: {
                            Label(domain.name, systemImage: iconForExpertiseCheck(named: domain.name))
                        }
                    }
                }
            } label: {
                Label("Expertise Check", systemImage: "graduationcap")
            }
        } label: {
            Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    private var hardRefreshToolbarButton: some View {
        Button {
            Task { await store.hardRefreshFromCloudKit() }
        } label: {
            Label("Refresh", systemImage: "arrow.clockwise")
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(store.isLoading)
        .help("Force a full refresh from CloudKit")
    }

    private var exportToolbarButton: some View {
        Button {
            exportData()
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(store.isLoading || isExportingData)
        .help("Export the currently loaded dataset to a ZIP of CSV files")
    }

    private var resetToolbarButton: some View {
        Menu {
            Button("Reset Data (Keep Base Defaults)", role: .destructive) { resetData() }
        } label: {
            Label("Reset", systemImage: "ellipsis.circle")
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(store.isLoading)
        .help("Reset all data and restore base Expertise Check plus default Success Criteria/Milestones")
    }

    private var addStudentCard: some View {
        Button {
            showingAddSheet = true
        } label: {
            VStack(spacing: zoomManager.scaled(10)) {
                Image(systemName: "plus.circle.fill")
                    .font(zoomManager.scaledFont(size: 34, weight: .semibold))
                    .foregroundColor(.accentColor)

                Text("Add Student")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(width: zoomManager.scaled(160), height: zoomManager.scaled(120))
            .background(
                RoundedRectangle(cornerRadius: zoomManager.scaled(14))
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: zoomManager.scaled(14))
                    .stroke(Color.primary.opacity(0.10), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help("Add a new student")
    }

    private func exportData() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                exportData()
            }
            return
        }

        guard isExportingData == false else { return }

        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true
        savePanel.allowedContentTypes = [.zip]
        savePanel.nameFieldStringValue = "VisualTrackerExport_\(exportTimestamp()).zip"
        savePanel.title = "Export Visual Tracker Data"
        savePanel.message = "Choose where to save the CSV export ZIP."

        guard savePanel.runModal() == .OK, let destinationURL = savePanel.url else {
            return
        }

        let payload = store.makeCSVExportPayload()
        isExportingData = true

        Task(priority: .userInitiated) {
            do {
                let exporter = CSVExportService()
                let result = try exporter.exportZip(payload: payload, destinationURL: destinationURL)
                await MainActor.run {
                    isExportingData = false
                    exportSuccessMessage = "Exported \(result.exportedFiles.count) CSV files to \(result.outputURL.path)."
                    showingExportSuccess = true
                }
            } catch {
                await MainActor.run {
                    isExportingData = false
                    exportErrorMessage = error.localizedDescription
                    showingExportError = true
                }
            }
        }
    }

    private func exportTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmm"
        return formatter.string(from: Date())
    }

    private func resetData() {
        Task {
            await store.resetLearningObjectivesToDefaultTemplate()
            store.selectedStudentId = nil
            selectedGroup = nil
        }
    }

    private func beginScopeSwitch(to newFilter: StudentFilterScope, group: CohortGroup? = nil) {
        withAnimation(.easeInOut(duration: 0.15)) {
            store.selectedScope = newFilter
            selectedGroup = group
            selectedStudent = nil
        }
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
                group: nil,
                session: session,
                domain: domain,
                customProperties: customProperties
            ) {
                await store.setGroups(for: newStudent, groups: groups, updateLegacyGroupField: true)
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedStudent = newStudent
                }
            }
        }
    }

    private func deleteStudent(_ studentToDelete: Student) {
        let deletingSelected = selectedStudent?.id == studentToDelete.id
        Task {
            await store.deleteStudent(studentToDelete)

            if deletingSelected {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedStudent = nil
                }
            }
        }
    }

    private func setGroups(for student: Student, groups: [CohortGroup]) {
        Task {
            await store.setGroups(for: student, groups: groups, updateLegacyGroupField: true)
        }
    }

    private func studentMetadata(for student: Student) -> String {
        let groupName = groupSummary(for: student)
        let domainName = student.domain?.name ?? "No Expertise Check"
        return "\(groupName) • \(domainName) • \(student.session.rawValue)"
    }

    private func iconForExpertiseCheck(named name: String?) -> String {
        guard let name else {
            return "graduationcap"
        }

        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized == "tech" {
            return "cpu"
        }
        if normalized == "design" {
            return "paintbrush"
        }
        if normalized == "domain expert" {
            return "graduationcap"
        }
        return "tag"
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

    private func studentAvatar(for student: Student) -> some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: zoomManager.scaled(64), height: zoomManager.scaled(64))

            Text(student.name.prefix(1).uppercased())
                .font(zoomManager.scaledFont(size: 26, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
    }

    private func categoryDisplayTitle(for objective: LearningObjective) -> String {
        let canonical = objective.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if canonical.isEmpty, let label = categoryLabels.first(where: { $0.key == objective.code }) {
            return label.title
        }
        return canonical.isEmpty ? objective.code : objective.title
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

    private enum DisplayMode {
        case overview
        case student(Student)
    }
}
