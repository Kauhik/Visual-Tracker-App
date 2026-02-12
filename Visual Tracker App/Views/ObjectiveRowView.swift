import SwiftUI

struct ObjectiveRowView: View {
    let objective: LearningObjective
    let context: ObjectiveProgressEditingContext
    let allObjectives: [LearningObjective]
    let indentLevel: Int

    @EnvironmentObject private var store: CloudKitStore
    @Environment(ZoomManager.self) private var zoomManager
    @State private var showingEditor: Bool = false
    @State private var isHovering: Bool = false

    private var hasChildren: Bool {
        childObjectives.isEmpty == false
    }

    private var childObjectives: [LearningObjective] {
        store.childObjectives(of: objective)
    }

    private var leafPercentage: Int {
        switch context {
        case .student(let student):
            return store.progressValue(student: student, objective: objective)
        case .expertiseCheck(let domain):
            return store.criteriaProgressValue(domain: domain, objective: objective)
        }
    }

    private var completionPercentage: Int {
        if hasChildren == false {
            return leafPercentage
        }
        switch context {
        case .student(let student):
            return store.objectivePercentage(student: student, objective: objective)
        case .expertiseCheck(let domain):
            return store.expertiseCheckObjectivePercentage(domain: domain, objective: objective)
        }
    }

    private var status: ProgressStatus {
        ObjectiveProgress.calculateStatus(from: completionPercentage)
    }

    private var statusColor: Color {
        switch status {
        case .notStarted:
            return .gray
        case .inProgress:
            return .orange
        case .complete:
            return .green
        }
    }

    private var indentString: String {
        if indentLevel == 0 { return "" }
        var indent = ""
        for i in 0..<indentLevel {
            if i == indentLevel - 1 {
                indent += "|--- "
            } else {
                indent += "|    "
            }
        }
        return indent
    }

    var body: some View {
        HStack(spacing: zoomManager.scaled(10)) {
            if indentLevel > 0 {
                Text(indentString)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Text(objective.code)
                .font(.system(.body, design: .monospaced))
                .fontWeight(.semibold)
                .foregroundColor(.primary)
                .frame(minWidth: zoomManager.scaled(54), alignment: .leading)

            Text(objective.title)
                .font(.body)
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(objective.title)
                .layoutPriority(1)

            Spacer()

            Text(status.indicator)
                .font(.title3)

            if objective.isQuantitative || hasChildren {
                Text("\(completionPercentage)%")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(minWidth: zoomManager.scaled(48), alignment: .trailing)
            }

            if hasChildren == false {
                progressPill
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, zoomManager.scaled(6))
        .padding(.horizontal, zoomManager.scaled(10))
        .background(
            RoundedRectangle(cornerRadius: zoomManager.scaled(8))
                .fill(backgroundFillColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: zoomManager.scaled(8))
                .stroke(Color.primary.opacity(indentLevel == 0 ? 0.08 : 0.0), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
        .contextMenu {
            if hasChildren == false {
                Button("Set 0%") { updateProgress(0) }
                Button("Set 25%") { updateProgress(25) }
                Button("Set 50%") { updateProgress(50) }
                Button("Set 75%") { updateProgress(75) }
                Button("Set 100%") { updateProgress(100) }
                Divider()
                Button("Custom...") { showingEditor = true }
            }
        }
    }

    private var progressPill: some View {
        Button {
            showingEditor = true
        } label: {
            HStack(spacing: zoomManager.scaled(6)) {
                Text(status.rawValue)
                    .font(.caption)
                    .fontWeight(.semibold)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .opacity(0.9)
            }
            .padding(.horizontal, zoomManager.scaled(10))
            .padding(.vertical, zoomManager.scaled(6))
            .background(
                Capsule()
                    .fill(statusColor.opacity(0.16))
            )
            .overlay(
                Capsule()
                    .stroke(statusColor.opacity(0.55), lineWidth: 1)
            )
            .foregroundColor(statusColor)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingEditor, arrowEdge: .trailing) {
            ProgressEditorView(
                title: objective.code,
                currentValue: leafPercentage,
                onSave: { newValue in
                    updateProgress(newValue)
                }
            )
        }
        .help("Edit progress")
    }

    private var backgroundFillColor: Color {
        if indentLevel == 0 {
            return Color.accentColor.opacity(isHovering ? 0.16 : 0.10)
        }
        return isHovering ? Color.primary.opacity(0.08) : Color.clear
    }

    private func updateProgress(_ newPercentage: Int) {
        Task {
            switch context {
            case .student(let student):
                await store.setProgress(student: student, objective: objective, value: newPercentage)
            case .expertiseCheck(let domain):
                await store.setExpertiseCheckCriteriaProgress(domain: domain, objective: objective, value: newPercentage)
            }
        }
    }
}
