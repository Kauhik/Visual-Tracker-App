import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct ManageStudentsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ZoomManager.self) private var zoomManager

    let onAddSingle: (String, [CohortGroup], Session, Domain?, [CustomPropertyRow]) -> Void

    @State private var showingAddSingleSheet: Bool = false
    @State private var showingCSVImportSheet: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: zoomManager.scaled(16)) {
            HStack {
                Text("Manage Students")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            Text("Choose how you want to add students to your cohort.")
                .font(.callout)
                .foregroundColor(.secondary)

            VStack(spacing: zoomManager.scaled(12)) {
                optionRow(
                    title: "Add Single Student",
                    subtitle: "Use the existing add-student form",
                    systemImage: "person.badge.plus",
                    action: { showingAddSingleSheet = true }
                )

                optionRow(
                    title: "Mass Import (CSV)",
                    subtitle: "Import many students from a CSV file",
                    systemImage: "tray.and.arrow.down",
                    action: { showingCSVImportSheet = true }
                )
            }

            Spacer()
        }
        .padding(zoomManager.scaled(20))
        .frame(width: zoomManager.scaled(520), height: zoomManager.scaled(360))
        .sheet(isPresented: $showingAddSingleSheet) {
            AddStudentSheet { name, groups, session, domain, customProperties in
                onAddSingle(name, groups, session, domain, customProperties)
            }
        }
        .sheet(isPresented: $showingCSVImportSheet) {
            StudentCSVImportSheet()
        }
    }

    private func optionRow(
        title: String,
        subtitle: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: zoomManager.scaled(12)) {
                Image(systemName: systemImage)
                    .font(zoomManager.scaledFont(size: 20, weight: .semibold))
                    .foregroundColor(.accentColor)
                    .frame(width: zoomManager.scaled(36), height: zoomManager.scaled(36))
                    .background(
                        RoundedRectangle(cornerRadius: zoomManager.scaled(10))
                            .fill(Color.accentColor.opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: zoomManager.scaled(2)) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(zoomManager.scaled(12))
            .background(
                RoundedRectangle(cornerRadius: zoomManager.scaled(12))
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: zoomManager.scaled(12))
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct StudentCSVImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: CloudKitStore
    @Environment(ZoomManager.self) private var zoomManager

    @State private var showingFileImporter: Bool = false
    @State private var isDropTargeted: Bool = false

    @State private var selectedFileName: String = ""
    @State private var previewRows: [CSVImportPreviewRow] = []
    @State private var importCandidates: [CSVImportCandidate] = []

    @State private var totalRows: Int = 0
    @State private var validRows: Int = 0
    @State private var skippedRows: Int = 0

    @State private var errorMessage: String?
    @State private var isImporting: Bool = false

    @State private var processedCount: Int = 0
    @State private var importedCount: Int = 0
    @State private var failedCount: Int = 0

    @State private var showingSummary: Bool = false
    @State private var summaryMessage: String = ""

    private var previewColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: zoomManager.scaled(180)), alignment: .leading),
            GridItem(.flexible(minimum: zoomManager.scaled(180)), alignment: .leading),
            GridItem(.flexible(minimum: zoomManager.scaled(140)), alignment: .leading)
        ]
    }

    private var hasCandidates: Bool {
        !importCandidates.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Mass Import (CSV)")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Your CSV must include these headers: Full Name, Expertise Check, Learning Session")
                    .font(.callout)
                Text("Only these columns will be used.")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 12) {
                Button("Choose CSV File") {
                    showingFileImporter = true
                }
                .buttonStyle(.bordered)

                if selectedFileName.isEmpty == false {
                    Text(selectedFileName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            dropZone

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            previewSection

            countsSection

            if isImporting {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: Double(processedCount), total: Double(max(importCandidates.count, 1)))
                        .progressViewStyle(.linear)
                    Text("Importing \(importedCount) / \(importCandidates.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            HStack {
                Spacer()

                Button(isImporting ? "Importing..." : "Import Students") {
                    importStudents()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!hasCandidates || isImporting)
            }
        }
        .padding(zoomManager.scaled(20))
        .frame(width: zoomManager.scaled(760), height: zoomManager.scaled(640))
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.commaSeparatedText, .plainText],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                handleCSVSelection(url)
            case .failure(let error):
                errorMessage = "Failed to select file: \(error.localizedDescription)"
            }
        }
        .task {
            await store.ensurePresetDomains()
        }
        .alert("Import Complete", isPresented: $showingSummary) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(summaryMessage)
        }
    }

    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: zoomManager.scaled(14))
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: zoomManager.scaled(14))
                        .stroke(
                            isDropTargeted ? Color.accentColor : Color.primary.opacity(0.12),
                            style: StrokeStyle(lineWidth: zoomManager.scaled(2), dash: [zoomManager.scaled(6)])
                        )
                )

            VStack(spacing: zoomManager.scaled(8)) {
                Image(systemName: "arrow.down.doc")
                    .font(zoomManager.scaledFont(size: 30, weight: .semibold))
                    .foregroundColor(.accentColor)

                Text("Drag & drop your CSV here")
                    .font(.headline)

                Text("or use the file picker above")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(zoomManager.scaled(12))
        }
        .frame(height: zoomManager.scaled(140))
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            guard let provider = providers.first else { return false }
            let identifier = UTType.fileURL.identifier
            provider.loadItem(forTypeIdentifier: identifier, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                DispatchQueue.main.async {
                    handleCSVSelection(url)
                }
            }
            return true
        }
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: zoomManager.scaled(8)) {
            Text("Preview")
                .font(.headline)

            if previewRows.isEmpty {
                ContentUnavailableView(
                    "No CSV Loaded",
                    systemImage: "doc.text",
                    description: Text("Select a CSV file to preview the first 10 rows.")
                )
                .frame(maxWidth: .infinity, minHeight: zoomManager.scaled(180))
            } else {
                VStack(spacing: zoomManager.scaled(8)) {
                    ScrollView {
                        LazyVGrid(columns: previewColumns, alignment: .leading, spacing: zoomManager.scaled(8)) {
                            Group {
                                Text("Full Name")
                                Text("Expertise Check")
                                Text("Learning Session")
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)

                            ForEach(previewRows.prefix(10)) { row in
                                Text(row.fullName)
                                    .lineLimit(1)
                                Text(row.expertiseCheck)
                                    .lineLimit(1)
                                Text(row.learningSession)
                                    .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: zoomManager.scaled(220))

                    if previewRows.count > 10 {
                        Text("Showing first 10 of \(previewRows.count) rows.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(zoomManager.scaled(12))
                .background(
                    RoundedRectangle(cornerRadius: zoomManager.scaled(12))
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: zoomManager.scaled(12))
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
            }
        }
    }

    private var countsSection: some View {
        VStack(alignment: .leading, spacing: zoomManager.scaled(8)) {
            HStack(spacing: zoomManager.scaled(12)) {
                ImportStatView(title: "Total rows", value: "\(totalRows)")
                ImportStatView(title: "Valid rows", value: "\(validRows)")
                ImportStatView(title: "Skipped rows", value: "\(skippedRows)")
            }

            Text("Rows without a Full Name or duplicate names are skipped.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func handleCSVSelection(_ url: URL) {
        errorMessage = nil
        selectedFileName = url.lastPathComponent

        do {
            let text = try readCSVText(from: url)
            let result = try parseCSV(text)
            apply(result)
        } catch {
            errorMessage = error.localizedDescription
            previewRows = []
            importCandidates = []
            totalRows = 0
            validRows = 0
            skippedRows = 0
            processedCount = 0
            importedCount = 0
            failedCount = 0
        }
    }

    private func readCSVText(from url: URL) throws -> String {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: url)
        return String(decoding: data, as: UTF8.self)
    }

    private func parseCSV(_ text: String) throws -> CSVImportResult {
        let rows = CSVParser.parse(text)
        guard rows.isEmpty == false else {
            throw CSVImportError.emptyFile
        }

        let headers = rows[0]
        let headerLookup = headerMap(from: headers)

        let requiredHeaders = [
            "full name": "Full Name",
            "expertise check": "Expertise Check",
            "learning session": "Learning Session"
        ]

        let missing = requiredHeaders.compactMap { key, displayName in
            headerLookup[key] == nil ? displayName : nil
        }

        if missing.isEmpty == false {
            throw CSVImportError.missingHeaders(missing)
        }

        let nameIndex = headerLookup["full name"]
        let expertiseIndex = headerLookup["expertise check"]
        let sessionIndex = headerLookup["learning session"]

        let rawRows = rows.dropFirst()
        let dataRows = rawRows.filter { row in
            row.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }

        var preview: [CSVImportPreviewRow] = []
        var candidates: [CSVImportCandidate] = []
        var seenNames: Set<String> = []

        for row in dataRows {
            let fullName = value(at: nameIndex, in: row).trimmingCharacters(in: .whitespacesAndNewlines)
            let expertiseRaw = value(at: expertiseIndex, in: row).trimmingCharacters(in: .whitespacesAndNewlines)
            let sessionRaw = value(at: sessionIndex, in: row).trimmingCharacters(in: .whitespacesAndNewlines)
            let expertiseNormalized = normalizedExpertise(expertiseRaw)
            let keyword = domainKeyword(from: expertiseNormalized)

            let normalized = fullName.lowercased()
            let isMissingName = fullName.isEmpty
            let isDuplicate = !normalized.isEmpty && seenNames.contains(normalized)
            let isValid = !isMissingName && !isDuplicate

            preview.append(
                CSVImportPreviewRow(
                    fullName: fullName,
                    expertiseCheck: expertiseRaw,
                    learningSession: sessionRaw,
                    isValid: isValid
                )
            )

            if isValid {
                seenNames.insert(normalized)
                candidates.append(
                    CSVImportCandidate(
                        name: fullName,
                        expertiseRaw: expertiseRaw,
                        domainKeyword: keyword,
                        session: mappedSession(from: sessionRaw)
                    )
                )
            }
        }

        let total = dataRows.count
        let valid = candidates.count
        let skipped = max(0, total - valid)

        return CSVImportResult(
            previewRows: preview,
            candidates: candidates,
            totalRows: total,
            validRows: valid,
            skippedRows: skipped
        )
    }

    private func apply(_ result: CSVImportResult) {
        previewRows = result.previewRows
        importCandidates = result.candidates
        totalRows = result.totalRows
        validRows = result.validRows
        skippedRows = result.skippedRows
        processedCount = 0
        importedCount = 0
        failedCount = 0
    }

    private func mappedSession(from value: String) -> Session {
        let lowercased = value.lowercased()
        if lowercased.contains("afternoon") {
            return .afternoon
        }
        if lowercased.contains("morning") {
            return .morning
        }
        return .morning
    }

    private func headerMap(from headers: [String]) -> [String: Int] {
        var map: [String: Int] = [:]
        for (index, header) in headers.enumerated() {
            var normalized = header.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if normalized.hasPrefix("\u{feff}") {
                normalized = String(normalized.dropFirst())
            }
            map[normalized] = index
        }
        return map
    }

    private func normalizedExpertise(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let parenIndex = trimmed.firstIndex(of: "(") {
            return String(trimmed[..<parenIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    private func domainKeyword(from value: String) -> DomainKeyword? {
        let lowercased = value.lowercased()
        if lowercased.contains("domain expert") {
            return .domainExpert
        }
        if lowercased.contains("tech") {
            return .tech
        }
        if lowercased.contains("design") {
            return .design
        }
        return nil
    }

    private func domainLookup() -> [String: Domain] {
        var map: [String: Domain] = [:]
        for domain in store.domains {
            map[normalizedDomainName(domain.name)] = domain
        }
        return map
    }

    private func normalizedDomainName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func value(at index: Int?, in row: [String]) -> String {
        guard let index, index >= 0, index < row.count else { return "" }
        return row[index]
    }

    private func importStudents() {
        guard importCandidates.isEmpty == false else { return }

        isImporting = true
        processedCount = 0
        importedCount = 0
        failedCount = 0

        Task {
            await store.ensurePresetDomains()
            let domainMap = domainLookup()

            for candidate in importCandidates {
                let customProperties = [
                    CustomPropertyRow(key: "Expertise Check", value: candidate.expertiseRaw)
                ]
                let domain = candidate.domainKeyword
                    .flatMap { domainMap[normalizedDomainName($0.domainName)] }

                let created = await store.addStudent(
                    name: candidate.name,
                    group: nil,
                    session: candidate.session,
                    domain: domain,
                    customProperties: customProperties
                )

                await MainActor.run {
                    processedCount += 1
                    if created != nil {
                        importedCount += 1
                    } else {
                        failedCount += 1
                    }
                }
            }

            let skipped = max(0, totalRows - validRows)

            await MainActor.run {
                isImporting = false
                summaryMessage = "Imported \(importedCount), skipped \(skipped), failed \(failedCount)."
                showingSummary = true
            }
        }
    }
}

private struct ImportStatView: View {
    let title: String
    let value: String
    @Environment(ZoomManager.self) private var zoomManager

    var body: some View {
        VStack(alignment: .leading, spacing: zoomManager.scaled(4)) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)

            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
        }
        .padding(zoomManager.scaled(12))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: zoomManager.scaled(10))
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: zoomManager.scaled(10))
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct CSVImportPreviewRow: Identifiable {
    let id = UUID()
    let fullName: String
    let expertiseCheck: String
    let learningSession: String
    let isValid: Bool
}

private struct CSVImportCandidate: Identifiable {
    let id = UUID()
    let name: String
    let expertiseRaw: String
    let domainKeyword: DomainKeyword?
    let session: Session
}

private struct CSVImportResult {
    let previewRows: [CSVImportPreviewRow]
    let candidates: [CSVImportCandidate]
    let totalRows: Int
    let validRows: Int
    let skippedRows: Int
}

private enum CSVImportError: LocalizedError {
    case emptyFile
    case missingHeaders([String])

    var errorDescription: String? {
        switch self {
        case .emptyFile:
            return "The selected CSV file is empty."
        case .missingHeaders(let headers):
            return "Missing required headers: \(headers.joined(separator: ", "))"
        }
    }
}

private enum DomainKeyword {
    case domainExpert
    case tech
    case design

    var domainName: String {
        switch self {
        case .domainExpert:
            return "Domain Expert"
        case .tech:
            return "Tech"
        case .design:
            return "Design"
        }
    }
}

private enum CSVParser {
    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false

        var index = text.startIndex

        func appendField() {
            row.append(field)
            field = ""
        }

        func appendRow() {
            rows.append(row)
            row = []
        }

        while index < text.endIndex {
            let character = text[index]

            if inQuotes {
                if character == "\"" {
                    let nextIndex = text.index(after: index)
                    if nextIndex < text.endIndex, text[nextIndex] == "\"" {
                        field.append("\"")
                        index = nextIndex
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(character)
                }
            } else {
                switch character {
                case "\"":
                    inQuotes = true
                case ",":
                    appendField()
                case "\n":
                    appendField()
                    appendRow()
                case "\r":
                    appendField()
                    appendRow()
                    let nextIndex = text.index(after: index)
                    if nextIndex < text.endIndex, text[nextIndex] == "\n" {
                        index = nextIndex
                    }
                default:
                    field.append(character)
                }
            }

            index = text.index(after: index)
        }

        if field.isEmpty == false || row.isEmpty == false {
            appendField()
            appendRow()
        }

        if let last = rows.last,
           last.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            rows.removeLast()
        }

        return rows
    }
}
