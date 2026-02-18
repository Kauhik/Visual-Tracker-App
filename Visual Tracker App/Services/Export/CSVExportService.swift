import Foundation

struct CSVExportPayload {
    struct SheetMetadata {
        let recordName: String
        let cohortId: String
        let name: String
        let createdAt: Date
        let updatedAt: Date
        let isActive: Bool
    }

    let cohortRecordName: String
    let activeSheetRecordName: String
    let activeSheetCohortId: String
    let activeSheetName: String
    let sheets: [SheetMetadata]
    let students: [Student]
    let groups: [CohortGroup]
    let memberships: [StudentGroupMembership]
    let domains: [Domain]
    let learningObjectives: [LearningObjective]
    let categoryLabels: [CategoryLabel]
    let expertiseCheckObjectiveScores: [ExpertiseCheckObjectiveScore]

    let studentRecordName: (Student) -> String
    let groupRecordName: (CohortGroup) -> String
    let membershipRecordName: (StudentGroupMembership) -> String
    let domainRecordName: (Domain) -> String
    let learningObjectiveRecordName: (LearningObjective) -> String
    let progressRecordName: (ObjectiveProgress) -> String
    let customPropertyRecordName: (StudentCustomProperty) -> String
    let expertiseCheckScoreRecordName: (ExpertiseCheckObjectiveScore) -> String
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
        let sortedSheets = payload.sheets.sorted {
            let compare = $0.name.localizedCaseInsensitiveCompare($1.name)
            if compare == .orderedSame {
                return $0.recordName < $1.recordName
            }
            return compare == .orderedAscending
        }
        let sortedGroups = payload.groups.sorted {
            let compare = $0.name.localizedCaseInsensitiveCompare($1.name)
            if compare == .orderedSame {
                return payload.groupRecordName($0) < payload.groupRecordName($1)
            }
            return compare == .orderedAscending
        }
        let sortedDomains = payload.domains.sorted {
            let compare = $0.name.localizedCaseInsensitiveCompare($1.name)
            if compare == .orderedSame {
                return payload.domainRecordName($0) < payload.domainRecordName($1)
            }
            return compare == .orderedAscending
        }
        let sortedStudents = payload.students.sorted {
            let compare = $0.name.localizedCaseInsensitiveCompare($1.name)
            if compare == .orderedSame {
                return payload.studentRecordName($0) < payload.studentRecordName($1)
            }
            return compare == .orderedAscending
        }

        let allObjectives = payload.learningObjectives.sorted { lhs, rhs in
            if lhs.sortOrder != rhs.sortOrder {
                return lhs.sortOrder < rhs.sortOrder
            }
            if lhs.code != rhs.code {
                return lhs.code < rhs.code
            }
            return payload.learningObjectiveRecordName(lhs) < payload.learningObjectiveRecordName(rhs)
        }
        let activeObjectives = allObjectives.filter { $0.isArchived == false }
        let roots = activeObjectives.filter { $0.isRootCategory }
        let milestones = activeObjectives.filter { $0.isRootCategory == false }

        let objectiveByID = Dictionary(uniqueKeysWithValues: allObjectives.map { ($0.id, $0) })
        var objectiveByCode: [String: LearningObjective] = [:]
        for objective in allObjectives where objectiveByCode[objective.code] == nil {
            objectiveByCode[objective.code] = objective
        }
        let domainByID = Dictionary(uniqueKeysWithValues: sortedDomains.map { ($0.id, $0) })

        var membershipGroupsByStudentID: [UUID: [CohortGroup]] = [:]
        for membership in payload.memberships {
            guard let student = membership.student, let group = membership.group else { continue }
            membershipGroupsByStudentID[student.id, default: []].append(group)
        }
        for (studentID, groups) in membershipGroupsByStudentID {
            let sortedUniqueGroups = groups
                .sorted { lhs, rhs in
                    let compare = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                    if compare == .orderedSame {
                        return payload.groupRecordName(lhs) < payload.groupRecordName(rhs)
                    }
                    return compare == .orderedAscending
                }
                .reduce(into: [CohortGroup]()) { result, group in
                    if result.contains(where: { $0.id == group.id }) == false {
                        result.append(group)
                    }
                }
            membershipGroupsByStudentID[studentID] = sortedUniqueGroups
        }

