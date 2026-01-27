import SwiftUI
import SwiftData

struct StudentDetailView: View {
    let student: Student

    @Query(sort: \LearningObjective.sortOrder) private var allObjectives: [LearningObjective]

    private var rootCategories: [LearningObjective] {
        allObjectives
            .filter { $0.parentCode == nil }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private var overallProgress: Int {
        ProgressCalculator.studentOverall(student: student, allObjectives: allObjectives)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                studentHeader
                legendView
                Divider()

                ForEach(rootCategories) { category in
                    CategorySectionView(
                        categoryObjective: category,
                        student: student,
                        allObjectives: allObjectives
                    )
                }
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var studentHeader: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 64, height: 64)

                Text(student.name.prefix(1).uppercased())
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(student.name)
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Challenge-Based Learning Progress")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("Overall Progress")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    Text("\(overallProgress)%")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(.accentColor)

                    CircularProgressView(progress: Double(overallProgress) / 100.0)
                        .frame(width: 50, height: 50)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
        )
    }

    private var legendView: some View {
        HStack(spacing: 24) {
            Text("Legend:")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 6) {
                Text("✅")
                Text("Complete (100%)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 6) {
                Text("☑️")
                Text("In Progress (1-99%)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 6) {
                Text("⬜")
                Text("Not Started (0%)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text("Click the slider icon to toggle completion")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
    }
}