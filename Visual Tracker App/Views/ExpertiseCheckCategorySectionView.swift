import SwiftUI

struct ExpertiseCheckCategorySectionView: View {
    let categoryObjective: LearningObjective
    let expertiseCheck: Domain
    let students: [Student]

    @EnvironmentObject private var store: CloudKitStore
    @Environment(ZoomManager.self) private var zoomManager

    @State private var isExpanded: Bool = true
    @State private var isHeaderHovering: Bool = false

    private var categoryLabels: [CategoryLabel] { store.categoryLabels }

    private var childObjectives: [LearningObjective] {
        store.childObjectives(of: categoryObjective)
    }

    private var aggregatePercentage: Int {
        if expertiseCheck.overallMode == .expertReview {
            return store.expertiseCheckReviewerObjectivePercentage(domain: expertiseCheck, objective: categoryObjective)
        }
        return store.cohortObjectiveAverage(objective: categoryObjective, students: students)
    }

    private var aggregateStatus: ProgressStatus {
        ObjectiveProgress.calculateStatus(from: aggregatePercentage)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: zoomManager.scaled(12)) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: zoomManager.scaled(16))

                    SuccessCriteriaBadge(
                        code: categoryObjective.code,
                        font: .system(.headline, design: .rounded),
                        horizontalPadding: zoomManager.scaled(10),
                        verticalPadding: zoomManager.scaled(4),
                        cornerRadius: zoomManager.scaled(6)
                    )

                    Text(categoryDisplayTitle(for: categoryObjective))
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(categoryDisplayTitle(for: categoryObjective))
                        .layoutPriority(1)

                    Spacer()

                    HStack(spacing: zoomManager.scaled(8)) {
                        Text(aggregateStatus.indicator)
                            .font(.title2)

                        Text("\(aggregatePercentage)%")
                            .font(.system(.headline, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, zoomManager.scaled(12))
                .padding(.horizontal, zoomManager.scaled(16))
                .background(
                    RoundedRectangle(cornerRadius: zoomManager.scaled(10))
                        .fill(SuccessCriteriaStyle.subtleFill(for: categoryObjective.code, isHovered: isHeaderHovering))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isHeaderHovering = hovering
            }
            .contextMenu {
                Button(isExpanded ? "Collapse" : "Expand") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(childObjectives, id: \.id) { child in
                        ExpertiseCheckObjectiveTreeView(
                            rootObjective: child,
                            expertiseCheck: expertiseCheck,
                            students: students,
                            startIndentLevel: 1
                        )
                    }
                }
                .padding(.leading, zoomManager.scaled(28))
                .padding(.top, zoomManager.scaled(8))
                .padding(.bottom, zoomManager.scaled(12))
            }
        }
    }

    private func categoryDisplayTitle(for objective: LearningObjective) -> String {
        let canonical = objective.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if canonical.isEmpty, let label = categoryLabels.first(where: { $0.key == objective.code }) {
            return label.title
        }
        return canonical.isEmpty ? objective.code : objective.title
    }
}
