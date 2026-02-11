import Foundation

struct CSVExportPayload {
    let cohortRecordName: String
    let students: [Student]
    let groups: [CohortGroup]
    let memberships: [StudentGroupMembership]
    let domains: [Domain]
    let learningObjectives: [LearningObjective]
    let categoryLabels: [CategoryLabel]

    let studentRecordName: (Student) -> String
    let groupRecordName: (CohortGroup) -> String
    let membershipRecordName: (StudentGroupMembership) -> String
    let domainRecordName: (Domain) -> String
    let learningObjectiveRecordName: (LearningObjective) -> String
    let progressRecordName: (ObjectiveProgress) -> String
    let customPropertyRecordName: (StudentCustomProperty) -> String
}

enum CSVExportError: LocalizedError {
    case zipFailed(String)

    var errorDescription: String? {
        switch self {
        case .zipFailed(let message):
            return "Unable to create ZIP archive: \(message)"
        }
    }
}

struct CSVExportResult {
    let outputURL: URL
    let exportedFiles: [String]
}

struct CSVExportService {
    private let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    func exportZip(payload: CSVExportPayload, destinationURL: URL) throws -> CSVExportResult {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory.appendingPathComponent("visual-tracker-export-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let tempZipURL = fileManager.temporaryDirectory.appendingPathComponent("visual-tracker-export-\(UUID().uuidString).zip")
        defer {
            try? fileManager.removeItem(at: tempRoot)
            try? fileManager.removeItem(at: tempZipURL)
        }

        let tables = makeTables(payload: payload)
        let orderedFileNames = tables.keys.sorted()

        for fileName in orderedFileNames {
            guard let contents = tables[fileName] else { continue }
            let url = tempRoot.appendingPathComponent(fileName)
            try contents.write(to: url, atomically: true, encoding: .utf8)
        }

        let didStartSecurityScope = destinationURL.startAccessingSecurityScopedResource()
        defer {
            if didStartSecurityScope {
                destinationURL.stopAccessingSecurityScopedResource()
            }
        }

        let destinationDirectory = destinationURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        do {
            try zipDirectory(sourceDirectoryURL: tempRoot, destinationURL: tempZipURL)
            try fileManager.copyItem(at: tempZipURL, to: destinationURL)
            return CSVExportResult(outputURL: destinationURL, exportedFiles: orderedFileNames)
        } catch let zipError {
            let fallbackDirectoryURL = fallbackDirectoryURL(for: destinationURL)
            do {
                if fileManager.fileExists(atPath: fallbackDirectoryURL.path) {
                    try fileManager.removeItem(at: fallbackDirectoryURL)
                }
                try fileManager.copyItem(at: tempRoot, to: fallbackDirectoryURL)
                return CSVExportResult(outputURL: fallbackDirectoryURL, exportedFiles: orderedFileNames)
            } catch let fallbackError {
                throw CSVExportError.zipFailed("ZIP failed (\(zipError.localizedDescription)) and folder fallback failed (\(fallbackError.localizedDescription)).")
            }
        }
    }

    private func makeTables(payload: CSVExportPayload) -> [String: String] {
        let roots = payload.learningObjectives
            .filter { $0.isRootCategory }
            .sorted { $0.sortOrder < $1.sortOrder }
        let milestones = payload.learningObjectives
            .filter { $0.isRootCategory == false }
            .sorted { lhs, rhs in
                if lhs.sortOrder == rhs.sortOrder {
                    return lhs.code < rhs.code
                }
                return lhs.sortOrder < rhs.sortOrder
            }

        var customPropertyKeys: [String] = []
        var customPropertySet = Set<String>()
        for student in payload.students {
            let sortedProperties = student.customProperties.sorted { $0.sortOrder < $1.sortOrder }
            for property in sortedProperties where customPropertySet.insert(property.key).inserted {
                customPropertyKeys.append(property.key)
            }
        }

        let studentsHeader = [
            "studentRecordName",
            "studentName",
            "cohortRecordName",
            "legacyGroupRecordName",
            "createdAt",
            "updatedAt",
            "session"
        ] + customPropertyKeys

        let studentsRows = payload.students
            .sorted { $0.createdAt < $1.createdAt }
            .map { student in
                let propertyMap = Dictionary(uniqueKeysWithValues: student.customProperties.map { ($0.key, $0.value) })
                var row: [String] = [
                    payload.studentRecordName(student),
                    student.name,
                    payload.cohortRecordName,
                    student.group.map(payload.groupRecordName) ?? "",
                    format(student.createdAt),
                    "",
                    student.session.rawValue
                ]
                row.append(contentsOf: customPropertyKeys.map { propertyMap[$0] ?? "" })
                return row
            }

        let groupsHeader = ["groupRecordName", "groupName", "cohortRecordName", "createdAt", "updatedAt"]
        let groupsRows = payload.groups
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { group in
                [
                    payload.groupRecordName(group),
                    group.name,
                    payload.cohortRecordName,
                    "",
                    ""
                ]
            }

        let membershipsHeader = [
            "membershipRecordName",
            "studentRecordName",
            "groupRecordName",
            "cohortRecordName",
            "createdAt",
            "updatedAt"
        ]
        let membershipsRows = payload.memberships.map { membership in
            [
                payload.membershipRecordName(membership),
                membership.student.map(payload.studentRecordName) ?? "",
                membership.group.map(payload.groupRecordName) ?? "",
                payload.cohortRecordName,
                format(membership.createdAt),
                format(membership.updatedAt)
            ]
        }

        let expertiseHeader = ["expertiseRecordName", "title", "cohortRecordName", "sortOrder", "createdAt", "updatedAt"]
        let expertiseRows = payload.domains
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .enumerated()
            .map { index, domain in
                [
                    payload.domainRecordName(domain),
                    domain.name,
                    payload.cohortRecordName,
                    String(index),
                    "",
                    ""
                ]
            }

        let successCriteriaHeader = [
            "successCriterionRecordName",
            "code",
            "title",
            "description",
            "isQuantitative",
            "sortOrder",
            "isArchived",
            "cohortRecordName",
            "createdAt",
            "updatedAt"
        ]
        let successCriteriaRows = roots.map { root in
            [
                payload.learningObjectiveRecordName(root),
                root.code,
                root.title,
                root.objectiveDescription,
                boolString(root.isQuantitative),
                String(root.sortOrder),
                boolString(root.isArchived),
                payload.cohortRecordName,
                "",
                ""
            ]
        }

        let milestonesHeader = [
            "milestoneRecordName",
            "parentSuccessCriterionRecordName",
            "code",
            "title",
            "description",
            "isQuantitative",
            "sortOrder",
            "isArchived",
            "cohortRecordName",
            "createdAt",
            "updatedAt"
        ]
        let milestonesRows = milestones.map { milestone in
            let parent = payload.learningObjectives.first { milestone.isChild(of: $0) && $0.isRootCategory }
            return [
                payload.learningObjectiveRecordName(milestone),
                parent.map(payload.learningObjectiveRecordName) ?? "",
                milestone.code,
                milestone.title,
                milestone.objectiveDescription,
                boolString(milestone.isQuantitative),
                String(milestone.sortOrder),
                boolString(milestone.isArchived),
                payload.cohortRecordName,
                "",
                ""
            ]
        }

        let objectiveProgressHeader = [
            "progressRecordName",
            "studentRecordName",
            "milestoneRecordName",
            "milestoneCode",
            "value",
            "statusText",
            "notes",
            "cohortRecordName",
            "createdAt",
            "updatedAt"
        ]
        let objectiveProgressRows = payload.students
            .flatMap { student in
                student.progressRecords.map { progress in
                    let milestone = progress.objectiveId.flatMap { objectiveID in
                        payload.learningObjectives.first { $0.id == objectiveID }
                    } ?? payload.learningObjectives.first { $0.code == progress.objectiveCode }
                    return [
                        payload.progressRecordName(progress),
                        payload.studentRecordName(student),
                        milestone.map(payload.learningObjectiveRecordName) ?? "",
                        progress.objectiveCode,
                        String(progress.value),
                        progress.status.rawValue,
                        progress.notes,
                        payload.cohortRecordName,
                        "",
                        format(progress.lastUpdated)
                    ]
                }
            }

        let rollupHeader = [
            "studentRecordName",
            "successCriterionRecordName",
            "rollupValue",
            "computedStatus",
            "computedAt"
        ]
        let computedAt = format(Date())
        let rollupRows = payload.students.flatMap { student in
            roots.map { root in
                let value = ProgressCalculator.objectivePercentage(student: student, objective: root, allObjectives: payload.learningObjectives)
                return [
                    payload.studentRecordName(student),
                    payload.learningObjectiveRecordName(root),
                    String(value),
                    rollupStatus(for: value),
                    computedAt
                ]
            }
        }

        let labelsHeader = ["labelKey", "code", "title", "cohortRecordName"]
        let labelRows = payload.categoryLabels
            .sorted { $0.code < $1.code }
            .map { label in
                [label.key, label.code, label.title, payload.cohortRecordName]
            }

        let customPropertiesHeader = [
            "customPropertyRecordName",
            "studentRecordName",
            "key",
            "value",
            "sortOrder",
            "cohortRecordName"
        ]
        let customPropertiesRows = payload.students.flatMap { student in
            student.customProperties.map { property in
                [
                    payload.customPropertyRecordName(property),
                    payload.studentRecordName(student),
                    property.key,
                    property.value,
                    String(property.sortOrder),
                    payload.cohortRecordName
                ]
            }
        }

        return [
            "students.csv": makeCSV(header: studentsHeader, rows: studentsRows),
            "groups.csv": makeCSV(header: groupsHeader, rows: groupsRows),
            "student_group_memberships.csv": makeCSV(header: membershipsHeader, rows: membershipsRows),
            "expertise_checks.csv": makeCSV(header: expertiseHeader, rows: expertiseRows),
            "success_criteria.csv": makeCSV(header: successCriteriaHeader, rows: successCriteriaRows),
            "milestones.csv": makeCSV(header: milestonesHeader, rows: milestonesRows),
            "objective_progress.csv": makeCSV(header: objectiveProgressHeader, rows: objectiveProgressRows),
            "student_success_criteria_rollup.csv": makeCSV(header: rollupHeader, rows: rollupRows),
            "category_labels.csv": makeCSV(header: labelsHeader, rows: labelRows),
            "student_custom_properties.csv": makeCSV(header: customPropertiesHeader, rows: customPropertiesRows)
        ]
    }

    private func makeCSV(header: [String], rows: [[String]]) -> String {
        let allRows = [header] + rows
        return allRows
            .map { row in
                row.map(escapeCSV).joined(separator: ",")
            }
            .joined(separator: "\n") + "\n"
    }

    private func escapeCSV(_ value: String) -> String {
        let needsQuotes = value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r")
        guard needsQuotes else { return value }
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    private func format(_ date: Date?) -> String {
        guard let date else { return "" }
        return iso8601.string(from: date)
    }

    private func boolString(_ value: Bool) -> String {
        value ? "true" : "false"
    }

    private func rollupStatus(for value: Int) -> String {
        switch value {
        case 0: return ProgressStatus.notStarted.rawValue
        case 100: return ProgressStatus.complete.rawValue
        default: return ProgressStatus.inProgress.rawValue
        }
    }

    private func fallbackDirectoryURL(for destinationURL: URL) -> URL {
        let baseURL = destinationURL.deletingPathExtension()
        return baseURL.appendingPathExtension("csvexport")
    }

    private func zipDirectory(sourceDirectoryURL: URL, destinationURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = sourceDirectoryURL.deletingLastPathComponent()
        process.arguments = ["-r", "-q", destinationURL.path, sourceDirectoryURL.lastPathComponent]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrMessage = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let stdoutMessage = String(data: stdoutData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            var parts = ["zip exited with status \(process.terminationStatus)."]
            if stderrMessage.isEmpty == false {
                parts.append(stderrMessage)
            }
            if stdoutMessage.isEmpty == false {
                parts.append(stdoutMessage)
            }

            throw CSVExportError.zipFailed(parts.joined(separator: " "))
        }
    }
}