        var customPropertyKeys: [String] = []
        var customPropertySet = Set<String>()
        for student in sortedStudents {
            let sortedProperties = student.customProperties.sorted {
                if $0.sortOrder != $1.sortOrder {
                    return $0.sortOrder < $1.sortOrder
                }
                return $0.key < $1.key
            }
            for property in sortedProperties where customPropertySet.insert(property.key).inserted {
                customPropertyKeys.append(property.key)
            }
        }

        let exportMetadataHeader = [
            "activeSheetRecordName",
            "activeSheetCohortId",
            "activeSheetName",
            "cohortRecordName"
        ]
        let exportMetadataRows = [[
            payload.activeSheetRecordName,
            payload.activeSheetCohortId,
            payload.activeSheetName,
            payload.cohortRecordName
        ]]

        let sheetsHeader = [
            "sheetRecordName",
            "cohortId",
            "sheetName",
            "isActive",
            "createdAt",
            "updatedAt"
        ]
        let sheetsRows = sortedSheets.map { sheet in
            [
                sheet.recordName,
                sheet.cohortId,
                sheet.name,
                boolString(sheet.isActive),
                format(sheet.createdAt),
                format(sheet.updatedAt)
            ]
        }

        let studentsHeader = [
            "studentRecordName",
            "studentName",
            "session",
            "cohortRecordName",
            "activeSheetRecordName",
            "activeSheetName",
            "domainRecordName",
            "domainName",
            "legacyGroupRecordName",
            "legacyGroupName",
            "membershipGroupRecordNames",
            "membershipGroupNames",
            "createdAt",
            "updatedAt"
        ] + customPropertyKeys

        let studentsRows = sortedStudents.map { student in
            let studentRecordName = payload.studentRecordName(student)
            let domainRecordName = student.domain.map(payload.domainRecordName) ?? ""
            let domainName = student.domain?.name ?? ""
            let legacyGroupRecordName = student.group.map(payload.groupRecordName) ?? ""
            let legacyGroupName = student.group?.name ?? ""
            let membershipGroups = membershipGroupsByStudentID[student.id] ?? []
            let membershipGroupRecordNames = semicolonList(membershipGroups.map { payload.groupRecordName($0) })
            let membershipGroupNames = semicolonList(membershipGroups.map(\.name))
            let propertyMap = Dictionary(uniqueKeysWithValues: student.customProperties.map { ($0.key, $0.value) })

            var row: [String] = [
                studentRecordName,
                student.name,
                student.session.rawValue,
                payload.cohortRecordName,
                payload.activeSheetRecordName,
                payload.activeSheetName,
                domainRecordName,
                domainName,
                legacyGroupRecordName,
                legacyGroupName,
                membershipGroupRecordNames,
                membershipGroupNames,
                format(student.createdAt),
                ""
            ]
            row.append(contentsOf: customPropertyKeys.map { propertyMap[$0] ?? "" })
            return row
        }

        let groupsHeader = [
            "groupRecordName",
            "groupName",
            "colorHex",
            "cohortRecordName",
            "createdAt",
            "updatedAt"
        ]
        let groupsRows = sortedGroups.map { group in
            [
                payload.groupRecordName(group),
                group.name,
                group.colorHex ?? "",
                payload.cohortRecordName,
                "",
                ""
            ]
        }

        let membershipsHeader = [
            "membershipRecordName",
            "studentRecordName",
            "studentName",
            "groupRecordName",
            "groupName",
            "cohortRecordName",
            "createdAt",
            "updatedAt"
        ]
        let membershipsRows = payload.memberships
            .sorted { lhs, rhs in
                let lhsStudentName = lhs.student?.name ?? ""
                let rhsStudentName = rhs.student?.name ?? ""
                let studentCompare = lhsStudentName.localizedCaseInsensitiveCompare(rhsStudentName)
                if studentCompare != .orderedSame {
                    return studentCompare == .orderedAscending
                }
                let lhsGroupName = lhs.group?.name ?? ""
                let rhsGroupName = rhs.group?.name ?? ""
                let groupCompare = lhsGroupName.localizedCaseInsensitiveCompare(rhsGroupName)
                if groupCompare != .orderedSame {
                    return groupCompare == .orderedAscending
                }
                return payload.membershipRecordName(lhs) < payload.membershipRecordName(rhs)
            }
            .map { membership in
                [
                    payload.membershipRecordName(membership),
                    membership.student.map(payload.studentRecordName) ?? "",
                    membership.student?.name ?? "",
                    membership.group.map(payload.groupRecordName) ?? "",
                    membership.group?.name ?? "",
                    payload.cohortRecordName,
                    format(membership.createdAt),
                    format(membership.updatedAt)
                ]
            }

