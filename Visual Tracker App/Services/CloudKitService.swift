import CloudKit
import Foundation
import os.log

final class CloudKitService {
    private let container: CKContainer
    private let database: CKDatabase
    private let logger: Logger

    init() {
        let containerIdentifier = CloudKitConfig.containerIdentifier
        self.container = CKContainer(identifier: containerIdentifier)
        self.database = container.publicCloudDatabase
        self.logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "VisualTrackerApp", category: "CloudKit")
        logger.info("Using CloudKit container: \(self.containerIdentifier, privacy: .public)")
    }

    var containerIdentifier: String {
        container.containerIdentifier ?? "default"
    }

    func accountStatus() async throws -> CKAccountStatus {
        try await container.accountStatus()
    }

    func fetchRecord(with recordID: CKRecord.ID) async throws -> CKRecord {
        try await withCheckedThrowingContinuation { continuation in
            database.fetch(withRecordID: recordID) { record, error in
                if let error {
                    self.logger.error("fetchRecord failed: \(self.describe(error), privacy: .public)")
                    continuation.resume(throwing: error)
                    return
                }
                if let record {
                    continuation.resume(returning: record)
                } else {
                    self.logger.error("fetchRecord failed: missing record")
                    continuation.resume(throwing: CKError(.unknownItem))
                }
            }
        }
    }

    func save(record: CKRecord) async throws -> CKRecord {
        do {
            return try await saveRecord(record)
        } catch {
            logger.error("save record failed: \(self.describe(error), privacy: .public)")
            if let ckError = error as? CKError,
               ckError.code == .serverRecordChanged,
               let serverRecord = ckError.serverRecord {
                mergeFields(from: record, into: serverRecord)
                return try await saveRecord(serverRecord)
            }
            throw error
        }
    }

    func delete(recordID: CKRecord.ID) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            database.delete(withRecordID: recordID) { _, error in
                if let error {
                    self.logger.error("delete record failed: \(self.describe(error), privacy: .public)")
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func queryRecords(
        ofType recordType: String,
        predicate: NSPredicate,
        sortDescriptors: [NSSortDescriptor] = []
    ) async throws -> [CKRecord] {
        var records: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor?

        repeat {
            let operation: CKQueryOperation
            if let cursor {
                operation = CKQueryOperation(cursor: cursor)
            } else {
                let query = CKQuery(recordType: recordType, predicate: predicate)
                query.sortDescriptors = sortDescriptors
                operation = CKQueryOperation(query: query)
            }

            operation.resultsLimit = CKQueryOperation.maximumResults
            operation.recordFetchedBlock = { record in
                records.append(record)
            }

            cursor = try await withCheckedThrowingContinuation { continuation in
                operation.queryResultBlock = { result in
                    switch result {
                    case .success(let nextCursor):
                        continuation.resume(returning: nextCursor)
                    case .failure(let error):
                        self.logger.error("query failed: \(self.describe(error), privacy: .public)")
                        continuation.resume(throwing: error)
                    }
                }

                database.add(operation)
            }
        } while cursor != nil

        return records
    }

    private func saveRecord(_ record: CKRecord) async throws -> CKRecord {
        try await withCheckedThrowingContinuation { continuation in
            database.save(record) { savedRecord, error in
                if let error {
                    self.logger.error("saveRecord failed: \(self.describe(error), privacy: .public)")
                    continuation.resume(throwing: error)
                    return
                }
                if let savedRecord {
                    continuation.resume(returning: savedRecord)
                } else {
                    self.logger.error("saveRecord failed: missing saved record")
                    continuation.resume(throwing: CKError(.unknownItem))
                }
            }
        }
    }

    private func mergeFields(from source: CKRecord, into target: CKRecord) {
        for key in source.allKeys() {
            target[key] = source[key]
        }
    }

    func describe(_ error: Error) -> String {
        if let ckError = error as? CKError {
            var parts = ["CKError.\(ckError.code.rawValue)"]
            if let retry = ckError.retryAfterSeconds {
                parts.append("retryAfter=\(retry)")
            }
            if let reason = ckError.userInfo[NSLocalizedFailureReasonErrorKey] as? String {
                parts.append("reason=\"\(reason)\"")
            }
            if let message = ckError.userInfo[NSLocalizedDescriptionKey] as? String {
                parts.append("message=\"\(message)\"")
            }
            return parts.joined(separator: " | ")
        }
        return error.localizedDescription
    }
}
