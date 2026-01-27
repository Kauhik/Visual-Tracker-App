import SwiftUI

struct StudentCardView: View {
    let student: Student
    let overallProgress: Int
    let isSelected: Bool
    let groups: [CohortGroup]
    let onSelect: () -> Void
    let onRequestDelete: () -> Void
    let onMoveToGroup: (CohortGroup?) -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    avatar

                    VStack(alignment: .leading, spacing: 6) {
                        Text(student.name)
                            .font(.headline)
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        groupBadge
                    }

                    Spacer()

                    ZStack {
                        CircularProgressView(progress: Double(overallProgress) / 100.0)
                            .frame(width: 38, height: 38)

                        Text("\(overallProgress)%")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundColor(.primary)
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Color.accentColor.opacity(0.8) : Color.clear, lineWidth: 2)
            )
            .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Menu("Move to Group") {
                Button("Ungrouped") { onMoveToGroup(nil) }
                if groups.isEmpty == false {
                    Divider()
                    ForEach(groups) { group in
                        Button(group.name) { onMoveToGroup(group) }
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
                .frame(width: 42, height: 42)

            Text(student.name.prefix(1).uppercased())
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
    }

    private var groupBadge: some View {
        let name = student.group?.name ?? "Ungrouped"
        let color = Color(hex: student.group?.colorHex) ?? Color.secondary.opacity(0.25)

        return HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            Text(name)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}
