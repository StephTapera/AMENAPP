// NonprofitDataService.swift
// AMENAPP
//
// Loads organization data from Firestore. Read-only for clients.
// Transparency, trust scores, and impact data are server-managed — never client-written.
// Falls back gracefully when data is stale or missing.

import Foundation
import FirebaseFirestore

@MainActor
final class NonprofitDataService: ObservableObject {

    private let db = Firestore.firestore()

    // MARK: - Load Organizations

    func fetchOrganizations(
        causeFilters: [GivingCause] = [],
        limit: Int = 50
    ) async throws -> [GivingOrganization] {
        var query: Query = db.collection("organizations")
            .whereField("isActive", isEqualTo: true)
            .whereField("rankingEligibility", isEqualTo: true)
            .limit(to: limit)

        // Apply cause filter if specified
        if !causeFilters.isEmpty {
            let rawValues = causeFilters.map { $0.rawValue }
            query = query.whereField("causeCategories", arrayContainsAny: rawValues)
        }

        let snapshot = try await query.getDocuments()
        return snapshot.documents.compactMap { decode(GivingOrganization.self, from: $0) }
    }

    func fetchOrganization(id: String) async throws -> GivingOrganization? {
        let doc = try await db.collection("organizations").document(id).getDocument()
        guard doc.exists else { return nil }
        return decode(GivingOrganization.self, from: doc)
    }

    func fetchOrganizations(ids: [String]) async throws -> [GivingOrganization] {
        guard !ids.isEmpty else { return [] }
        // Firestore `in` queries limited to 10 — batch if needed
        let batches = stride(from: 0, to: ids.count, by: 10).map { Array(ids[$0..<min($0+10, ids.count)]) }
        var results: [GivingOrganization] = []
        for batch in batches {
            let snap = try await db.collection("organizations")
                .whereField(FieldPath.documentID(), in: batch)
                .getDocuments()
            results += snap.documents.compactMap { decode(GivingOrganization.self, from: $0) }
        }
        return results
    }

    // MARK: - Cause Briefs

    func fetchCauseBriefs(limit: Int = 20) async throws -> [CauseBrief] {
        let snap = try await db.collection("cause_briefs")
            .whereField("isActive", isEqualTo: true)
            .order(by: "publishedAt", descending: true)
            .limit(to: limit)
            .getDocuments()
        return snap.documents.compactMap { decode(CauseBrief.self, from: $0) }
    }

    // MARK: - Disaster Events

    func fetchActiveDisasterEvents() async throws -> [DisasterEvent] {
        let snap = try await db.collection("disaster_events")
            .whereField("isActive", isEqualTo: true)
            .order(by: "startedAt", descending: true)
            .limit(to: 5)
            .getDocuments()
        return snap.documents.compactMap { decode(DisasterEvent.self, from: $0) }
    }

    // MARK: - Benevolence Requests

    func fetchApprovedRequests(limit: Int = 20) async throws -> [BenevolenceRequest] {
        let snap = try await db.collection("benevolence_requests")
            .whereField("status", isEqualTo: BenevolenceRequest.RequestStatus.active.rawValue)
            .whereField("guardianStatus", isEqualTo: BenevolenceRequest.GuardianStatus.cleared.rawValue)
            .order(by: "createdAt", descending: true)
            .limit(to: limit)
            .getDocuments()
        return snap.documents.compactMap { decode(BenevolenceRequest.self, from: $0) }
    }

    // MARK: - Giving Profile

    func fetchGivingProfile(userId: String) async throws -> GivingProfile? {
        let doc = try await db.collection("giving_profiles").document(userId).getDocument()
        guard doc.exists else { return nil }
        return decode(GivingProfile.self, from: doc)
    }

    func saveGivingProfile(_ profile: GivingProfile, userId: String) async throws {
        var data: [String: Any] = [:]
        if let encoded = try? JSONEncoder().encode(profile),
           let dict = try? JSONSerialization.jsonObject(with: encoded) as? [String: Any] {
            data = dict
        }
        data["updatedAt"] = FieldValue.serverTimestamp()
        try await db.collection("giving_profiles").document(userId).setData(data, merge: true)
    }

    // MARK: - Receipts

    func fetchReceipts(userId: String, year: Int? = nil) async throws -> [GivingReceipt] {
        var query: Query = db.collection("receipts")
            .whereField("userId", isEqualTo: userId)
            .order(by: "issuedAt", descending: true)
        if let year {
            query = query.whereField("taxYear", isEqualTo: year)
        }
        let snap = try await query.getDocuments()
        return snap.documents.compactMap { decode(GivingReceipt.self, from: $0) }
    }

    // MARK: - Annual Review

    func fetchAnnualReview(userId: String, year: Int) async throws -> GivingAnnualReview? {
        let doc = try await db.collection("annual_reviews").document("\(userId)_\(year)").getDocument()
        guard doc.exists else { return nil }
        return decode(GivingAnnualReview.self, from: doc)
    }

    // MARK: - Decode Helper

    private func decode<T: Decodable>(_ type: T.Type, from document: DocumentSnapshot) -> T? {
        guard var data = document.data() else { return nil }
        data["id"] = document.documentID
        // Convert Firestore Timestamps to Date
        data = convertTimestamps(in: data)
        guard let jsonData = try? JSONSerialization.data(withJSONObject: data),
              let decoded = try? JSONDecoder().decode(type, from: jsonData) else { return nil }
        return decoded
    }

    private func convertTimestamps(in dict: [String: Any]) -> [String: Any] {
        var result = dict
        for (key, value) in result {
            if let ts = value as? Timestamp {
                result[key] = ts.dateValue().timeIntervalSince1970
            } else if let nested = value as? [String: Any] {
                result[key] = convertTimestamps(in: nested)
            } else if let array = value as? [[String: Any]] {
                result[key] = array.map { convertTimestamps(in: $0) }
            }
        }
        return result
    }
}