        let expertiseHeader = [
            "expertiseCheckRecordName",
            "expertiseCheckName",
            "overallMode",
            "cohortRecordName",
            "sortOrder",
            "createdAt",
            "updatedAt"
        ]
        let expertiseRows = sortedDomains.enumerated().map { index, domain in
            [
                payload.domainRecordName(domain),
                domain.name,
                domain.overallMode.rawValue,
                payload.cohortRecordName,
                String(index),
                "",
                ""
            ]
        }

        let learningObjectivesHeader = [
            "objectiveRecordName",
            "code",
            "title",
            "objectiveDescription",
            "isQuantitative",
            "sortOrder",
            "isArchived",
            "parentObjectiveRecordName",
            "parentCode",
            "parentTitle",
            "cohortRecordName",
            "createdAt",
            "updatedAt"
        ]
        let learningObjectivesRows = allObjectives.map { objective in
            let parentFromID = objective.parentId.flatMap { objectiveByID[$0] }
            let parentFromCode = objective.parentCode.flatMap { objectiveByCode[$0] }
            let parent = parentFromID ?? parentFromCode

            return [
                payload.learningObjectiveRecordName(objective),
                objective.code,
                objective.title,
                objective.objectiveDescription,
                boolString(objective.isQuantitative),
                String(objective.sortOrder),
                boolString(objective.isArchived),
                parent.map(payload.learningObjectiveRecordName) ?? "",
                objective.parentCode ?? parent?.code ?? "",
                parent?.title ?? "",
                payload.cohortRecordName,
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
            "parentCode",
            "parentTitle",
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
            let parent = milestone.parentId.flatMap { objectiveByID[$0] }
                ?? milestone.parentCode.flatMap { objectiveByCode[$0] }
            return [
                payload.learningObjectiveRecordName(milestone),
                parent.map(payload.learningObjectiveRecordName) ?? "",
                milestone.parentCode ?? parent?.code ?? "",
                parent?.title ?? "",
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
            "cohortRecordName",
            "studentRecordName",
            "studentName",
            "objectiveRecordName",
            "objectiveCode",
            "objectiveTitle",
            "value",
            "statusText",
            "notes",
            "createdAt",
            "updatedAt",
            "milestoneRecordName",
            "milestoneCode"
        ]
        let objectiveProgressRows = sortedStudents
            .flatMap { student in
                student.progressRecords.map { progress -> [String] in
                    let objective = progress.objectiveId.flatMap { objectiveByID[$0] }
                        ?? objectiveByCode[progress.objectiveCode]
                    let objectiveRecordName = objective.map(payload.learningObjectiveRecordName) ?? ""
                    let objectiveCode = objective?.code ?? progress.objectiveCode
                    let objectiveTitle = objective?.title ?? ""

                    return [
                        payload.progressRecordName(progress),
                        payload.cohortRecordName,
                        payload.studentRecordName(student),
                        student.name,
                        objectiveRecordName,
                        objectiveCode,
                        objectiveTitle,
                        String(progress.value),
                        progress.status.rawValue,
                        progress.notes,
                        "",
                        format(progress.lastUpdated),
                        objectiveRecordName,
                        objectiveCode
                    ]
                }
            }
            .sorted { lhs, rhs in
                if lhs[3] != rhs[3] { return lhs[3].localizedCaseInsensitiveCompare(rhs[3]) == .orderedAscending }
                if lhs[5] != rhs[5] { return lhs[5] < rhs[5] }
                return lhs[0] < rhs[0]
            }

        let rollupHeader = [
            "studentRecordName",
            "studentName",
            "successCriterionRecordName",
            "successCriterionCode",
            "successCriterionTitle",
            "rollupValue",
            "computedStatus",
            "computedAt"
        ]
        let computedAt = format(Date())
        let rollupRows = sortedStudents.flatMap { student in
            roots.map { root in
                let value = ProgressCalculator.objectivePercentage(
                    student: student,
                    objective: root,
                    allObjectives: activeObjectives
                )
                return [
                    payload.studentRecordName(student),
                    student.name,
                    payload.learningObjectiveRecordName(root),
                    root.code,
                    root.title,
                    String(value),
                    rollupStatus(for: value),
                    computedAt
                ]
            }
        }

        let expertiseScoreHeader = [
            "scoreRecordName",
            "cohortRecordName",
            "expertiseCheckRecordName",
            "expertiseCheckName",
            "objectiveRecordName",
            "objectiveCode",
            "objectiveTitle",
            "value",
            "status",
            "createdAt",
            "updatedAt",
            "lastEditedByDisplayName"
        ]
        let expertiseScoreRows = payload.expertiseCheckObjectiveScores
            .sorted { lhs, rhs in
                let lhsDomain = lhs.expertiseCheckId.flatMap { domainByID[$0] }?.name ?? ""
                let rhsDomain = rhs.expertiseCheckId.flatMap { domainByID[$0] }?.name ?? ""
                let domainCompare = lhsDomain.localizedCaseInsensitiveCompare(rhsDomain)
                if domainCompare != .orderedSame {
                    return domainCompare == .orderedAscending
                }
                let lhsCode = lhs.objectiveCode
                let rhsCode = rhs.objectiveCode
                if lhsCode != rhsCode {
                    return lhsCode < rhsCode
                }
                return payload.expertiseCheckScoreRecordName(lhs) < payload.expertiseCheckScoreRecordName(rhs)
            }
            .map { score in
                let domain = score.expertiseCheckId.flatMap { domainByID[$0] }
                let objective = score.objectiveId.flatMap { objectiveByID[$0] }
                    ?? objectiveByCode[score.objectiveCode]
                return [
                    payload.expertiseCheckScoreRecordName(score),
                    payload.cohortRecordName,
                    domain.map(payload.domainRecordName) ?? "",
                    domain?.name ?? "",
                    objective.map(payload.learningObjectiveRecordName) ?? "",
                    objective?.code ?? score.objectiveCode,
                    objective?.title ?? "",
                    String(score.value),
                    score.status.rawValue,
                    format(score.createdAt),
                    format(score.updatedAt),
                    score.lastEditedByDisplayName ?? ""
                ]
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
            "studentName",
            "key",
            "value",
            "sortOrder",
            "cohortRecordName"
        ]
        let customPropertiesRows = sortedStudents.flatMap { student in
            student.customProperties
                .sorted {
                    if $0.sortOrder != $1.sortOrder {
                        return $0.sortOrder < $1.sortOrder
                    }
                    return $0.key < $1.key
                }
                .map { property in
                    [
                        payload.customPropertyRecordName(property),
                        payload.studentRecordName(student),
                        student.name,
                        property.key,
                        property.value,
                        String(property.sortOrder),
                        payload.cohortRecordName
                    ]
                }
        }

        return [
            "category_labels.csv": makeCSV(header: labelsHeader, rows: labelRows),
            "expertise_check_objective_scores.csv": makeCSV(header: expertiseScoreHeader, rows: expertiseScoreRows),
            "expertise_checks.csv": makeCSV(header: expertiseHeader, rows: expertiseRows),
            "export_metadata.csv": makeCSV(header: exportMetadataHeader, rows: exportMetadataRows),
            "groups.csv": makeCSV(header: groupsHeader, rows: groupsRows),
            "learning_objectives.csv": makeCSV(header: learningObjectivesHeader, rows: learningObjectivesRows),
            "milestones.csv": makeCSV(header: milestonesHeader, rows: milestonesRows),
            "objective_progress.csv": makeCSV(header: objectiveProgressHeader, rows: objectiveProgressRows),
            "sheets.csv": makeCSV(header: sheetsHeader, rows: sheetsRows),
            "student_custom_properties.csv": makeCSV(header: customPropertiesHeader, rows: customPropertiesRows),
            "student_group_memberships.csv": makeCSV(header: membershipsHeader, rows: membershipsRows),
            "student_success_criteria_rollup.csv": makeCSV(header: rollupHeader, rows: rollupRows),
            "students.csv": makeCSV(header: studentsHeader, rows: studentsRows),
            "success_criteria.csv": makeCSV(header: successCriteriaHeader, rows: successCriteriaRows)
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

    private func semicolonList(_ values: [String]) -> String {
        var seen = Set<String>()
        let deduplicated = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
            .filter { seen.insert($0).inserted }
        return deduplicated.joined(separator: ";")
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
