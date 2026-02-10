import SwiftUI

struct StudentCardView: View {
    @EnvironmentObject private var store: CloudKitStore
    @Environment(ZoomManager.self) private var zoomManager

    let student: Student
    let overallProgress: Int
    let isSelected: Bool
    let groups: [CohortGroup]
    let onSelect: () -> Void
    let onRequestDelete: () -> Void
    let onUpdateGroups: ([CohortGroup]) -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: zoomManager.scaled(11)) {
                HStack(spacing: zoomManager.scaled(10)) {
                    avatar

                    VStack(alignment: .leading, spacing: zoomManager.scaled(6)) {
                        Text(student.name)
                            .font(.headline)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .help(student.name)

                        metadataBadges
                    }
                    .layoutPriority(1)

                    Spacer()

                    ZStack {
                        CircularProgressView(progress: Double(overallProgress) / 100.0)
                            .frame(width: zoomManager.scaled(34), height: zoomManager.scaled(34))

                        Text("\(overallProgress)%")
                            .font(zoomManager.scaledFont(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(.primary)
                    }
                }
            }
            .padding(zoomManager.scaled(12))
            .background(
                RoundedRectangle(cornerRadius: zoomManager.scaled(14))
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: zoomManager.scaled(14))
                    .stroke(isSelected ? Color.accentColor.opacity(0.9) : Color.secondary.opacity(0.35), lineWidth: isSelected ? 2 : 1)
            )
            .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Menu("Assign Groups") {
                Button("Ungrouped") { onUpdateGroups([]) }
                if groups.isEmpty == false {
                    Divider()
                    ForEach(groups) { group in
                        Button {
                            var updatedGroups = store.groups(for: student)
                            if updatedGroups.contains(where: { $0.id == group.id }) {
                                updatedGroups.removeAll { $0.id == group.id }
                            } else {
                                updatedGroups.append(group)
                            }
                            onUpdateGroups(updatedGroups)
                        } label: {
                            Label(group.name, systemImage: assignedGroupIDs.contains(group.id) ? "checkmark.circle.fill" : "circle")
                        }
                    }
                }
            }

            Divider()

            Button("Delete Student", role: .destructive) {
                onRequestDelete()
            }
        }
        .accessibilityLabel(student.name)
        .accessibilityHint("Opens progress tracker")
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: zoomManager.scaled(40), height: zoomManager.scaled(40))

            Text(student.name.prefix(1).uppercased())
                .font(zoomManager.scaledFont(size: 19, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
    }

    private var metadataBadges: some View {
        let assignedGroups = store.groups(for: student)
        let groupSummary = groupSummary(for: assignedGroups)
        let color = Color(hex: assignedGroups.first?.colorHex) ?? Color.secondary.opacity(0.25)

        let groupPill = HStack(spacing: zoomManager.scaled(6)) {
            Circle()
                .fill(color)
                .frame(width: zoomManager.scaled(8), height: zoomManager.scaled(8))

            Text(groupSummary)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(groupSummary)
        }

        let domainName = student.domain?.name ?? "No Expertise Check"
        let sessionLabel = "\(student.session.rawValue) • \(domainName)"
        let sessionPill = Text(sessionLabel)
            .font(.caption2)
            .foregroundColor(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .help(sessionLabel)

        return ViewThatFits(in: .horizontal) {
            HStack(spacing: zoomManager.scaled(6)) {
                pill(groupPill)
                pill(sessionPill)
            }
            VStack(alignment: .leading, spacing: zoomManager.scaled(6)) {
                pill(groupPill)
                pill(sessionPill)
            }
        }
    }

    private func pill<Content: View>(_ content: Content) -> some View {
        content
            .padding(.horizontal, zoomManager.scaled(8))
            .padding(.vertical, zoomManager.scaled(4))
            .background(
                RoundedRectangle(cornerRadius: zoomManager.scaled(10))
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: zoomManager.scaled(10))
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }

    private var assignedGroupIDs: Set<UUID> {
        Set(store.groups(for: student).map(\.id))
    }

    private func groupSummary(for studentGroups: [CohortGroup]) -> String {
        if studentGroups.isEmpty {
            return "Ungrouped"
        }
        if studentGroups.count == 1 {
            return studentGroups[0].name
        }
        let primary = studentGroups[0].name
        return "\(primary) +\(studentGroups.count - 1)"
    }
}
