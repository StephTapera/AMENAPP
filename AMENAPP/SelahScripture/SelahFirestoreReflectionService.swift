//
//  SelahFirestoreReflectionService.swift
//  AMENAPP
//
//  Phase 3b — Reflections & Privacy
//  Firestore persistence layer for SelahReflectionDocument.
//  All paths follow the reflections/{id} collection schema defined in
//  Selah/_contracts/SelahContracts.swift.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - Error

enum SelahReflectionError: LocalizedError {
    case notAuthenticated
    case saveFailed(String)
    case fetchFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in to access your reflections."
        case .saveFailed(let reason):
            return "Could not save reflection: \(reason)"
        case .fetchFailed(let reason):
            return "Could not load reflections: \(reason)"
        }
    }
}

// MARK: - Service

@MainActor
final class SelahFirestoreReflectionService {

    static let shared = SelahFirestoreReflectionService()
    private let db = Firestore.firestore()

    private init() {}

    // MARK: - Write

    func saveReflection(_ doc: SelahReflectionDocument) async throws {
        let uid = try requireUID()
        guard doc.ownerUid == uid else {
            throw SelahReflectionError.saveFailed("Owner UID mismatch.")
        }
        do {
            try await db.collection("reflections")
                .document(doc.id)
                .setData(encode(doc))
        } catch {
            throw SelahReflectionError.saveFailed(error.localizedDescription)
        }
    }

    func updateReflection(_ doc: SelahReflectionDocument) async throws {
        _ = try requireUID()
        do {
            try await db.collection("reflections")
                .document(doc.id)
                .setData(encode(doc), merge: true)
        } catch {
            throw SelahReflectionError.saveFailed(error.localizedDescription)
        }
    }

    func deleteReflection(id: String) async throws {
        _ = try requireUID()
        do {
            try await db.collection("reflections")
                .document(id)
                .delete()
        } catch {
            throw SelahReflectionError.saveFailed(error.localizedDescription)
        }
    }

    // MARK: - Read

    func fetchMyReflections() async throws -> [SelahReflectionDocument] {
        let uid = try requireUID()
        do {
            let snapshot = try await db.collection("reflections")
                .whereField("ownerUid", isEqualTo: uid)
                .order(by: "createdAt", descending: true)
                .getDocuments()
            return snapshot.documents.compactMap { decode($0.data()) }
        } catch {
            throw SelahReflectionError.fetchFailed(error.localizedDescription)
        }
    }

    func fetchReflectionsForVerse(
        verseId: String,
        translation: SelahTranslation
    ) async throws -> [SelahReflectionDocument] {
        _ = try requireUID()
        do {
            let snapshot = try await db.collection("reflections")
                .whereField("verseId", isEqualTo: verseId)
                .whereField("translation", isEqualTo: translation.rawValue)
                // Only shared documents are readable by non-owners via security rules.
                .order(by: "createdAt", descending: true)
                .getDocuments()
            return snapshot.documents.compactMap { decode($0.data()) }
        } catch {
            throw SelahReflectionError.fetchFailed(error.localizedDescription)
        }
    }

    func updateRelationalSignals(
        reflectionId: String,
        prayedByGroupCount: Int
    ) async throws {
        _ = try requireUID()
        let signals: [String: Any] = [
            "relationalSignals": [
                "prayedByGroupCount": prayedByGroupCount,
                "lastPrayerAt": FieldValue.serverTimestamp()
            ],
            "updatedAt": FieldValue.serverTimestamp()
        ]
        do {
            try await db.collection("reflections")
                .document(reflectionId)
                .updateData(signals)
        } catch {
            throw SelahReflectionError.saveFailed(error.localizedDescription)
        }
    }

    // MARK: - Private Helpers

    private func requireUID() throws -> String {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw SelahReflectionError.notAuthenticated
        }
        return uid
    }

    private func encode(_ doc: SelahReflectionDocument) -> [String: Any] {
        var map: [String: Any] = [
            "id": doc.id,
            "ownerUid": doc.ownerUid,
            "body": doc.body,
            "safetyTheme": doc.safetyTheme.rawValue,
            "shareScope": doc.shareScope.rawValue,
            "isShareEligible": doc.isShareEligible,
            "relationalSignals": [
                "prayedByGroupCount": doc.relationalSignals.prayedByGroupCount,
                "lastPrayerAt": doc.relationalSignals.lastPrayerAt.map {
                    Timestamp(date: $0)
                } as Any
            ],
            "createdAt": Timestamp(date: doc.createdAt),
            "updatedAt": Timestamp(date: doc.updatedAt)
        ]
        if let verseId = doc.verseId { map["verseId"] = verseId }
        if let translation = doc.translation { map["translation"] = translation.rawValue }
        if let uid = doc.sharedWithUid { map["sharedWithUid"] = uid }
        if let gid = doc.sharedWithGroupId { map["sharedWithGroupId"] = gid }
        return map
    }

    private func decode(_ data: [String: Any]) -> SelahReflectionDocument? {
        guard
            let id = data["id"] as? String,
            let ownerUid = data["ownerUid"] as? String,
            let body = data["body"] as? String,
            let safetyThemeRaw = data["safetyTheme"] as? String,
            let safetyTheme = SelahSafetyTheme(rawValue: safetyThemeRaw),
            let shareScopeRaw = data["shareScope"] as? String,
            let shareScope = SelahReflectionShareScope(rawValue: shareScopeRaw),
            let isShareEligible = data["isShareEligible"] as? Bool,
            let createdTs = data["createdAt"] as? Timestamp,
            let updatedTs = data["updatedAt"] as? Timestamp
        else { return nil }

        let translationRaw = data["translation"] as? String
        let translation = translationRaw.flatMap { SelahTranslation(rawValue: $0) }

        let signalsMap = data["relationalSignals"] as? [String: Any]
        let prayedCount = signalsMap?["prayedByGroupCount"] as? Int ?? 0
        let lastPrayerAt = (signalsMap?["lastPrayerAt"] as? Timestamp)?.dateValue()
        let relationalSignals = SelahRelationalSignals(
            prayedByGroupCount: prayedCount,
            lastPrayerAt: lastPrayerAt
        )

        return SelahReflectionDocument(
            id: id,
            ownerUid: ownerUid,
            verseId: data["verseId"] as? String,
            translation: translation,
            body: body,
            safetyTheme: safetyTheme,
            shareScope: shareScope,
            sharedWithUid: data["sharedWithUid"] as? String,
            sharedWithGroupId: data["sharedWithGroupId"] as? String,
            isShareEligible: isShareEligible,
            relationalSignals: relationalSignals,
            createdAt: createdTs.dateValue(),
            updatedAt: updatedTs.dateValue()
        )
    }
}
