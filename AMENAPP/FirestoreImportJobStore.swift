
//
//  FirestoreImportJobStore.swift
//  AMENAPP
//
//  Thin Firestore layer for the server-tracked import pipeline.
//  Mirrors the naming convention of existing service classes (e.g. BereanMemoryService).
//
//  Collection layout:
//    importJobs/{uid}/jobs/{jobId}                     → ImportJob
//    importJobs/{uid}/jobs/{jobId}/candidates/{id}     → ImportCandidate
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseStorage

@MainActor
final class FirestoreImportJobStore: ObservableObject {

    static let shared = FirestoreImportJobStore()
    private init() {}

    private let db = Firestore.firestore()

    // MARK: - Paths

    private func jobsRef(uid: String) -> CollectionReference {
        db.collection("importJobs").document(uid).collection("jobs")
    }

    private func jobRef(uid: String, jobId: String) -> DocumentReference {
        jobsRef(uid: uid).document(jobId)
    }

    private func candidatesRef(uid: String, jobId: String) -> CollectionReference {
        jobRef(uid: uid, jobId: jobId).collection("candidates")
    }

    // MARK: - Create Job

    func createJob(uid: String, source: ImportJobSource) async throws -> ImportJob {
        let ref = jobsRef(uid: uid).document()
        let job = ImportJob(
            id: ref.documentID,
            source: source,
            status: .uploading,
            counts: ImportJobCounts(),
            createdAt: Date(),
            error: nil
        )
        let data: [String: Any] = [
            "source":    job.source.rawValue,
            "status":    job.status.rawValue,
            "counts":    ["found": 0, "candidates": 0, "imported": 0],
            "createdAt": Timestamp(date: job.createdAt)
        ]
        try await ref.setData(data)
        return job
    }

    // MARK: - Update Job Status

    func updateJobStatus(uid: String, jobId: String, status: ImportJobStatus) async throws {
        try await jobRef(uid: uid, jobId: jobId).updateData(["status": status.rawValue])
    }

    // MARK: - Observe Job (real-time)

    func observeJob(uid: String, jobId: String) -> AsyncStream<ImportJob?> {
        AsyncStream { continuation in
            let listener = jobRef(uid: uid, jobId: jobId).addSnapshotListener { snap, _ in
                guard let snap, snap.exists else {
                    continuation.yield(nil)
                    return
                }
                do {
                    let job = try snap.data(as: ImportJob.self)
                    continuation.yield(job)
                } catch {
                    continuation.yield(nil)
                }
            }
            continuation.onTermination = { _ in listener.remove() }
        }
    }

    // MARK: - Observe Candidates (real-time)

    func observeCandidates(uid: String, jobId: String) -> AsyncStream<[ImportCandidate]> {
        AsyncStream { continuation in
            let listener = candidatesRef(uid: uid, jobId: jobId)
                .order(by: "originalTimestamp", descending: true)
                .addSnapshotListener { snap, _ in
                    guard let snap else { continuation.yield([]); return }
                    let candidates = snap.documents.compactMap {
                        try? $0.data(as: ImportCandidate.self)
                    }
                    continuation.yield(candidates)
                }
            continuation.onTermination = { _ in listener.remove() }
        }
    }

    // MARK: - Fetch Candidates (one-shot)

    func fetchCandidates(uid: String, jobId: String) async throws -> [ImportCandidate] {
        let snap = try await candidatesRef(uid: uid, jobId: jobId).getDocuments()
        return snap.documents.compactMap { try? $0.data(as: ImportCandidate.self) }
    }

    // MARK: - Update Candidate Decision

    func updateCandidateDecision(
        uid: String,
        jobId: String,
        candidateId: String,
        decision: UserImportDecision,
        editedText: String? = nil
    ) async throws {
        var update: [String: Any] = ["userDecision": decision.rawValue]
        if let text = editedText {
            update["bereanClassification.reconsecratedDraft"] = text
        }
        try await candidatesRef(uid: uid, jobId: jobId)
            .document(candidateId)
            .updateData(update)
    }

    // MARK: - Delete Job

    /// Purges the job doc, all candidate sub-docs, and the Storage folder.
    func deleteJob(uid: String, jobId: String) async throws {
        // Delete candidate sub-collection in batches
        var snap = try await candidatesRef(uid: uid, jobId: jobId).limit(to: 100).getDocuments()
        while !snap.documents.isEmpty {
            let batch = db.batch()
            snap.documents.forEach { batch.deleteDocument($0.reference) }
            try await batch.commit()
            snap = try await candidatesRef(uid: uid, jobId: jobId).limit(to: 100).getDocuments()
        }

        // Delete the job document
        try await jobRef(uid: uid, jobId: jobId).delete()

        // Delete Storage folder (archive + extracted media)
        let folder = Storage.storage().reference()
            .child("imports/\(uid)/\(jobId)")
        try await deleteStorageFolder(folder)
    }

    /// Deletes only the raw archive.zip — called immediately after server parsing completes.
    func deleteRawArchive(uid: String, jobId: String) async throws {
        let ref = Storage.storage().reference()
            .child("imports/\(uid)/\(jobId)/archive.zip")
        try? await ref.delete()
    }

    /// Deletes extracted media for a specific candidate (called when user discards it).
    func deleteCandidateMedia(uid: String, jobId: String, mediaRefs: [String]) async {
        await withTaskGroup(of: Void.self) { group in
            for path in mediaRefs {
                group.addTask {
                    try? await Storage.storage().reference(withPath: path).delete()
                }
            }
        }
    }

    // MARK: - Update Imported Count

    func incrementImportedCount(uid: String, jobId: String) async throws {
        try await jobRef(uid: uid, jobId: jobId)
            .updateData(["counts.imported": FieldValue.increment(Int64(1))])
    }

    func setJobDone(uid: String, jobId: String) async throws {
        try await jobRef(uid: uid, jobId: jobId)
            .updateData(["status": ImportJobStatus.done.rawValue])
    }

    // MARK: - Private

    private func deleteStorageFolder(_ ref: StorageReference) async throws {
        let list = try await ref.listAll()
        await withTaskGroup(of: Void.self) { group in
            list.items.forEach { item in
                group.addTask { try? await item.delete() }
            }
            for prefix in list.prefixes {
                group.addTask { try? await self.deleteStorageFolder(prefix) }
            }
        }
    }
}
