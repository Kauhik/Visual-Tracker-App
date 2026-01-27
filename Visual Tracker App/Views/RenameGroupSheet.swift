import SwiftUI
import SwiftData

struct RenameGroupSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let group: CohortGroup

    @State private var name: String = ""

    private var trimmed: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
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
        .padding(20)
        .frame(width: 420)
        .onAppear {
            name = group.name
        }
    }

    private func save() {
        let value = trimmed
        guard value.isEmpty == false else { return }

        group.name = value

        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("Failed to rename group: \(error)")
        }
    }
}
