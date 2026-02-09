import SwiftUI

struct StudentDetailView: View {
    @Binding var selectedStudent: Student?
    @Binding var selectedGroup: CohortGroup?

    @EnvironmentObject private var store: CloudKitStore
    @EnvironmentObject private var activityCenter: ActivityCenter
    @Environment(ZoomManager.self) private var zoomManager

    @State private var showingAddSheet: Bool = false
    @State private var studentPendingDelete: Student?

    @State private var editingCategoryTarget: CategoryEditTarget?

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
        allObjectives
            .filter { $0.parentCode == nil }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private var ungroupedStudents: [Student] {
        students.filter { $0.group == nil }
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
            return students.filter { $0.group?.id == id }
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
            return domains.first(where: { $0.id == id })?.name ?? "Domain"
        case .noDomain:
            return "No Domain"
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
            return "chart.bar.fill"
        case .ungrouped:
            return "tray.fill"
        case .group:
            return "folder.fill"
        case .domain:
            return "tag.fill"
        case .noDomain:
            return "tag.slash"
        }
    }

    private var scopeOverallProgress: Int {
        switch selectedScope {
        case .overall:
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
            return ProgressCalculator.cohortOverall(students: filteredStudents, allObjectives: allObjectives)
        case .domain, .noDomain:
            return ProgressCalculator.cohortOverall(students: filteredStudents, allObjectives: allObjectives)
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
            return ProgressCalculator.studentOverall(student: student, allObjectives: allObjectives)
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

                overviewFilterMenu
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
                Text("A–E Summary")
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
            value = ProgressCalculator.objectivePercentage(
                student: student,
                objectiveCode: category.code,
                allObjectives: allObjectives
            )
        case .overview:
            value = ProgressCalculator.cohortObjectiveAverage(
                objectiveCode: category.code,
                students: breakdownStudents,
                allObjectives: allObjectives
            )
        }

        return HStack(spacing: zoomManager.scaled(12)) {
            Text(category.code.uppercased())
                .font(zoomManager.scaledFont(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(minWidth: zoomManager.scaled(24), alignment: .center)
                .padding(.horizontal, zoomManager.scaled(8))
                .padding(.vertical, zoomManager.scaled(4))
                .background(
                    RoundedRectangle(cornerRadius: zoomManager.scaled(8))
                        .fill(categoryColor(for: category.code))
                )

            VStack(alignment: .leading, spacing: zoomManager.scaled(2)) {
                Text(categoryDisplayTitle(for: category))
                    .font(.callout)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(categoryDisplayTitle(for: category))
                    .layoutPriority(1)
                    .contextMenu {
                        Button("Edit Title...") {
                            editingCategoryTarget = CategoryEditTarget(code: category.code, fallbackTitle: category.title)
                        }
                    }
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
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: zoomManager.scaled(12))
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
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
            return "No Students in Domain"
        case .noDomain:
            return "No Students with No Domain"
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
            return "No students in this scope. Add a student or assign students to this domain."
        case .noDomain:
            return "No students in this scope. Add a student or remove their domain assignment."
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

                studentBoardFilterMenu
                    .buttonStyle(.bordered)
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

    private var studentBoardFilterMenu: some View {
        filterMenuView(style: .standard)
            .help("Filter student cards by group or domain (also sets the scope shown in header and A–E breakdown)")
    }

    private var overviewFilterMenu: some View {
        filterMenuView(style: .compact)
            .help("Change the scope shown in the overview container (group or domain)")
    }

    private func filterMenuView(style: FilterMenuStyle) -> some View {
        Menu {
            Button("Overall") {
                beginScopeSwitch(to: .overall)
            }

            Divider()

            Menu("Groups") {
                Button("All Groups…") {
                    beginScopeSwitch(to: .overall)
                }

                Divider()

                Button("Ungrouped") {
                    beginScopeSwitch(to: .ungrouped)
                }

                if groups.isEmpty == false {
                    Divider()

                    ForEach(groups) { group in
                        Button(group.name) {
                            beginScopeSwitch(to: .group(group.id), group: group)
                        }
                    }
                }
            }

            Divider()

            Menu("Domains") {
                Button("All Domains…") {
                    beginScopeSwitch(to: .overall)
                }

                Divider()

                Button("No Domain") {
                    beginScopeSwitch(to: .noDomain)
                }

                if domains.isEmpty == false {
                    Divider()

                    ForEach(domains) { domain in
                        Button(domain.name) {
                            beginScopeSwitch(to: .domain(domain.id))
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: zoomManager.scaled(style == .compact ? 6 : 8)) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .foregroundColor(.secondary)

                Text(style == .compact ? "Scope:" : "Filter:")
                    .font(style == .compact ? .caption2 : .caption)
                    .foregroundColor(.secondary)

                Text(selectedScope.title(groups: groups, domains: domains))
                    .font(style == .compact ? .caption2 : .caption)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(selectedScope.title(groups: groups, domains: domains))
                    .layoutPriority(1)

                Image(systemName: "chevron.down")
                    .font(style == .compact ? .caption2 : .caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, zoomManager.scaled(style == .compact ? 8 : 10))
            .padding(.vertical, zoomManager.scaled(style == .compact ? 4 : 6))
            .background(
                RoundedRectangle(cornerRadius: zoomManager.scaled(style == .compact ? 8 : 10))
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: zoomManager.scaled(style == .compact ? 8 : 10))
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
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

    private func beginScopeSwitch(to newFilter: StudentFilterScope, group: CohortGroup? = nil) {
        withAnimation(.easeInOut(duration: 0.15)) {
            store.selectedScope = newFilter
            selectedGroup = group
            selectedStudent = nil
        }
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

    private func move(student: Student, to group: CohortGroup?) {
        Task {
            await store.moveStudent(student, to: group)
        }
    }

    private func studentMetadata(for student: Student) -> String {
        let groupName = student.group?.name ?? "Ungrouped"
        let domainName = student.domain?.name ?? "No Domain"
        return "\(groupName) • \(domainName) • \(student.session.rawValue)"
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

    private enum DisplayMode {
        case overview
        case student(Student)
    }
}
