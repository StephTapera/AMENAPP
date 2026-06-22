// BereanPersonalContextProvider.swift
// AMEN App — Retrieval over Living Memory, notes, commitments, Space history
//
// TIER P IMPOSSIBILITY:
// Private/E2EE collections are never queried — the block is at the
// collection-path level, not a post-hoc filter. The set of paths this
// class may touch is hardcoded to Tier-S and Tier-C paths only.
// Tier P paths (e.g. directMessages/{uid}/threads) are not present in
// this file and cannot be reached through this API.

import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions

// MARK: - Allowed Collection Paths (Tier S + C only)

/// Exhaustive list of Firestore paths this provider may read.
/// Private (Tier P) paths (directMessages, privateNotes, e2eeThreads) are
/// intentionally absent — adding them here requires a security review.
private enum AllowedPath {
    // Tier S — shared/public
    static func notes(_ uid: String) -> String            { "notes/\(uid)/entries" }
    static func commitments(_ uid: String) -> String      { "users/\(uid)/prayerCommitments" }
    static func spaceActivity(_ uid: String) -> String    { "users/\(uid)/spaceActivity" }
    // Tier C — connected (requires follow relationship, still not E2EE)
    static func sharedStudies(_ uid: String) -> String    { "users/\(uid)/sharedStudies" }
}

// MARK: - BereanPersonalContextProvider

@MainActor
final class BereanPersonalContextProvider: ObservableObject, BereanContextProviding {

    static let shared = BereanPersonalContextProvider()

    private let db = Firestore.firestore()

    private init() {}

    // MARK: - BereanContextProviding

    /// Retrieves personal context chunks for the current user.
    ///
    /// CRITICAL INVARIANT: `tier` MUST NOT contain a hypothetical `.private` case.
    /// `ContentTierFilter` deliberately has no `.private` member — this function
    /// enforces the impossibility at the query level by only targeting paths
    /// in `AllowedPath`. No post-hoc filtering of results is sufficient on its own;
    /// this is an architectural guarantee.
    func retrieveContext(
        query: String,
        tier: ContentTierFilter,
        limit: Int
    ) async throws -> [ProvenanceTaggedChunk] {

        // Feature flag gate
        guard AMENFeatureFlags.shared.bereanPersonalContext else { return [] }

        guard let uid = Auth.auth().currentUser?.uid else { return [] }

        var chunks: [ProvenanceTaggedChunk] = []

        // --- Tier S paths ---
        if tier.contains(.shared) {
            let noteChunks = try await fetchNotes(uid: uid, limit: limit)
            chunks.append(contentsOf: noteChunks)

            let commitmentChunks = try await fetchCommitments(uid: uid, limit: limit)
            chunks.append(contentsOf: commitmentChunks)
        }

        // --- Tier C paths ---
        if tier.contains(.connected) {
            let spaceChunks = try await fetchSpaceActivity(uid: uid, limit: limit)
            chunks.append(contentsOf: spaceChunks)

            let studyChunks = try await fetchSharedStudies(uid: uid, limit: limit)
            chunks.append(contentsOf: studyChunks)
        }

        // Defensive assertion: no Tier P should ever exist given path restrictions
        // This is belt-and-suspenders only — the impossibility is at query level.
        let sanitized = chunks.filter { $0.tier != "P" }
        return Array(sanitized.prefix(limit))
    }

    // MARK: - Private Fetchers (Tier S)

    private func fetchNotes(uid: String, limit: Int) async throws -> [ProvenanceTaggedChunk] {
        let snapshot = try await db
            .collection(AllowedPath.notes(uid))
            .order(by: "createdAt", descending: true)
            .limit(to: min(limit, 20))
            .getDocuments()

        return snapshot.documents.compactMap { doc in
            guard let text = doc["text"] as? String,
                  let ts = (doc["createdAt"] as? Timestamp)?.dateValue() else { return nil }
            let label = humanLabel(for: ts, prefix: "your note from")
            return ProvenanceTaggedChunk(
                content: text,
                source: "notes",
                tier: "S",
                timestamp: ts,
                humanLabel: label
            )
        }
    }

    private func fetchCommitments(uid: String, limit: Int) async throws -> [ProvenanceTaggedChunk] {
        let snapshot = try await db
            .collection(AllowedPath.commitments(uid))
            .order(by: "createdAt", descending: true)
            .limit(to: min(limit, 10))
            .getDocuments()

        return snapshot.documents.compactMap { doc in
            guard let text = doc["commitmentText"] as? String,
                  let ts = (doc["createdAt"] as? Timestamp)?.dateValue() else { return nil }
            let subject = doc["subject"] as? String
            let label = subject.map { "your commitment to pray for \($0)" }
                        ?? humanLabel(for: ts, prefix: "your prayer commitment from")
            return ProvenanceTaggedChunk(
                content: text,
                source: "commitments",
                tier: "S",
                timestamp: ts,
                humanLabel: label
            )
        }
    }

    // MARK: - Private Fetchers (Tier C)

    private func fetchSpaceActivity(uid: String, limit: Int) async throws -> [ProvenanceTaggedChunk] {
        let snapshot = try await db
            .collection(AllowedPath.spaceActivity(uid))
            .order(by: "joinedAt", descending: true)
            .limit(to: min(limit, 10))
            .getDocuments()

        return snapshot.documents.compactMap { doc in
            guard let spaceName = doc["spaceName"] as? String,
                  let ts = (doc["joinedAt"] as? Timestamp)?.dateValue() else { return nil }
            let label = "your activity in \(spaceName)"
            let content = doc["summary"] as? String ?? spaceName
            return ProvenanceTaggedChunk(
                content: content,
                source: "space_history",
                tier: "C",
                timestamp: ts,
                humanLabel: label
            )
        }
    }

    private func fetchSharedStudies(uid: String, limit: Int) async throws -> [ProvenanceTaggedChunk] {
        let snapshot = try await db
            .collection(AllowedPath.sharedStudies(uid))
            .order(by: "updatedAt", descending: true)
            .limit(to: min(limit, 10))
            .getDocuments()

        return snapshot.documents.compactMap { doc in
            guard let topic = doc["topic"] as? String,
                  let ts = (doc["updatedAt"] as? Timestamp)?.dateValue() else { return nil }
            let ref = doc["scriptureRef"] as? String
            let label = ref.map { "your study on \($0)" }
                        ?? humanLabel(for: ts, prefix: "your study from")
            let content = doc["summary"] as? String ?? topic
            return ProvenanceTaggedChunk(
                content: content,
                source: "shared_studies",
                tier: "C",
                timestamp: ts,
                humanLabel: label
            )
        }
    }

    // MARK: - Helpers

    private func humanLabel(for date: Date, prefix: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d"
        return "\(prefix) \(formatter.string(from: date))"
    }
}
