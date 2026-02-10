import SwiftUI

struct CategorySectionView: View {
    let categoryObjective: LearningObjective
    let student: Student
    let allObjectives: [LearningObjective]

    @EnvironmentObject private var store: CloudKitStore
    @Environment(ZoomManager.self) private var zoomManager

    private var categoryLabels: [CategoryLabel] { store.categoryLabels }

    @State private var isExpanded: Bool = true
    @State private var editingTarget: CategoryEditTarget?
    @State private var isHeaderHovering: Bool = false

    private var childObjectives: [LearningObjective] {
        allObjectives
            .filter { $0.isChild(of: categoryObjective) && $0.isArchived == false }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private var aggregatePercentage: Int {
        ProgressCalculator.objectivePercentage(
            student: student,
            objective: categoryObjective,
            allObjectives: allObjectives
        )
    }

    private var aggregateStatus: ProgressStatus {
        ObjectiveProgress.calculateStatus(from: aggregatePercentage)
    }

    private var formulaDisplay: String? {
        if categoryObjective.code == "A" {
            let a1 = objectivePercentage(forCode: "A.1")
            let a2 = objectivePercentage(forCode: "A.2")
            let a3 = objectivePercentage(forCode: "A.3")
            let sum = a1 + a2 + a3
            let avg = Double(sum) / 3.0
            return "(\(a1) + \(a2) + \(a3)) / 300% = \(String(format: "%.3f", avg / 100.0 * 100))%"
        }
        return nil
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
                Button("Edit Title...") {
                    editingTarget = CategoryEditTarget(
                        code: categoryObjective.code,
                        fallbackTitle: categoryObjective.title
                    )
                }
            }

            if let formula = formulaDisplay, isExpanded {
                HStack {
                    Spacer()
                    Text(formula)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, zoomManager.scaled(16))
                        .padding(.top, zoomManager.scaled(4))
                }
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(childObjectives) { child in
                        ObjectiveTreeView(
                            rootObjective: child,
                            student: student,
                            allObjectives: allObjectives,
                            startIndentLevel: 1
                        )
                    }
                }
                .padding(.leading, zoomManager.scaled(28))
                .padding(.top, zoomManager.scaled(8))
                .padding(.bottom, zoomManager.scaled(12))
            }
        }
        .sheet(item: $editingTarget) { target in
            EditCategoryTitleSheet(
                code: target.code,
                fallbackTitle: target.fallbackTitle
            )
        }
    }

    private func categoryDisplayTitle(for objective: LearningObjective) -> String {
        let canonical = objective.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if canonical.isEmpty, let label = categoryLabels.first(where: { $0.key == objective.code }) {
            return label.title
        }
        return canonical.isEmpty ? objective.code : objective.title
    }

    private func objectivePercentage(forCode code: String) -> Int {
        guard let objective = allObjectives.first(where: { $0.code == code }) else {
            return student.completionPercentage(for: code)
        }
        return student.completionPercentage(for: objective)
    }

    private struct CategoryEditTarget: Identifiable {
        let id: String
        let code: String
        let fallbackTitle: String

        init(code: String, fallbackTitle: String) {
            self.id = code
            self.code = code
            self.fallbackTitle = fallbackTitle
        }
    }
}
