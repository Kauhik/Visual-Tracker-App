import SwiftUI

struct ManageDomainsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: CloudKitStore

    private var domains: [Domain] { store.domains }
    private var students: [Student] { store.students }
    private var allObjectives: [LearningObjective] { store.learningObjectives }

    @State private var newDomainName: String = ""
    @State private var newDomainColor: DomainColorPreset = .none

    @State private var showingRenameSheet: Bool = false
    @State private var domainPendingRename: Domain?

    @State private var domainPendingDelete: Domain?

    @State private var showingError: Bool = false
    @State private var errorMessage: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Manage Domains")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            addDomainRow

            Divider()
                .opacity(0.25)

            if domains.isEmpty {
                ContentUnavailableView(
                    "No Domains",
                    systemImage: "tag",
                    description: Text("Create a domain to classify students.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(domains) { domain in
                        domainRow(domain)
                            .contextMenu {
                                Button("Rename") {
                                    domainPendingRename = domain
                                    showingRenameSheet = true
                                }

                                Divider()

                                Button("Delete", role: .destructive) {
                                    domainPendingDelete = domain
                                }
                            }
                    }
                }
                .listStyle(.inset)
            }
        }
        .padding(20)
        .frame(width: 560, height: 440)
        .sheet(isPresented: $showingRenameSheet) {
            if let domain = domainPendingRename {
                RenameDomainSheet(domain: domain)
            }
        }
        .confirmationDialog(
            "Delete Domain",
            isPresented: Binding(
                get: { domainPendingDelete != nil },
                set: { if $0 == false { domainPendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let domain = domainPendingDelete {
                    deleteDomain(domain)
                }
                domainPendingDelete = nil
            }

            Button("Cancel", role: .cancel) {
                domainPendingDelete = nil
            }
        } message: {
            if let domain = domainPendingDelete {
                let count = students.filter { $0.domain?.id == domain.id }.count
                Text("\(count) student\(count == 1 ? "" : "s") will become No Domain.")
            }
        }
        .alert("Action Failed", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    private var addDomainRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Create Domain")
                .font(.headline)

            HStack(spacing: 10) {
                TextField("Domain Name", text: $newDomainName)

                Picker("Colour", selection: $newDomainColor) {
                    ForEach(DomainColorPreset.allCases, id: \.self) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .frame(width: 160)

                Button("Add") { addDomain() }
                    .buttonStyle(.borderedProminent)
                    .disabled(newDomainName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func domainRow(_ domain: Domain) -> some View {
        let count = students.filter { $0.domain?.id == domain.id }.count
        let average = domainAverage(domain: domain)
        let badgeColor = Color(hex: domain.colorHex) ?? Color.secondary.opacity(0.35)

        return HStack(spacing: 12) {
            Circle()
                .fill(badgeColor)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(domain.name)
                    .font(.body)

                Text("\(count) student\(count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(average)%")
                    .font(.system(.callout, design: .rounded))
                    .fontWeight(.semibold)

                Text("Domain average")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func addDomain() {
        let trimmed = newDomainName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }

        let collision = domains.contains { existing in
            existing.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == trimmed.lowercased()
        }
        if collision {
            errorMessage = "A domain with that name already exists."
            showingError = true
            return
        }

        Task {
            await store.addDomain(name: trimmed, colorHex: newDomainColor.hexValue)
            if let error = store.lastErrorMessage {
                errorMessage = error
                showingError = true
            } else {
                newDomainName = ""
                newDomainColor = .none
            }
        }
    }

    private func deleteDomain(_ domain: Domain) {
        Task {
            await store.deleteDomain(domain)
            if let error = store.lastErrorMessage {
                errorMessage = error
                showingError = true
            }
        }
    }

    private func domainAverage(domain: Domain) -> Int {
        let domainStudents = students.filter { $0.domain?.id == domain.id }
        guard domainStudents.isEmpty == false else { return 0 }
        return ProgressCalculator.cohortOverall(students: domainStudents, allObjectives: allObjectives)
    }
}

private enum DomainColorPreset: CaseIterable, Hashable {
    case none
    case blue
    case green
    case orange
    case purple
    case pink
    case gray

    var title: String {
        switch self {
        case .none: return "Default"
        case .blue: return "Blue"
        case .green: return "Green"
        case .orange: return "Orange"
        case .purple: return "Purple"
        case .pink: return "Pink"
        case .gray: return "Gray"
        }
    }

    var hexValue: String? {
        switch self {
        case .none: return nil
        case .blue: return "#3B82F6"
        case .green: return "#10B981"
        case .orange: return "#F97316"
        case .purple: return "#8B5CF6"
        case .pink: return "#EC4899"
        case .gray: return "#6B7280"
        }
    }
}
