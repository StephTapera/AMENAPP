//
//  CloudKitSyncService.swift
//  AMENAPP
//
//  iCloud sync for Church Notes via CloudKit.
//  Syncs notes across devices using the user's iCloud account.
//

import Foundation
import CloudKit
import Combine

@MainActor
class CloudKitSyncService: ObservableObject {
    static let shared = CloudKitSyncService()

    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var syncError: String?
    @Published var isCloudAvailable = false

    private let container = CKContainer.default()
    private let privateDB: CKDatabase
    private let recordType = "ChurchNote"

    private init() {
        privateDB = container.privateCloudDatabase
        checkCloudStatus()
    }

    // MARK: - Cloud Status

    func checkCloudStatus() {
        container.accountStatus { [weak self] status, _ in
            Task { @MainActor in
                self?.isCloudAvailable = (status == .available)
            }
        }
    }

    // MARK: - Save Note

    func saveNote(_ note: SyncableChurchNote) async throws {
        guard isCloudAvailable else { throw CloudSyncError.cloudUnavailable }

        let record = CKRecord(recordType: recordType, recordID: CKRecord.ID(recordName: note.id))
        record["title"] = note.title as CKRecordValue
        record["content"] = note.content as CKRecordValue
        record["churchName"] = (note.churchName ?? "") as CKRecordValue
        record["sermonDate"] = note.sermonDate as CKRecordValue
        record["tags"] = note.tags as CKRecordValue
        record["updatedAt"] = note.updatedAt as CKRecordValue
        record["isArchived"] = (note.isArchived ? 1 : 0) as CKRecordValue

        let operation = CKModifyRecordsOperation(recordsToSave: [record])
        operation.savePolicy = .changedKeys
        operation.qualityOfService = .userInitiated

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            privateDB.add(operation)
        }
    }

    // MARK: - Fetch All Notes

    func fetchNotes() async throws -> [SyncableChurchNote] {
        guard isCloudAvailable else { throw CloudSyncError.cloudUnavailable }

        isSyncing = true
        defer { isSyncing = false }

        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]

        let (results, _) = try await privateDB.records(matching: query, resultsLimit: 200)

        var notes: [SyncableChurchNote] = []
        for (_, result) in results {
            if let record = try? result.get() {
                if let note = SyncableChurchNote(from: record) {
                    notes.append(note)
                }
            }
        }

        lastSyncDate = Date()
        return notes
    }

    // MARK: - Delete Note

    func deleteNote(id: String) async throws {
        guard isCloudAvailable else { throw CloudSyncError.cloudUnavailable }

        let recordID = CKRecord.ID(recordName: id)
        try await privateDB.deleteRecord(withID: recordID)
    }

    // MARK: - Subscribe to Changes

    func subscribeToChanges() async {
        guard isCloudAvailable else { return }

        let subscription = CKDatabaseSubscription(subscriptionID: "church-notes-changes")
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo

        do {
            try await privateDB.save(subscription)
        } catch {
            // Subscription may already exist — that's fine
            #if DEBUG
            print("CloudKit subscription setup: \(error.localizedDescription)")
            #endif
        }
    }

    enum CloudSyncError: Error, LocalizedError {
        case cloudUnavailable
        case recordNotFound

        var errorDescription: String? {
            switch self {
            case .cloudUnavailable: return "iCloud is not available. Please sign in to iCloud in Settings."
            case .recordNotFound: return "Note not found in iCloud."
            }
        }
    }
}

// MARK: - Syncable Church Note

struct SyncableChurchNote: Identifiable {
    let id: String
    var title: String
    var content: String
    var churchName: String?
    var sermonDate: Date
    var tags: [String]
    var updatedAt: Date
    var isArchived: Bool

    init(id: String = UUID().uuidString, title: String, content: String, churchName: String? = nil,
         sermonDate: Date = Date(), tags: [String] = [], updatedAt: Date = Date(), isArchived: Bool = false) {
        self.id = id
        self.title = title
        self.content = content
        self.churchName = churchName
        self.sermonDate = sermonDate
        self.tags = tags
        self.updatedAt = updatedAt
        self.isArchived = isArchived
    }

    init?(from record: CKRecord) {
        guard let title = record["title"] as? String,
              let content = record["content"] as? String else { return nil }

        self.id = record.recordID.recordName
        self.title = title
        self.content = content
        self.churchName = record["churchName"] as? String
        self.sermonDate = record["sermonDate"] as? Date ?? Date()
        self.tags = record["tags"] as? [String] ?? []
        self.updatedAt = record["updatedAt"] as? Date ?? record.modificationDate ?? Date()
        self.isArchived = (record["isArchived"] as? Int ?? 0) == 1
    }
}
