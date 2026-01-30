import SwiftUI

struct EditCategoryTitleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: CloudKitStore

    let code: String
    let fallbackTitle: String

    @State private var titleText: String = ""
    @State private var showingError: Bool = false
    @State private var errorMessage: String = ""

    private var trimmedTitle: String {
        titleText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Category Title")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Category \(code)")
                .font(.caption)
                .foregroundColor(.secondary)

            Form {
                TextField("Title", text: $titleText)
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
                .disabled(trimmedTitle.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 520)
        .alert("Save Failed", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            if let label = store.categoryLabels.first(where: { $0.key == code }) {
                titleText = label.title
            } else {
                titleText = fallbackTitle
            }
        }
    }

    private func save() {
        let newValue = trimmedTitle
        guard newValue.isEmpty == false else {
            errorMessage = "Title cannot be empty."
            showingError = true
            return
        }
        Task {
            await store.updateCategoryLabel(code: code, title: newValue)
            dismiss()
        }
    }
}
