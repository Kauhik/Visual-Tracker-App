import SwiftUI

struct ManageSuccessCriteriaSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: CloudKitStore
    @Environment(ZoomManager.self) private var zoomManager

    @State private var newCode: String = ""
    @State private var newTitle: String = ""
    @State private var newDescription: String = ""
    @State private var newIsQuantitative: Bool = false

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

    var body: some View {
        VStack(alignment: .leading, spacing: zoomManager.scaled(16)) {
            HStack {
                Text("Manage Success Criteria")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            addRow

            Text("Archiving a success criterion does not automatically archive milestones.")
                .font(.caption)
                .foregroundColor(.secondary)

            Divider()
                .opacity(0.25)

            if rootObjectives.isEmpty {
                ContentUnavailableView(
                    "No Success Criteria",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Create at least one root success criterion.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(Array(rootObjectives.enumerated()), id: \.element.id) { index, objective in
                        row(objective, index: index)
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
                }
                .listStyle(.inset)
            }
        }
        .padding(zoomManager.scaled(20))
        .frame(width: zoomManager.scaled(760), height: zoomManager.scaled(560))
        .sheet(item: $editingObjective) { objective in
            SuccessCriteriaEditorSheet(objective: objective) { title, description, isQuantitative in
                updateRootObjective(
                    objective,
                    title: title,
                    description: description,
                    isQuantitative: isQuantitative
                )
            }
        }
        .confirmationDialog(
            "Archive Success Criterion",
            isPresented: Binding(
                get: { objectivePendingArchive != nil },
                set: { if $0 == false { objectivePendingArchive = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Archive Root Only", role: .destructive) {
                if let objective = objectivePendingArchive {
                    archiveRoot(objective, includeChildren: false)
                }
                objectivePendingArchive = nil
            }

            Button("Archive Root + Milestones", role: .destructive) {
                if let objective = objectivePendingArchive {
                    archiveRoot(objective, includeChildren: true)
                }
                objectivePendingArchive = nil
            }

            Button("Cancel", role: .cancel) {
                objectivePendingArchive = nil
            }
        } message: {
            if let objective = objectivePendingArchive {
                let descendants = descendants(of: objective).count
                Text("Archive '\(objective.title)'? \(descendants) milestone(s) are under this criterion.")
            }
        }
        .alert("Action Failed", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    private var addRow: some View {
        VStack(alignment: .leading, spacing: zoomManager.scaled(10)) {
            Text("Create Success Criterion")
                .font(.headline)

            HStack(spacing: zoomManager.scaled(10)) {
                TextField("Code (e.g. F)", text: $newCode)
                    .frame(width: zoomManager.scaled(140))

                TextField("Title", text: $newTitle)

                Toggle("Quantitative", isOn: $newIsQuantitative)
                    .toggleStyle(.checkbox)
                    .fixedSize()

                Button("Add") {
                    addRootObjective()
                }
                .buttonStyle(.borderedProminent)
                .disabled(newCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            TextField("Description (optional)", text: $newDescription)
        }
    }

    private func row(_ objective: LearningObjective, index: Int) -> some View {
        let childrenCount = descendants(of: objective).count

        return HStack(spacing: zoomManager.scaled(10)) {
            Text(objective.code)
                .font(.system(.body, design: .monospaced))
                .fontWeight(.semibold)
                .frame(width: zoomManager.scaled(72), alignment: .leading)

            VStack(alignment: .leading, spacing: zoomManager.scaled(2)) {
                Text(objective.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(objective.title)

                Text("\(childrenCount) milestone\(childrenCount == 1 ? "" : "s")")
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
                    moveRootObjective(objective, direction: -1)
                } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.borderless)
                .disabled(index == 0)

                Button {
                    moveRootObjective(objective, direction: 1)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.borderless)
                .disabled(index == rootObjectives.count - 1)
            }
            .foregroundColor(.secondary)
        }
        .padding(.vertical, zoomManager.scaled(4))
    }

    private func addRootObjective() {
        let code = newCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = newDescription.trimmingCharacters(in: .whitespacesAndNewlines)

        guard code.isEmpty == false, title.isEmpty == false else { return }
        guard allObjectives.contains(where: { $0.code.caseInsensitiveCompare(code) == .orderedSame }) == false else {
            showError("A success criterion with code '\(code)' already exists.")
            return
        }

        let nextSort = (rootObjectives.map(\.sortOrder).max() ?? 0) + 1
        Task {
            _ = await store.createLearningObjective(
                code: code,
                title: title,
                description: description,
                isQuantitative: newIsQuantitative,
                parent: nil,
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

    private func updateRootObjective(
        _ objective: LearningObjective,
        title: String,
        description: String,
        isQuantitative: Bool
    ) {
        Task {
            await store.updateLearningObjective(
                objective,
                code: objective.code,
                title: title,
                description: description,
                isQuantitative: isQuantitative,
                parent: nil,
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

    private func moveRootObjective(_ objective: LearningObjective, direction: Int) {
        let ordered = rootObjectives
        guard let index = ordered.firstIndex(where: { $0.id == objective.id }) else { return }
        let target = index + direction
        guard ordered.indices.contains(target) else { return }

        let other = ordered[target]
        let objectiveSort = objective.sortOrder
        let otherSort = other.sortOrder

        Task {
            await store.updateLearningObjective(
                objective,
                code: objective.code,
                title: objective.title,
                description: objective.objectiveDescription,
                isQuantitative: objective.isQuantitative,
                parent: nil,
                sortOrder: otherSort,
                isArchived: false
            )
            await store.updateLearningObjective(
                other,
                code: other.code,
                title: other.title,
                description: other.objectiveDescription,
                isQuantitative: other.isQuantitative,
                parent: nil,
                sortOrder: objectiveSort,
                isArchived: false
            )
            if let error = store.lastErrorMessage {
                showError(error)
            }
        }
    }

    private func archiveRoot(_ objective: LearningObjective, includeChildren: Bool) {
        let children = includeChildren ? descendants(of: objective) : []
        Task {
            if includeChildren {
                for child in children {
                    await store.archiveLearningObjective(child)
                }
            }
            await store.archiveLearningObjective(objective)
            if let error = store.lastErrorMessage {
                showError(error)
            }
        }
    }

    private func descendants(of objective: LearningObjective) -> [LearningObjective] {
        let directChildren = allObjectives.filter { $0.isChild(of: objective) && $0.isArchived == false }
        var collected: [LearningObjective] = directChildren
        for child in directChildren {
            collected.append(contentsOf: descendants(of: child))
        }
        return collected
    }

    private func showError(_ message: String) {
        errorMessage = message
        showingError = true
    }
}

private struct SuccessCriteriaEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ZoomManager.self) private var zoomManager

    let objective: LearningObjective
    let onSave: (String, String, Bool) -> Void

    @State private var title: String = ""
    @State private var description: String = ""
    @State private var isQuantitative: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: zoomManager.scaled(16)) {
            Text("Edit Success Criterion")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Code: \(objective.code)")
                .font(.caption)
                .foregroundColor(.secondary)

            Form {
                TextField("Title", text: $title)
                TextField("Description", text: $description)
                Toggle("Quantitative", isOn: $isQuantitative)
            }
            .formStyle(.grouped)

            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }

                Button("Save") {
                    let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard trimmedTitle.isEmpty == false else { return }
                    onSave(trimmedTitle, description.trimmingCharacters(in: .whitespacesAndNewlines), isQuantitative)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(zoomManager.scaled(20))
        .frame(width: zoomManager.scaled(520))
        .onAppear {
            title = objective.title
            description = objective.objectiveDescription
            isQuantitative = objective.isQuantitative
        }
    }
}
