import SwiftUI
import SwiftData

struct AddStudentSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \CohortGroup.name) private var groups: [CohortGroup]

    @State private var name: String = ""
    @State private var selectedGroup: CohortGroup? = nil

    let onAdd: (String, CohortGroup?) -> Void

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Student")
                .font(.title2)
                .fontWeight(.semibold)

            Form {
                TextField("Student Name", text: $name)

                Picker("Group", selection: $selectedGroup) {
                    Text("Ungrouped").tag(nil as CohortGroup?)
                    if groups.isEmpty == false {
                        Divider()
                        ForEach(groups) { group in
                            Text(group.name).tag(group as CohortGroup?)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }

                Button("Add") {
                    onAdd(trimmedName, selectedGroup)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedName.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
