import SwiftUI

struct AddStudentSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""

    let onAdd: (String) -> Void

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
            }
            .formStyle(.grouped)

            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }

                Button("Add") {
                    onAdd(trimmedName)
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