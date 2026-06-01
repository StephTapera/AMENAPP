// SelahStoryService.swift
// AMENAPP/SelahStories
//
// Phase 5 — Selah Stories
// Implements SelahStoryServiceProtocol from Phase0Contracts.swift.
// Free-tier CRUD gated by selahStories feature flag.
// Premium AI features gated by selahStoriesPremiumAI flag AND Berean subscription tier.
//
// Remote calls use Functions.callWithTimeout (30 s for AI, 15 s for data).
// All work runs on @MainActor; heavy decoding is pushed to a Task that can be
// awaited without blocking the run loop.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import Combine

// MARK: - SelahStoryService

@MainActor
final class SelahStoryService: ObservableObject, SelahStoryServiceProtocol {

    // MARK: - Singleton

    static let shared = SelahStoryService()
    private init() {}

    // MARK: - Published state

    /// Stories for the current session author (refreshed via fetchStories).
    @Published private(set) var stories: [SelahStory] = []
    @Published private(set) var isLoading = false
    @Published var lastError: String?

    // MARK: - Dependencies

    private let db         = Firestore.firestore()
    private let functions  = Functions.functions()
    private let auth       = Auth.auth()
    private var featureFlags: AMENFeatureFlags { AMENFeatureFlags.shared }
    private var subscription: AmenSubscriptionService { AmenSubscriptionService.shared }

    // MARK: - SelahStoryServiceProtocol: CRUD

    /// Creates a new story in Firestore and returns the generated storyId.
    /// Guard: selahStories flag must be ON; audience must be set (no nil case possible
    /// since StoryAudience has no "everyone" case by contract).
    func create(_ story: SelahStory) async throws -> String {
        guard featureFlags.selahStories else {
            throw SelahStoryError.featureDisabled
        }
        guard auth.currentUser != nil else {
            throw SelahStoryError.notAuthenticated
        }

        isLoading = true
        defer { isLoading = false }

        let payload = try encodeStoryForFirestore(story)

        let result = try await functions.callWithTimeout(
            "createSelahStory",
            data: payload,
            timeout: 15
        )

        guard let data = result.data as? [String: Any],
              let storyId = data["storyId"] as? String else {
            throw SelahStoryError.invalidResponse
        }
        return storyId
    }

    /// Fetches active (non-expired) stories for the given userId.
    func fetchStories(for userId: String) async throws -> [SelahStory] {
        guard featureFlags.selahStories else {
            throw SelahStoryError.featureDisabled
        }

        isLoading = true
        defer { isLoading = false }

        let now = Date()
        let snap = try await db
            .collection("selahStories")
            .whereField("ownerUid", isEqualTo: userId)
            .whereField("expiresAt", isGreaterThan: Timestamp(date: now))
            .order(by: "expiresAt", descending: false)
            .getDocuments()

        let decoded: [SelahStory] = snap.documents.compactMap { doc in
            decodeStoryDocument(doc)
        }
        stories = decoded
        return decoded
    }

    /// Deletes a story by its Firestore document ID.
    func delete(storyId: String) async throws {
        guard featureFlags.selahStories else {
            throw SelahStoryError.featureDisabled
        }
        guard auth.currentUser != nil else {
            throw SelahStoryError.notAuthenticated
        }

        _ = try await functions.callWithTimeout(
            "deleteSelahStory",
            data: ["storyId": storyId],
            timeout: 15
        )
        stories.removeAll { $0.id == storyId }
    }

    // MARK: - SelahStoryServiceProtocol: Premium AI

    /// Recognizes a scripture reference from a captured image.
    /// Requires selahStoriesPremiumAI flag AND Berean-tier subscription.
    func recognizeVerse(from imageData: Data) async throws -> ScriptureRef? {
        try assertPremiumAI()

        let base64 = imageData.base64EncodedString()
        let result = try await functions.callWithTimeout(
            "selahRecognizeVerse",
            data: ["imageBase64": base64],
            timeout: 30
        )

        guard let data = result.data as? [String: Any] else { return nil }
        return try decodeScriptureRef(from: data)
    }

