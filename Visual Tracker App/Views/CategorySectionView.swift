import SwiftUI

struct CategorySectionView: View {
    let categoryObjective: LearningObjective
    let context: ObjectiveProgressEditingContext
    let allObjectives: [LearningObjective]

    @EnvironmentObject private var store: CloudKitStore
    @Environment(ZoomManager.self) private var zoomManager

    private var categoryLabels: [CategoryLabel] { store.categoryLabels }

    @State private var isExpanded: Bool = true
    @State private var isHeaderHovering: Bool = false
    @State private var showingHeaderEditor: Bool = false

    private var childObjectives: [LearningObjective] {
        store.childObjectives(of: categoryObjective)
    }

    private var aggregatePercentage: Int {
        switch context {
        case .student(let student):
            return store.objectivePercentage(student: student, objective: categoryObjective)
        case .expertiseCheck(let domain):
            return store.expertiseCheckObjectivePercentage(domain: domain, objective: categoryObjective)
        }
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

                        if isEditableAtCategoryLevel {
                            headerProgressPill
                        }
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
                if isEditableAtCategoryLevel {
                    Divider()
                    Button("Set 0%") { updateCategoryProgress(0) }
                    Button("Set 25%") { updateCategoryProgress(25) }
                    Button("Set 50%") { updateCategoryProgress(50) }
                    Button("Set 75%") { updateCategoryProgress(75) }
                    Button("Set 100%") { updateCategoryProgress(100) }
                    Divider()
                    Button("Custom...") { showingHeaderEditor = true }
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
                            context: context,
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
    }

    private func categoryDisplayTitle(for objective: LearningObjective) -> String {
        let canonical = objective.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if canonical.isEmpty, let label = categoryLabels.first(where: { $0.key == objective.code }) {
            return label.title
        }
        return canonical.isEmpty ? objective.code : objective.title
    }

    private func objectivePercentage(forCode code: String) -> Int {
        guard let objective = store.objective(forCode: code) else {
            switch context {
            case .student(let student):
                return student.completionPercentage(for: code)
            case .expertiseCheck:
                return 0
            }
        }
        switch context {
        case .student(let student):
            return store.objectivePercentage(student: student, objective: objective)
        case .expertiseCheck(let domain):
            return store.expertiseCheckObjectivePercentage(domain: domain, objective: objective)
        }
    }

    private var isEditableAtCategoryLevel: Bool {
        guard childObjectives.isEmpty else { return false }
        if case .expertiseCheck = context {
            return true
        }
        return false
    }

    @ViewBuilder
    private var headerProgressPill: some View {
        Button {
            showingHeaderEditor = true
        } label: {
            HStack(spacing: zoomManager.scaled(4)) {
                Text(aggregateStatus.rawValue)
                    .font(.caption2)
                    .fontWeight(.semibold)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
            }
            .padding(.horizontal, zoomManager.scaled(8))
            .padding(.vertical, zoomManager.scaled(4))
            .background(Capsule().fill(Color.accentColor.opacity(0.12)))
            .overlay(Capsule().stroke(Color.accentColor.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingHeaderEditor, arrowEdge: .trailing) {
            ProgressEditorView(
                title: categoryObjective.code,
                currentValue: aggregatePercentage,
                onSave: { newValue in
                    updateCategoryProgress(newValue)
                }
            )
        }
    }

    private func updateCategoryProgress(_ newPercentage: Int) {
        guard case .expertiseCheck(let domain) = context else { return }
        Task {
            await store.setExpertiseCheckCriteriaProgress(domain: domain, objective: categoryObjective, value: newPercentage)
        }
    }
}
