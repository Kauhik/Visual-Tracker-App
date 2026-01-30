import SwiftUI

struct RenameDomainSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: CloudKitStore

    let domain: Domain

    @State private var name: String = ""
    @State private var showingError: Bool = false
    @State private var errorMessage: String = ""

    private var trimmed: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename Domain")
                .font(.title2)
                .fontWeight(.semibold)

            Form {
                TextField("Domain Name", text: $name)
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
        .alert("Rename Failed", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            name = domain.name
        }
    }

    private func save() {
        let value = trimmed
        guard value.isEmpty == false else { return }
        let collision = store.domains.contains { other in
            other.id != domain.id &&
            other.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == value.lowercased()
        }

        if collision {
            errorMessage = "A domain with that name already exists."
            showingError = true
            return
        }

        Task {
            await store.renameDomain(domain, newName: value)
            dismiss()
        }
    }
}
