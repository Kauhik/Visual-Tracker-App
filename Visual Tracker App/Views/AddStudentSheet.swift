import SwiftUI

struct AddStudentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: CloudKitStore
    @Environment(ZoomManager.self) private var zoomManager

    private var groups: [CohortGroup] { store.groups }
    private var domains: [Domain] { store.domains }

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
        VStack(alignment: .leading, spacing: zoomManager.scaled(16)) {
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
                            HStack(spacing: zoomManager.scaled(8)) {
                                TextField("Key", text: $row.key)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: zoomManager.scaled(140))

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
        .padding(zoomManager.scaled(20))
        .frame(width: zoomManager.scaled(480), height: zoomManager.scaled(520))
        .alert("Validation Error", isPresented: $showingValidationError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(validationErrorMessage)
        }
        .task {
            if let student = studentToEdit {
                await store.loadCustomPropertiesIfNeeded(for: student)
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
