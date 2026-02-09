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

    private var childObjectives: [LearningObjective] {
        allObjectives
            .filter { $0.parentCode == categoryObjective.code }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private var aggregatePercentage: Int {
        calculateCategoryPercentage(for: categoryObjective)
    }

    private func calculateCategoryPercentage(for objective: LearningObjective) -> Int {
        let children = allObjectives.filter { $0.parentCode == objective.code }
        if children.isEmpty {
            return student.completionPercentage(for: objective.code)
        }

        var total = 0
        for child in children {
            total += calculateCategoryPercentage(for: child)
        }
        return children.count > 0 ? total / children.count : 0
    }

    private var aggregateStatus: ProgressStatus {
        ObjectiveProgress.calculateStatus(from: aggregatePercentage)
    }

    private var categoryColor: Color {
        switch categoryObjective.code {
        case "A": return .blue
        case "B": return .green
        case "C": return .orange
        case "D": return .purple
        case "E": return .pink
        default: return .gray
        }
    }

    private var formulaDisplay: String? {
        if categoryObjective.code == "A" {
            let a1 = student.completionPercentage(for: "A.1")
            let a2 = student.completionPercentage(for: "A.2")
            let a3 = student.completionPercentage(for: "A.3")
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

                    Text(categoryObjective.code)
                        .font(.system(.headline, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, zoomManager.scaled(10))
                        .padding(.vertical, zoomManager.scaled(4))
                        .background(
                            RoundedRectangle(cornerRadius: zoomManager.scaled(6))
                                .fill(categoryColor)
                        )

                    Text(categoryDisplayTitle(for: categoryObjective))
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(categoryDisplayTitle(for: categoryObjective))
                        .layoutPriority(1)
                        .contextMenu {
                            Button("Edit Title...") {
                                editingTarget = CategoryEditTarget(
                                    code: categoryObjective.code,
                                    fallbackTitle: categoryObjective.title
                                )
                            }
                        }

                    Spacer()

                    HStack(spacing: zoomManager.scaled(8)) {
                        Text(aggregateStatus.indicator)
                            .font(.title2)

                        Text("\(aggregatePercentage)%")
                            .font(.system(.headline, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, zoomManager.scaled(12))
                .padding(.horizontal, zoomManager.scaled(16))
                .background(
                    RoundedRectangle(cornerRadius: zoomManager.scaled(10))
                        .fill(categoryColor.opacity(0.1))
                )
            }
            .buttonStyle(.plain)

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
        if let label = categoryLabels.first(where: { $0.key == objective.code }) {
            return label.title
        }
        return objective.title
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
