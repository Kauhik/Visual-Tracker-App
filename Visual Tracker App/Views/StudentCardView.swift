import SwiftUI

struct StudentCardView: View {
    let student: Student
    let overallProgress: Int
    let isSelected: Bool
    let onSelect: () -> Void
    let onRequestDelete: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    avatar

                    VStack(alignment: .leading, spacing: 2) {
                        Text(student.name)
                            .font(.headline)
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        Text("Overall")
                            .font(.caption)
                            .foregroundColor(.secondary)
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
}