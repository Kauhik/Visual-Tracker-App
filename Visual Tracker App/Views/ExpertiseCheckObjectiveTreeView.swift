import SwiftUI

struct ExpertiseCheckObjectiveTreeView: View {
    let rootObjective: LearningObjective
    let expertiseCheck: Domain
    let students: [Student]
    let startIndentLevel: Int

    @EnvironmentObject private var store: CloudKitStore
    @Environment(ZoomManager.self) private var zoomManager

    private var childObjectives: [LearningObjective] {
        store.childObjectives(of: rootObjective)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: zoomManager.scaled(2)) {
            ExpertiseCheckObjectiveRowView(
                objective: rootObjective,
                expertiseCheck: expertiseCheck,
                students: students,
                indentLevel: startIndentLevel
            )

            ForEach(childObjectives, id: \.id) { child in
                ExpertiseCheckObjectiveTreeView(
                    rootObjective: child,
                    expertiseCheck: expertiseCheck,
                    students: students,
                    startIndentLevel: startIndentLevel + 1
                )
            }
        }
    }
}
