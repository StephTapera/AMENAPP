// ContentObjectService.swift
// AMEN App — Community Around Content OS
//
// Manages ContentObject persistence and engagement aggregation in Firestore.
// All writes are gated on the contentDetectionEngine feature flag.
//
// Firestore paths:
//   contentObjects/{contentObjectId}
//   contentEngagement/{eventId}

import Foundation
import FirebaseFirestore

// MARK: - ContentObjectService

/// Actor-isolated Firestore service for ContentObjects.
/// Checks for existing objects by rawURL before creating duplicates.
actor ContentObjectService {

    // MARK: - Constants

    private enum Collection {
        static let contentObjects = "contentObjects"
        static let contentEngagement = "contentEngagement"
    }

    /// Expected maximum engagement used to normalise communityScore.
    /// Tuned conservatively — revisit as real data accumulates.
    private let maxExpectedEngagement: Double = 500.0

    // MARK: - Private

    private let db: Firestore

    // MARK: - Init

    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }

    // MARK: - Public API

    /// Returns an existing ContentObject whose `rawURL` matches, or creates and saves a new one.
    func fetchOrCreate(rawURL: String) async throws -> ContentObject {
        guard await CommunityOSFlagService.shared.isEnabled(.contentDetectionEngine) else {
            dlog("[ContentObjectService] contentDetectionEngine flag is OFF — aborting fetchOrCreate")
            throw ContentObjectServiceError.flagDisabled
        }

        // 1. Query for an existing document by rawURL.
        let snapshot = try await db
            .collection(Collection.contentObjects)
            .whereField("rawURL", isEqualTo: rawURL)
            .limit(to: 1)
            .getDocuments()

        if let doc = snapshot.documents.first,
           let existing = ContentObject(from: doc.data()) {
            dlog("[ContentObjectService] fetchOrCreate — found existing id=\(existing.id)")
            return existing
        }

        // 2. Detect & assemble a new ContentObject via the detection engine.
        let newObject = await ContentDetectionEngine.shared.detect(from: rawURL)
        try await save(newObject)
        dlog("[ContentObjectService] fetchOrCreate — created new id=\(newObject.id) kind=\(newObject.kind.rawValue)")
        return newObject
    }

    /// Fetches a single ContentObject by its document ID. Returns nil if not found.
    func fetch(id: String) async throws -> ContentObject? {
        guard await CommunityOSFlagService.shared.isEnabled(.contentDetectionEngine) else {
            dlog("[ContentObjectService] contentDetectionEngine flag is OFF — aborting fetch")
            throw ContentObjectServiceError.flagDisabled
        }

        let doc = try await db
            .collection(Collection.contentObjects)
            .document(id)
            .getDocument()

        guard doc.exists, let data = doc.data() else {
            dlog("[ContentObjectService] fetch — document \(id) not found")
            return nil
        }

        return ContentObject(from: data)
    }

    /// Persists a ContentObject to Firestore (merge strategy — safe for create and update).
    func save(_ object: ContentObject) async throws {
        guard await CommunityOSFlagService.shared.isEnabled(.contentDetectionEngine) else {
            dlog("[ContentObjectService] contentDetectionEngine flag is OFF — aborting save")
            throw ContentObjectServiceError.flagDisabled
        }

        var data = object.toFirestoreData()
        data["updatedAt"] = Timestamp(date: Date())

        try await db
            .collection(Collection.contentObjects)
            .document(object.id)
            .setData(data, merge: true)

        dlog("[ContentObjectService] save — id=\(object.id)")
    }

    /// Atomically increments the appropriate engagement counter and recomputes communityScore.
    func recordEngagement(
        contentObjectId: String,
        eventType: ContentEngagementEventType,
        userId: String
    ) async throws {
        guard await CommunityOSFlagService.shared.isEnabled(.contentDetectionEngine) else {
            dlog("[ContentObjectService] contentDetectionEngine flag is OFF — aborting recordEngagement")
            throw ContentObjectServiceError.flagDisabled
        }

        let ref = db.collection(Collection.contentObjects).document(contentObjectId)

        // Determine which counter field to increment.
        let counterField: String?
        switch eventType {
        case .discussed:        counterField = "discussionCount"
        case .prayed:           counterField = "prayerCount"
        case .testified:        counterField = "testimonyCount"
        case .spaceJoined, .spaceCreated: counterField = "spaceCount"
        default:                counterField = nil
        }

        // Read current counts to recompute communityScore.
        let snapshot = try await ref.getDocument()
        guard let data = snapshot.data() else {
            dlog("[ContentObjectService] recordEngagement — document \(contentObjectId) not found")
            throw ContentObjectServiceError.documentNotFound(id: contentObjectId)
        }

        var discussionCount = data["discussionCount"] as? Int ?? 0
        var prayerCount     = data["prayerCount"] as? Int ?? 0
        var testimonyCount  = data["testimonyCount"] as? Int ?? 0

        if let field = counterField {
            switch field {
            case "discussionCount": discussionCount += 1
            case "prayerCount":     prayerCount += 1
            case "testimonyCount":  testimonyCount += 1
            default: break
            }
        }

        // Build a synthetic object snapshot to feed the score formula.
        let scoreProxy = ContentObject(
            kind: (data["kind"] as? String).flatMap(ContentObjectKind.init) ?? .article,
            source: .unknown,
            title: data["title"] as? String ?? "",
            rawURL: data["rawURL"] as? String ?? "",
            communityScore: 0,
            discussionCount: discussionCount,
            prayerCount: prayerCount,
            testimonyCount: testimonyCount
        )
        let newScore = computeCommunityScore(object: scoreProxy)

        var update: [String: Any] = [
            "updatedAt": Timestamp(date: Date()),
            "communityScore": newScore
        ]
        if let field = counterField {
            update[field] = FieldValue.increment(Int64(1))
        }

        try await ref.updateData(update)
        dlog("[ContentObjectService] recordEngagement — id=\(contentObjectId) event=\(eventType.rawValue) newScore=\(String(format: "%.3f", newScore))")

        // Also record the raw engagement event.
        let event = ContentEngagementEvent(
            contentObjectId: contentObjectId,
            userId: userId,
            eventType: eventType
        )
        try await ContentEngagementEventService.shared.record(event)
    }

    /// Fetches the top ContentObjects ordered by communityScore descending.
    func fetchTrending(limit: Int) async throws -> [ContentObject] {
        guard await CommunityOSFlagService.shared.isEnabled(.contentDetectionEngine) else {
            dlog("[ContentObjectService] contentDetectionEngine flag is OFF — aborting fetchTrending")
            throw ContentObjectServiceError.flagDisabled
        }

        let snapshot = try await db
            .collection(Collection.contentObjects)
            .order(by: "communityScore", descending: true)
            .limit(to: limit)
            .getDocuments()

        let results = snapshot.documents.compactMap { ContentObject(from: $0.data()) }
        dlog("[ContentObjectService] fetchTrending — returned \(results.count) of \(limit) requested")
        return results
    }

    /// Fetches ContentObjects of a specific kind, ordered by communityScore descending.
    func fetchByKind(_ kind: ContentObjectKind, limit: Int) async throws -> [ContentObject] {
        guard await CommunityOSFlagService.shared.isEnabled(.contentDetectionEngine) else {
            dlog("[ContentObjectService] contentDetectionEngine flag is OFF — aborting fetchByKind")
            throw ContentObjectServiceError.flagDisabled
        }

        let snapshot = try await db
            .collection(Collection.contentObjects)
            .whereField("kind", isEqualTo: kind.rawValue)
            .order(by: "communityScore", descending: true)
            .limit(to: limit)
            .getDocuments()

        let results = snapshot.documents.compactMap { ContentObject(from: $0.data()) }
        dlog("[ContentObjectService] fetchByKind \(kind.rawValue) — returned \(results.count)")
        return results
    }

    // MARK: - Private helpers

    /// Weighted community score formula.
    /// Returns a value clamped to [0, 1].
    private func computeCommunityScore(object: ContentObject) -> Double {
        let raw = (Double(object.discussionCount) * 0.3)
               + (Double(object.prayerCount) * 0.4)
               + (Double(object.testimonyCount) * 0.3)
        let normalized = raw / maxExpectedEngagement
        return min(max(normalized, 0.0), 1.0)
    }
}

