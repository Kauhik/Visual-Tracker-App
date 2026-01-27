import SwiftUI
import SwiftData

struct ManageGroupsSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \CohortGroup.name) private var groups: [CohortGroup]
    @Query(sort: \Student.createdAt) private var students: [Student]
    @Query(sort: \LearningObjective.sortOrder) private var allObjectives: [LearningObjective]

    @State private var newGroupName: String = ""
    @State private var newGroupColor: GroupColorPreset = .none

    @State private var showingRenameSheet: Bool = false
    @State private var groupPendingRename: CohortGroup?

    @State private var groupPendingDelete: CohortGroup?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
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
        .padding(20)
        .frame(width: 560, height: 440)
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
        VStack(alignment: .leading, spacing: 10) {
            Text("Create Group")
                .font(.headline)

            HStack(spacing: 10) {
                TextField("Group Name", text: $newGroupName)

                Picker("Colour", selection: $newGroupColor) {
                    ForEach(GroupColorPreset.allCases, id: \.self) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .frame(width: 160)

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

        return HStack(spacing: 12) {
            Circle()
                .fill(badgeColor)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(group.name)
                    .font(.body)

                Text("\(count) student\(count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(average)%")
                    .font(.system(.callout, design: .rounded))
                    .fontWeight(.semibold)

                Text("Group average")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func addGroup() {
        let trimmed = newGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }

        let group = CohortGroup(name: trimmed, colorHex: newGroupColor.hexValue)
        modelContext.insert(group)

        do {
            try modelContext.save()
            newGroupName = ""
            newGroupColor = .none
        } catch {
            print("Failed to add group: \(error)")
        }
    }

    private func deleteGroup(_ group: CohortGroup) {
        let affected = students.filter { $0.group?.id == group.id }
        for student in affected {
            student.group = nil
        }

        modelContext.delete(group)

        do {
            try modelContext.save()
        } catch {
            print("Failed to delete group: \(error)")
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
