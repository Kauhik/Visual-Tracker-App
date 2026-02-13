import SwiftUI

struct ExpertiseCheckObjectiveRowView: View {
    let objective: LearningObjective
    let expertiseCheck: Domain
    let students: [Student]
    let indentLevel: Int

    @EnvironmentObject private var store: CloudKitStore
    @Environment(ZoomManager.self) private var zoomManager
    @State private var showingEditor: Bool = false
    @State private var isHovering: Bool = false

    private var childObjectives: [LearningObjective] {
        store.childObjectives(of: objective)
    }

    private var hasChildren: Bool {
        childObjectives.isEmpty == false
    }

    private var isReviewMode: Bool {
        expertiseCheck.overallMode == .expertReview
    }

    private var leafPercentage: Int {
        if isReviewMode {
            return store.expertiseCheckReviewLeafValue(domain: expertiseCheck, objective: objective)
        }
        return store.cohortObjectiveAverage(objective: objective, students: students)
    }

    private var completionPercentage: Int {
        if isReviewMode {
            return store.expertiseCheckReviewerObjectivePercentage(domain: expertiseCheck, objective: objective)
        }
        return store.cohortObjectiveAverage(objective: objective, students: students)
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

            Text("\(completionPercentage)%")
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(minWidth: zoomManager.scaled(48), alignment: .trailing)

            if hasChildren == false {
                if isReviewMode {
                    progressPill
                } else {
                    Text("Computed")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, zoomManager.scaled(10))
                        .padding(.vertical, zoomManager.scaled(6))
                        .background(
                            Capsule()
                                .fill(Color.secondary.opacity(0.14))
                        )
                        .foregroundColor(.secondary)
                }
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
            if hasChildren == false, isReviewMode {
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
        .help("Edit expert review score")
    }

    private var backgroundFillColor: Color {
        if indentLevel == 0 {
            return Color.accentColor.opacity(isHovering ? 0.16 : 0.10)
        }
        return isHovering ? Color.primary.opacity(0.08) : Color.clear
    }

    private func updateProgress(_ newPercentage: Int) {
        Task {
            await store.setExpertiseCheckReviewScore(domain: expertiseCheck, objective: objective, value: newPercentage)
        }
    }
}