// MARK: - ContentObjectServiceError

enum ContentObjectServiceError: LocalizedError {
    case flagDisabled
    case documentNotFound(id: String)
    case encodingFailure

    var errorDescription: String? {
        switch self {
        case .flagDisabled:
            return "Content detection is not enabled in this environment."
        case .documentNotFound(let id):
            return "ContentObject '\(id)' was not found in Firestore."
        case .encodingFailure:
            return "Failed to encode ContentObject for Firestore."
        }
    }
}

// MARK: - ContentObject + Firestore serialisation

private extension ContentObject {
    /// Converts a ContentObject to a flat [String: Any] dictionary for Firestore.
    func toFirestoreData() -> [String: Any] {
        var data: [String: Any] = [
            "id": id,
            "kind": kind.rawValue,
            "source": source.rawValue,
            "title": title,
            "rawURL": rawURL,
            "metadata": metadata,
            "communityScore": communityScore,
            "discussionCount": discussionCount,
            "prayerCount": prayerCount,
            "testimonyCount": testimonyCount,
            "spaceCount": spaceCount,
            "purityRating": purityRating.rawValue,
            "themes": themes,
            "linkedVerseRefs": linkedVerseRefs,
            "createdAt": Timestamp(date: createdAt),
            "updatedAt": Timestamp(date: updatedAt)
        ]
        if let subtitle = subtitle       { data["subtitle"] = subtitle }
        if let thumbnailURL = thumbnailURL { data["thumbnailURL"] = thumbnailURL }
        if let contentURL = contentURL   { data["contentURL"] = contentURL }
        return data
    }
}

// MARK: - ContentEngagementEventService

/// Actor-isolated Firestore service that records raw ContentEngagementEvent documents.
actor ContentEngagementEventService {

    static let shared = ContentEngagementEventService()

    private let db: Firestore

    private init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }

    /// Persists a ContentEngagementEvent to `contentEngagement/{eventId}` and emits a debug log.
    func record(_ event: ContentEngagementEvent) async throws {
        guard await CommunityOSFlagService.shared.isEnabled(.contentDetectionEngine) else {
            dlog("[ContentEngagementEventService] flag is OFF — skipping event record")
            return
        }

        let data: [String: Any] = [
            "id": event.id,
            "contentObjectId": event.contentObjectId,
            "userId": event.userId,
            "eventType": event.eventType.rawValue,
            "occurredAt": Timestamp(date: event.occurredAt)
        ]

        try await db
            .collection("contentEngagement")
            .document(event.id)
            .setData(data)

        dlog("[ContentEngagementEventService] recorded event=\(event.eventType.rawValue) contentObjectId=\(event.contentObjectId) userId=\(event.userId.prefix(8))…")
    }
}
