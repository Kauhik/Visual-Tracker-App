import SwiftUI

struct RenameGroupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: CloudKitStore
    @Environment(ZoomManager.self) private var zoomManager

    let group: CohortGroup

    @State private var name: String = ""

    private var trimmed: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: zoomManager.scaled(16)) {
            Text("Rename Group")
                .font(.title2)
                .fontWeight(.semibold)

            Form {
                TextField("Group Name", text: $name)
            }
            .formStyle(.grouped)

            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }

                Button("Save") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmed.isEmpty)
            }
        }
        .padding(zoomManager.scaled(20))
        .frame(width: zoomManager.scaled(420))
        .onAppear {
            name = group.name
        }
    }

    private func save() {
        let value = trimmed
        guard value.isEmpty == false else { return }
        Task {
            await store.renameGroup(group, newName: value)
            dismiss()
        }
    }
}
