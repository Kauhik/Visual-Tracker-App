import SwiftUI

struct ManageGroupsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: CloudKitStore
    @Environment(ZoomManager.self) private var zoomManager

    private var groups: [CohortGroup] { store.groups }
    private var students: [Student] { store.students }
    private var allObjectives: [LearningObjective] { store.learningObjectives }

    @State private var newGroupName: String = ""
    @State private var newGroupColor: GroupColorPreset = .none

    @State private var showingRenameSheet: Bool = false
    @State private var groupPendingRename: CohortGroup?

    @State private var groupPendingDelete: CohortGroup?

    var body: some View {
        VStack(alignment: .leading, spacing: zoomManager.scaled(16)) {
            HStack {
                Text("Manage Groups")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            addGroupRow

            Divider()
                .opacity(0.25)

            if groups.isEmpty {
                ContentUnavailableView(
                    "No Groups",
                    systemImage: "folder",
                    description: Text("Create a group to organise students.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(groups) { group in
                        groupRow(group)
                            .contextMenu {
                                Button("Rename") {
                                    groupPendingRename = group
                                    showingRenameSheet = true
                                }

                                Divider()

                                Button("Delete", role: .destructive) {
                                    groupPendingDelete = group
                                }
                            }
                    }
                }
                .listStyle(.inset)
            }
        }
        .padding(zoomManager.scaled(20))
        .frame(width: zoomManager.scaled(560), height: zoomManager.scaled(440))
        .sheet(isPresented: $showingRenameSheet) {
            if let group = groupPendingRename {
                RenameGroupSheet(group: group)
            }
        }
        .confirmationDialog(
            "Delete Group",
            isPresented: Binding(
                get: { groupPendingDelete != nil },
                set: { if $0 == false { groupPendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let group = groupPendingDelete {
                    deleteGroup(group)
                }
                groupPendingDelete = nil
            }

            Button("Cancel", role: .cancel) {
                groupPendingDelete = nil
            }
        } message: {
            if let group = groupPendingDelete {
                let count = students.filter { $0.group?.id == group.id }.count
                Text("\(count) student\(count == 1 ? "" : "s") will become Ungrouped.")
            }
        }
    }

    private var addGroupRow: some View {
        VStack(alignment: .leading, spacing: zoomManager.scaled(10)) {
            Text("Create Group")
                .font(.headline)

            HStack(spacing: zoomManager.scaled(10)) {
                TextField("Group Name", text: $newGroupName)

                Picker("Colour", selection: $newGroupColor) {
                    ForEach(GroupColorPreset.allCases, id: \.self) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .frame(width: zoomManager.scaled(160))

                Button("Add") { addGroup() }
                    .buttonStyle(.borderedProminent)
                    .disabled(newGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func groupRow(_ group: CohortGroup) -> some View {
        let count = students.filter { $0.group?.id == group.id }.count
        let average = ProgressCalculator.groupOverall(group: group, students: students, allObjectives: allObjectives)
        let badgeColor = Color(hex: group.colorHex) ?? Color.secondary.opacity(0.35)

        return HStack(spacing: zoomManager.scaled(12)) {
            Circle()
                .fill(badgeColor)
                .frame(width: zoomManager.scaled(10), height: zoomManager.scaled(10))

            VStack(alignment: .leading, spacing: zoomManager.scaled(2)) {
                Text(group.name)
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(group.name)

                Text("\(count) student\(count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: zoomManager.scaled(2)) {
                Text("\(average)%")
                    .font(.system(.callout, design: .rounded))
                    .fontWeight(.semibold)

                Text("Group average")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, zoomManager.scaled(4))
    }

    private func addGroup() {
        let trimmed = newGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        Task {
            await store.addGroup(name: trimmed, colorHex: newGroupColor.hexValue)
            newGroupName = ""
            newGroupColor = .none
        }
    }

    private func deleteGroup(_ group: CohortGroup) {
        Task {
            await store.deleteGroup(group)
        }
    }
}

private enum GroupColorPreset: CaseIterable, Hashable {
    case none
    case blue
    case green
    case orange
    case purple
    case pink
    case gray

    var title: String {
        switch self {
        case .none: return "Default"
        case .blue: return "Blue"
        case .green: return "Green"
        case .orange: return "Orange"
        case .purple: return "Purple"
        case .pink: return "Pink"
        case .gray: return "Gray"
        }
    }

    var hexValue: String? {
        switch self {
        case .none: return nil
        case .blue: return "#3B82F6"
        case .green: return "#10B981"
        case .orange: return "#F97316"
        case .purple: return "#8B5CF6"
        case .pink: return "#EC4899"
        case .gray: return "#6B7280"
        }
    }
}
