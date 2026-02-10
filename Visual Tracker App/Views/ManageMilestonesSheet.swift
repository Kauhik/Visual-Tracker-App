import SwiftUI

struct ManageMilestonesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: CloudKitStore
    @Environment(ZoomManager.self) private var zoomManager

    @State private var newCode: String = ""
    @State private var newTitle: String = ""
    @State private var newDescription: String = ""
    @State private var newIsQuantitative: Bool = false
    @State private var selectedParentID: UUID?

    @State private var editingObjective: LearningObjective?
    @State private var objectivePendingArchive: LearningObjective?

    @State private var showingError: Bool = false
    @State private var errorMessage: String = ""

    private var allObjectives: [LearningObjective] { store.learningObjectives }

    private var rootObjectives: [LearningObjective] {
        allObjectives
            .filter { $0.isRootCategory && $0.isArchived == false }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private var milestones: [LearningObjective] {
        allObjectives
            .filter { $0.isRootCategory == false && $0.isArchived == false }
            .sorted {
                if $0.sortOrder != $1.sortOrder {
                    return $0.sortOrder < $1.sortOrder
                }
                return $0.code < $1.code
            }
    }

    private var unassignedMilestones: [LearningObjective] {
        milestones.filter { rootParent(for: $0) == nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: zoomManager.scaled(16)) {
            HStack {
                Text("Manage Milestones")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            addRow

            Divider()
                .opacity(0.25)

            if milestones.isEmpty {
                ContentUnavailableView(
                    "No Milestones",
                    systemImage: "list.number",
                    description: Text("Create milestones under a success criterion.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(rootObjectives) { root in
                        let sectionItems = milestonesForRoot(root)
                        if sectionItems.isEmpty == false {
                            Section {
                                ForEach(sectionItems) { milestone in
                                    row(milestone)
                                }
                            } header: {
                                rootHeader(root)
                            }
                        }
                    }

                    if unassignedMilestones.isEmpty == false {
                        Section("Unassigned Parent") {
                            ForEach(unassignedMilestones) { milestone in
                                row(milestone)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .padding(zoomManager.scaled(20))
        .frame(width: zoomManager.scaled(860), height: zoomManager.scaled(620))
        .sheet(item: $editingObjective) { objective in
            MilestoneEditorSheet(
                objective: objective,
                rootOptions: rootObjectives,
                selectedParent: rootParent(for: objective)
            ) { code, title, description, isQuantitative, parent in
                updateMilestone(
                    objective,
                    code: code,
                    title: title,
                    description: description,
                    isQuantitative: isQuantitative,
                    parent: parent
                )
            }
        }
        .confirmationDialog(
            "Archive Milestone",
            isPresented: Binding(
                get: { objectivePendingArchive != nil },
                set: { if $0 == false { objectivePendingArchive = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Archive", role: .destructive) {
                if let objective = objectivePendingArchive {
                    archiveMilestone(objective)
                }
                objectivePendingArchive = nil
            }

            Button("Cancel", role: .cancel) {
                objectivePendingArchive = nil
            }
        } message: {
            if let objective = objectivePendingArchive {
                Text("Archive '\(objective.title)'?")
            }
        }
        .alert("Action Failed", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            if selectedParentID == nil {
                selectedParentID = rootObjectives.first?.id
            }
        }
    }

    private var addRow: some View {
        VStack(alignment: .leading, spacing: zoomManager.scaled(10)) {
            Text("Create Milestone")
                .font(.headline)

            HStack(spacing: zoomManager.scaled(10)) {
                TextField("Code (e.g. A.4)", text: $newCode)
                    .frame(width: zoomManager.scaled(170))

                TextField("Title", text: $newTitle)

                Picker("Parent", selection: $selectedParentID) {
                    ForEach(rootObjectives) { root in
                        Text("\(root.code) - \(root.title)").tag(root.id as UUID?)
                    }
                }
                .frame(width: zoomManager.scaled(240))

                Toggle("Quantitative", isOn: $newIsQuantitative)
                    .toggleStyle(.checkbox)
                    .fixedSize()

                Button("Add") {
                    addMilestone()
                }
                .buttonStyle(.borderedProminent)
                .disabled(canCreateMilestone == false)
            }

            TextField("Description (optional)", text: $newDescription)
        }
    }

    private var canCreateMilestone: Bool {
        newCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        && newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        && selectedParentID != nil
    }

    private func row(_ objective: LearningObjective) -> some View {
        let siblings = milestonesForDirectParent(of: objective)
        let index = siblings.firstIndex(where: { $0.id == objective.id }) ?? 0
        let isFirst = index == 0
        let isLast = index == max(siblings.count - 1, 0)

        return HStack(spacing: zoomManager.scaled(10)) {
            Text(objective.code)
                .font(.system(.body, design: .monospaced))
                .fontWeight(.semibold)
                .frame(width: zoomManager.scaled(88), alignment: .leading)

            VStack(alignment: .leading, spacing: zoomManager.scaled(2)) {
                Text(objective.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(objective.title)

                Text(parentLabel(for: objective))
                    .font(.caption)
                    .foregroundColor(.secondary)

                if store.isPendingCreate(objective: objective) {
                    HStack(spacing: zoomManager.scaled(4)) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Saving...")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            if objective.isQuantitative {
                Text("Quant")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, zoomManager.scaled(8))
                    .padding(.vertical, zoomManager.scaled(4))
                    .background(
                        Capsule()
                            .fill(Color.secondary.opacity(0.16))
                    )
            }

            HStack(spacing: zoomManager.scaled(4)) {
                Button {
                    moveMilestone(objective, direction: -1)
                } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.borderless)
                .disabled(isFirst)

                Button {
                    moveMilestone(objective, direction: 1)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.borderless)
                .disabled(isLast)
            }
            .foregroundColor(.secondary)
        }
        .padding(.vertical, zoomManager.scaled(4))
        .contextMenu {
            Button("Edit") {
                editingObjective = objective
            }

            Divider()

            Button("Archive", role: .destructive) {
                objectivePendingArchive = objective
            }
        }
    }

    private func rootHeader(_ root: LearningObjective) -> some View {
        HStack(spacing: zoomManager.scaled(8)) {
            Text(root.code)
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.semibold)

            Text(root.title)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private func addMilestone() {
        let code = newCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = newDescription.trimmingCharacters(in: .whitespacesAndNewlines)

        guard code.isEmpty == false, title.isEmpty == false else { return }
        guard allObjectives.contains(where: { $0.code.caseInsensitiveCompare(code) == .orderedSame }) == false else {
            showError("A milestone with code '\(code)' already exists.")
            return
        }
        guard let parentID = selectedParentID,
              let parent = rootObjectives.first(where: { $0.id == parentID }) else {
            showError("Select a parent success criterion.")
            return
        }

        let siblings = milestonesForDirectParent(ofParent: parent)
        let nextSort = (siblings.map(\.sortOrder).max() ?? 0) + 1

        Task {
            _ = await store.createLearningObjective(
                code: code,
                title: title,
                description: description,
                isQuantitative: newIsQuantitative,
                parent: parent,
                sortOrder: nextSort
            )
            if let error = store.lastErrorMessage {
                showError(error)
            } else {
                newCode = ""
                newTitle = ""
                newDescription = ""
                newIsQuantitative = false
            }
        }
    }

    private func updateMilestone(
        _ objective: LearningObjective,
        code: String,
        title: String,
        description: String,
        isQuantitative: Bool,
        parent: LearningObjective?
    ) {
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedCode.isEmpty == false, trimmedTitle.isEmpty == false else { return }

        let duplicateCodeExists = allObjectives.contains {
            $0.id != objective.id && $0.code.caseInsensitiveCompare(trimmedCode) == .orderedSame
        }
        guard duplicateCodeExists == false else {
            showError("Another objective already uses code '\(trimmedCode)'.")
            return
        }

        Task {
            await store.updateLearningObjective(
                objective,
                code: trimmedCode,
                title: trimmedTitle,
                description: trimmedDescription,
                isQuantitative: isQuantitative,
                parent: parent,
                sortOrder: objective.sortOrder,
                isArchived: false
            )
            if let error = store.lastErrorMessage {
                showError(error)
            } else {
                editingObjective = nil
            }
        }
    }

    private func moveMilestone(_ objective: LearningObjective, direction: Int) {
        let siblings = milestonesForDirectParent(of: objective)
        guard let index = siblings.firstIndex(where: { $0.id == objective.id }) else { return }
        let target = index + direction
        guard siblings.indices.contains(target) else { return }

        let other = siblings[target]
        let objectiveSort = objective.sortOrder
        let otherSort = other.sortOrder

        Task {
            await store.updateLearningObjective(
                objective,
                code: objective.code,
                title: objective.title,
                description: objective.objectiveDescription,
                isQuantitative: objective.isQuantitative,
                parent: resolvedParent(for: objective),
                sortOrder: otherSort,
                isArchived: false
            )
            await store.updateLearningObjective(
                other,
                code: other.code,
                title: other.title,
                description: other.objectiveDescription,
                isQuantitative: other.isQuantitative,
                parent: resolvedParent(for: other),
                sortOrder: objectiveSort,
                isArchived: false
            )
            if let error = store.lastErrorMessage {
                showError(error)
            }
        }
    }

    private func archiveMilestone(_ objective: LearningObjective) {
        Task {
            await store.archiveLearningObjective(objective)
            if let error = store.lastErrorMessage {
                showError(error)
            }
        }
    }

    private func milestonesForRoot(_ root: LearningObjective) -> [LearningObjective] {
        milestones.filter { rootParent(for: $0)?.id == root.id }
    }

    private func milestonesForDirectParent(of objective: LearningObjective) -> [LearningObjective] {
        milestones.filter { directParentKey(of: $0) == directParentKey(of: objective) }
            .sorted {
                if $0.sortOrder != $1.sortOrder {
                    return $0.sortOrder < $1.sortOrder
                }
                return $0.code < $1.code
            }
    }

    private func milestonesForDirectParent(ofParent parent: LearningObjective) -> [LearningObjective] {
        milestones.filter { objective in
            if let parentId = objective.parentId {
                return parentId == parent.id
            }
            return objective.parentCode == parent.code
        }
            .sorted {
                if $0.sortOrder != $1.sortOrder {
                    return $0.sortOrder < $1.sortOrder
                }
                return $0.code < $1.code
            }
    }

    private func resolvedParent(for objective: LearningObjective) -> LearningObjective? {
        if let parentId = objective.parentId {
            return allObjectives.first(where: { $0.id == parentId })
        }
        if let parentCode = objective.parentCode {
            return allObjectives.first(where: { $0.code == parentCode })
        }
        return nil
    }

    private func rootParent(for objective: LearningObjective) -> LearningObjective? {
        guard let parent = resolvedParent(for: objective) else { return nil }
        if parent.isRootCategory {
            return parent
        }
        return rootParent(for: parent)
    }

    private func directParentKey(of objective: LearningObjective) -> String {
        if let parentId = objective.parentId {
            return parentId.uuidString
        }
        if let parentCode = objective.parentCode {
            return "code:\(parentCode)"
        }
        return "__nil__"
    }

    private func parentLabel(for objective: LearningObjective) -> String {
        if let parent = resolvedParent(for: objective) {
            return "Parent: \(parent.code)"
        }
        if let parentCode = objective.parentCode, parentCode.isEmpty == false {
            return "Parent: \(parentCode)"
        }
        return "Parent: none"
    }

    private func showError(_ message: String) {
        errorMessage = message
        showingError = true
    }
}

private struct MilestoneEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ZoomManager.self) private var zoomManager

    let objective: LearningObjective
    let rootOptions: [LearningObjective]
    let selectedParent: LearningObjective?
    let onSave: (String, String, String, Bool, LearningObjective?) -> Void

    @State private var code: String = ""
    @State private var title: String = ""
    @State private var description: String = ""
    @State private var isQuantitative: Bool = false
    @State private var selectedParentID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: zoomManager.scaled(16)) {
            Text("Edit Milestone")
                .font(.title2)
                .fontWeight(.semibold)

            Form {
                TextField("Code", text: $code)
                TextField("Title", text: $title)
                TextField("Description", text: $description)

                Picker("Parent Success Criterion", selection: $selectedParentID) {
                    Text("None").tag(nil as UUID?)
                    ForEach(rootOptions) { root in
                        Text("\(root.code) - \(root.title)").tag(root.id as UUID?)
                    }
                }

                Toggle("Quantitative", isOn: $isQuantitative)
            }
            .formStyle(.grouped)

            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }

                Button("Save") {
                    let parent = rootOptions.first(where: { $0.id == selectedParentID })
                    onSave(
                        code.trimmingCharacters(in: .whitespacesAndNewlines),
                        title.trimmingCharacters(in: .whitespacesAndNewlines),
                        description.trimmingCharacters(in: .whitespacesAndNewlines),
                        isQuantitative,
                        parent
                    )
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(zoomManager.scaled(20))
        .frame(width: zoomManager.scaled(560))
        .onAppear {
            code = objective.code
            title = objective.title
            description = objective.objectiveDescription
            isQuantitative = objective.isQuantitative
            selectedParentID = selectedParent?.id
        }
    }
}
