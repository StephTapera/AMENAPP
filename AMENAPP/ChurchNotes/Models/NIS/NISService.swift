// NISService.swift
// AMEN — Notes Intelligence System
// Wave 0 Contracts — FROZEN after tag nis-contracts-v1
// All changes to this file require human approval per NIS build order §10.
//
// UI lanes MUST consume NISService only — never import FirebaseNISService directly.

import Foundation
import FirebaseFirestore
import FirebaseFunctions

// MARK: - NISService Protocol (frozen)

protocol NISService: AnyObject {
    /// Current pipeline processing state for a note.
    func processingState(for noteId: String) -> NISProcessingState

    /// Live stream of all detections for a note.
    /// Emits on every write to the detections subcollection.
    func detections(for noteId: String) -> AsyncStream<[NISDetection]>

    /// Accept or dismiss a proposed detection.
    func resolveDetection(noteId: String, detectionId: String, action: NISResolutionAction) async throws

    /// Trigger the Berean distillation pipeline for a note.
    /// Writes layers/distilled with status: proposed. Never auto-approves.
    func requestDistill(noteId: String) async throws

    /// Promote a prayer detection to a NISPrayer entity with lifecycle.
    @discardableResult
    func promotePrayer(noteId: String, detectionId: String) async throws -> NISPrayer

    /// Begin (or resume) a batch Apple Notes migration job.
    @discardableResult
    func startMigration(content: String, source: NISMigrationSource) async throws -> NISMigrationJob
}

enum NISResolutionAction: String {
    case accept  = "accept"
    case dismiss = "dismiss"
}

// MARK: - FirebaseNISService (concrete impl — Lane D, Wave 1 owns the full body)

/// Concrete NISService backed by Firestore listeners and deployed Cloud Functions.
/// This stub satisfies the protocol contract so Wave 2+ UI lanes compile immediately.
/// Lane D (Wave 1) replaces the stub bodies with real implementations.
final class FirebaseNISService: NISService {

    static let shared = FirebaseNISService()

    private let db = Firestore.firestore()
    private let functions = Functions.functions()

    private init() {}

    // MARK: Processing state

    func processingState(for noteId: String) -> NISProcessingState {
        .idle
    }

    // MARK: Detection stream

    func detections(for noteId: String) -> AsyncStream<[NISDetection]> {
        AsyncStream { continuation in
            let ref = db
                .collection("notes")
                .document(noteId)
                .collection("detections")

            let listener = ref.addSnapshotListener { snapshot, error in
                guard error == nil, let snapshot else {
                    continuation.yield([])
                    return
                }
                let decoder = Firestore.Decoder()
                let detections = snapshot.documents.compactMap { doc -> NISDetection? in
                    var d = try? decoder.decode(NISDetection.self, from: doc.data())
                    d?.id = doc.documentID
                    return d
                }
                continuation.yield(detections)
            }

            continuation.onTermination = { _ in
                listener.remove()
            }
        }
    }

    // MARK: Callables

    func resolveDetection(noteId: String, detectionId: String, action: NISResolutionAction) async throws {
        let payload: [String: Any] = [
            "noteId": noteId,
            "detectionId": detectionId,
            "action": action.rawValue
        ]
        _ = try await functions.httpsCallable("nisResolveDetection").call(payload)
    }

    func requestDistill(noteId: String) async throws {
        _ = try await functions.httpsCallable("nisDistillNote").call(["noteId": noteId])
    }

    @discardableResult
    func promotePrayer(noteId: String, detectionId: String) async throws -> NISPrayer {
        let payload: [String: Any] = ["noteId": noteId, "detectionId": detectionId]
        let result = try await functions.httpsCallable("nisPromotePrayer").call(payload)
        return try NISServiceDecoder.decode(NISPrayer.self, from: result.data, fn: "nisPromotePrayer")
    }

    @discardableResult
    func startMigration(content: String, source: NISMigrationSource) async throws -> NISMigrationJob {
        let payload: [String: Any] = ["content": content, "source": source.rawValue]
        let result = try await functions.httpsCallable("nisMigrationStart").call(payload)
        return try NISServiceDecoder.decode(NISMigrationJob.self, from: result.data, fn: "nisMigrationStart")
    }
}

// MARK: - NISServiceDecoder

private enum NISServiceDecoder {
    static func decode<T: Decodable>(_ type: T.Type, from data: Any?, fn: String) throws -> T {
        guard
            let dict = data as? [String: Any],
            let json = try? JSONSerialization.data(withJSONObject: dict),
            let value = try? JSONDecoder().decode(type, from: json)
        else {
            throw NISServiceError.decodingFailed(fn)
        }
        return value
    }
}

// MARK: - NISServiceError

enum NISServiceError: LocalizedError {
    case decodingFailed(String)
    case notAuthenticated
    case functionError(String)

    var errorDescription: String? {
        switch self {
        case .decodingFailed(let fn): return "NIS: failed to decode response from \(fn)"
        case .notAuthenticated:       return "NIS: user not authenticated"
        case .functionError(let msg): return "NIS: \(msg)"
        }
    }
}
