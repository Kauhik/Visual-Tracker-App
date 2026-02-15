import SwiftUI

struct ManageSheetsSheet: View {
    @EnvironmentObject private var store: CloudKitStore
    @Environment(\.dismiss) private var dismiss

    @State private var newSheetName: String = ""
    @State private var renamingSheet: CohortSheet?
    @State private var renameText: String = ""
    @State private var sheetPendingDelete: CohortSheet?

    private var isBusy: Bool {
        store.isLoading || store.isSheetMutationInProgress
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Manage Sheets")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button("Done") { dismiss() }
            }

            HStack {
                TextField("New sheet name", text: $newSheetName)
                    .disabled(isBusy)
                Button("Create") {
                    let name = newSheetName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard name.isEmpty == false else { return }
                    Task {
                        await store.createSheet(name: name)
                        await MainActor.run { newSheetName = "" }
                    }
                }
                .disabled(isBusy || newSheetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            List {
                ForEach(store.sheets) { sheet in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(sheet.name)
                            Text(sheet.cohortId)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if store.activeSheet?.id == sheet.id {
                            Text("Active")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.accentColor.opacity(0.15))
                                .clipShape(Capsule())
                        }
                        Button("Switch") {
                            Task { await store.switchSheet(to: sheet) }
                        }
                        .disabled(isBusy || store.activeSheet?.id == sheet.id)
                        Button("Rename") {
                            renamingSheet = sheet
                            renameText = sheet.name
                        }
                        .disabled(isBusy)
                        Button("Delete", role: .destructive) {
                            sheetPendingDelete = sheet
                        }
                        .disabled(isBusy || store.activeSheet?.id == sheet.id || sheet.cohortId == "main")
                    }
                }
            }
        }
        .padding(16)
        .frame(minWidth: 560, minHeight: 420)
        .task { await store.loadSheets() }
        .alert(
            "Delete Sheet?",
            isPresented: Binding(
                get: { sheetPendingDelete != nil },
                set: { if $0 == false { sheetPendingDelete = nil } }
            )
        ) {
            Button("Delete", role: .destructive) {
                guard let sheet = sheetPendingDelete else { return }
                Task { await store.deleteSheet(sheet: sheet) }
                sheetPendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                sheetPendingDelete = nil
            }
        } message: {
            if let sheet = sheetPendingDelete {
                Text(
                    "Delete '\(sheet.name)'? This permanently deletes all data in this sheet, including students, groups, expertise checks, success criteria, milestones, and progress."
                )
            }
        }
        .sheet(item: $renamingSheet) { sheet in
            VStack(alignment: .leading, spacing: 12) {
                Text("Rename Sheet")
                    .font(.headline)
                TextField("Name", text: $renameText)
                    .disabled(isBusy)
                HStack {
                    Spacer()
                    Button("Cancel") { renamingSheet = nil }
                        .disabled(isBusy)
                    Button("Save") {
                        Task {
                            await store.renameSheet(sheet: sheet, name: renameText)
                            await MainActor.run { renamingSheet = nil }
                        }
                    }
                    .disabled(isBusy || renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(16)
            .frame(minWidth: 360)
        }
    }
}
