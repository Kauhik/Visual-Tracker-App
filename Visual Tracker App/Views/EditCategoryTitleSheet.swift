import SwiftUI
import SwiftData

struct EditCategoryTitleSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let code: String
    let fallbackTitle: String

    @State private var titleText: String = ""
    @State private var showingError: Bool = false
    @State private var errorMessage: String = ""

    @State private var loadedLabel: CategoryLabel?

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
            loadOrCreateLabelIfNeeded()
        }
    }

    private func loadOrCreateLabelIfNeeded() {
        do {
            let descriptor = FetchDescriptor<CategoryLabel>(
                predicate: #Predicate { $0.key == code }
            )
            let existing = try modelContext.fetch(descriptor).first
            if let existing {
                loadedLabel = existing
                titleText = existing.title
            } else {
                let created = CategoryLabel(code: code, title: fallbackTitle)
                modelContext.insert(created)
                try modelContext.save()
                loadedLabel = created
                titleText = created.title
            }
        } catch {
            loadedLabel = nil
            titleText = fallbackTitle
        }
    }

    private func save() {
        let newValue = trimmedTitle
        guard newValue.isEmpty == false else {
            errorMessage = "Title cannot be empty."
            showingError = true
            return
        }

        if loadedLabel == nil {
            let created = CategoryLabel(code: code, title: newValue)
            modelContext.insert(created)
            loadedLabel = created
        } else {
            loadedLabel?.title = newValue
        }

        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = "Failed to save title: \(error)"
            showingError = true
        }
    }
}