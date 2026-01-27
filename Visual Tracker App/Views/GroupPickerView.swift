import SwiftUI
import SwiftData

struct GroupPickerView: View {
    let title: String
    @Binding var selectedGroup: CohortGroup?

    @Query(sort: \CohortGroup.name) private var groups: [CohortGroup]

    var body: some View {
        Menu {
            Button("Ungrouped") { selectedGroup = nil }
            if groups.isEmpty == false {
                Divider()
                ForEach(groups) { group in
                    Button(group.name) { selectedGroup = group }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(groupDisplayColor)
                    .frame(width: 10, height: 10)

                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(selectedGroup?.name ?? "Ungrouped")
                    .font(.caption)
                    .fontWeight(.semibold)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
    }

    private var groupDisplayColor: Color {
        if let c = Color(hex: selectedGroup?.colorHex) {
            return c
        }
        return Color.secondary.opacity(0.6)
    }
}
