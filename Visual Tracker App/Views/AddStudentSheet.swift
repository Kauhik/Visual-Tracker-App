import SwiftUI
import SwiftData

struct CustomPropertyRow: Identifiable {
    let id: UUID
    var key: String
    var value: String

    init(id: UUID = UUID(), key: String = "", value: String = "") {
        self.id = id
        self.key = key
        self.value = value
    }
}

struct AddStudentSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \CohortGroup.name) private var groups: [CohortGroup]
    @Query(sort: \Domain.name) private var domains: [Domain]

    @State private var name: String = ""
    @State private var selectedGroup: CohortGroup? = nil
    @State private var selectedSession: Session = .morning
    @State private var selectedDomain: Domain? = nil
    @State private var customPropertyRows: [CustomPropertyRow] = []

    @State private var showingValidationError: Bool = false
    @State private var validationErrorMessage: String = ""

    let studentToEdit: Student?
    let onSave: (String, CohortGroup?, Session, Domain?, [CustomPropertyRow]) -> Void

    init(studentToEdit: Student? = nil, onSave: @escaping (String, CohortGroup?, Session, Domain?, [CustomPropertyRow]) -> Void) {
        self.studentToEdit = studentToEdit
        self.onSave = onSave
    }

    private var isEditMode: Bool {
        studentToEdit != nil
    }

    private var sheetTitle: String {
        isEditMode ? "Edit Student" : "Add Student"
    }

    private var saveButtonTitle: String {
        isEditMode ? "Save" : "Add"
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var customPropertyKeysValid: Bool {
        let keys = customPropertyRows.map { $0.key.trimmingCharacters(in: .whitespacesAndNewlines) }
        let nonEmptyKeys = keys.filter { !$0.isEmpty }

        if customPropertyRows.isEmpty {
            return true
        }

        for row in customPropertyRows {
            let trimmedKey = row.key.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedValue = row.value.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedKey.isEmpty && !trimmedValue.isEmpty {
                return false
            }
        }

        return nonEmptyKeys.count == Set(nonEmptyKeys).count
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && customPropertyKeysValid
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(sheetTitle)
                .font(.title2)
                .fontWeight(.semibold)

            Form {
                Section {
                    TextField("Student Name", text: $name)
                }

                Section {
                    Picker("Group", selection: $selectedGroup) {
                        Text("Ungrouped").tag(nil as CohortGroup?)
                        if groups.isEmpty == false {
                            Divider()
                            ForEach(groups) { group in
                                Text(group.name).tag(group as CohortGroup?)
                            }
                        }
                    }

                    Picker("Session", selection: $selectedSession) {
                        ForEach(Session.allCases, id: \.self) { session in
                            Text(session.rawValue).tag(session)
                        }
                    }

                    Picker("Domain", selection: $selectedDomain) {
                        Text("No Domain").tag(nil as Domain?)
                        if domains.isEmpty == false {
                            Divider()
                            ForEach(domains) { domain in
                                Text(domain.name).tag(domain as Domain?)
                            }
                        }
                    }
                }

                Section {
                    if customPropertyRows.isEmpty {
                        Text("No custom properties")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach($customPropertyRows) { $row in
                            HStack(spacing: 8) {
                                TextField("Key", text: $row.key)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: 140)

                                TextField("Value", text: $row.value)
                                    .textFieldStyle(.roundedBorder)

                                Button {
                                    removeProperty(row)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Button {
                        addProperty()
                    } label: {
                        Label("Add Property", systemImage: "plus.circle")
                    }
                } header: {
                    Text("Custom Properties")
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }

                Button(saveButtonTitle) {
                    if validateAndSave() {
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 480, height: 520)
        .alert("Validation Error", isPresented: $showingValidationError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(validationErrorMessage)
        }
        .onAppear {
            if let student = studentToEdit {
                name = student.name
                selectedGroup = student.group
                selectedSession = student.session
                selectedDomain = student.domain
                customPropertyRows = student.customProperties
                    .sorted { $0.sortOrder < $1.sortOrder }
                    .map { CustomPropertyRow(id: $0.id, key: $0.key, value: $0.value) }
            }
        }
    }

    private func addProperty() {
        customPropertyRows.append(CustomPropertyRow())
    }

    private func removeProperty(_ row: CustomPropertyRow) {
        customPropertyRows.removeAll { $0.id == row.id }
    }

    private func validateAndSave() -> Bool {
        guard !trimmedName.isEmpty else {
            validationErrorMessage = "Student name cannot be empty."
            showingValidationError = true
            return false
        }

        let keys = customPropertyRows
            .map { $0.key.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if keys.count != Set(keys).count {
            validationErrorMessage = "Custom property keys must be unique."
            showingValidationError = true
            return false
        }

        for row in customPropertyRows {
            let trimmedKey = row.key.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedValue = row.value.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedKey.isEmpty && !trimmedValue.isEmpty {
                validationErrorMessage = "Custom property keys cannot be empty if a value is provided."
                showingValidationError = true
                return false
            }
        }

        let validRows = customPropertyRows.filter { row in
            let trimmedKey = row.key.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmedKey.isEmpty
        }

        onSave(trimmedName, selectedGroup, selectedSession, selectedDomain, validRows)
        return true
    }
}