    /// Generates a short reflection prompt grounded in the given scripture reference.
    func generateReflectionPrompt(for ref: ScriptureRef) async throws -> String {
        try assertPremiumAI()

        let payload: [String: Any] = [
            "book": ref.book,
            "chapter": ref.chapter,
            "verse": ref.verse as Any,
            "endVerse": ref.endVerse as Any
        ]
        let result = try await functions.callWithTimeout(
            "selahGenerateReflectionPrompt",
            data: payload,
            timeout: 30
        )

        guard let data = result.data as? [String: Any],
              let prompt = data["prompt"] as? String else {
            throw SelahStoryError.invalidResponse
        }
        return prompt
    }

    /// Recommends ambient/worship audio that complements the scripture and liturgical season.
    func matchAudio(for ref: ScriptureRef, season: LiturgicalSeasonKind?) async throws -> StoryAudio? {
        try assertPremiumAI()

        var payload: [String: Any] = [
            "book": ref.book,
            "chapter": ref.chapter
        ]
        if let season { payload["season"] = season.rawValue }

        let result = try await functions.callWithTimeout(
            "selahMatchAudio",
            data: payload,
            timeout: 30
        )

        guard let data = result.data as? [String: Any] else { return nil }
        return try decodeStoryAudio(from: data)
    }

    // MARK: - Private helpers

    /// Throws unless both the premiumAI flag is ON and the user holds at least the Berean tier.
    @discardableResult
    private func assertPremiumAI() throws -> Void {
        guard featureFlags.selahStoriesPremiumAI else {
            throw SelahStoryError.premiumFeatureDisabled
        }
        guard subscription.tier >= .berean else {
            throw SelahStoryError.insufficientSubscription
        }
    }

    private func encodeStoryForFirestore(_ story: SelahStory) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(story)
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SelahStoryError.encodingFailed
        }
        return dict
    }

    private func decodeStoryDocument(_ doc: QueryDocumentSnapshot) -> SelahStory? {
        var dict = doc.data()
        dict["id"] = doc.documentID
        // Convert Firestore Timestamps to ISO8601 seconds for JSONDecoder.
        if let ts = dict["createdAt"] as? Timestamp {
            dict["createdAt"] = ts.seconds
        }
        if let ts = dict["expiresAt"] as? Timestamp {
            dict["expiresAt"] = ts.seconds
        }
        guard let jsonData = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(SelahStory.self, from: jsonData)
    }

    private func decodeScriptureRef(from dict: [String: Any]) throws -> ScriptureRef? {
        guard let book = dict["book"] as? String,
              let chapter = dict["chapter"] as? Int else { return nil }
        let verse    = dict["verse"] as? Int
        let endVerse = dict["endVerse"] as? Int
        return ScriptureRef(book: book, chapter: chapter, verse: verse, endVerse: endVerse)
    }

    private func decodeStoryAudio(from dict: [String: Any]) throws -> StoryAudio? {
        guard let id       = dict["id"]       as? String,
              let title    = dict["title"]    as? String,
              let url      = dict["url"]      as? String,
              let duration = dict["durationSeconds"] as? Double else { return nil }
        let artist = dict["artistName"] as? String
        return StoryAudio(id: id, title: title, artistName: artist, url: url, durationSeconds: duration)
    }
}

// MARK: - SelahStoryError

enum SelahStoryError: LocalizedError {
    case featureDisabled
    case premiumFeatureDisabled
    case insufficientSubscription
    case notAuthenticated
    case invalidResponse
    case encodingFailed
    case audienceRequired

    var errorDescription: String? {
        switch self {
        case .featureDisabled:
            return "Selah Stories is not available yet."
        case .premiumFeatureDisabled:
            return "This AI feature is not enabled."
        case .insufficientSubscription:
            return "Upgrade to Berean to unlock verse recognition, reflection prompts, and audio matching."
        case .notAuthenticated:
            return "Please sign in to create a story."
        case .invalidResponse:
            return "Unexpected response from the server."
        case .encodingFailed:
            return "Could not prepare your story for upload."
        case .audienceRequired:
            return "Please choose who can see this story before posting."
        }
    }
}

// MARK: - Reaction model (author-private)

/// Private reaction record stored under selahStories/{id}/reactions/{uid}.
/// The public view never exposes counts — only the author can read their own.
struct SelahStoryReaction: Identifiable, Codable {
    let id: String           // reaction doc ID
    let reactorUid: String
    let kind: SelahReactionKind
    let createdAt: Date
}

enum SelahReactionKind: String, Codable, CaseIterable {
    case amen    // hands raised  ✋
    case praying // praying hands 🙏
}
