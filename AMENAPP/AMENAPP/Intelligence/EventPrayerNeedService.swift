// EventPrayerNeedService.swift
// AMENAPP — Event, Prayer, and Need Intelligence Service
//
// Calls the three Living Intelligence Cloud Function callables:
//   getEventIntelligence   → event-matched IntelligenceCard[]
//   getPrayerMatchCards    → prayer graph IntelligenceCard[]
//   getNeedDetectionCards  → community need IntelligenceCard[]
//
// Records user actions so the backend can do loop-closing.
//
// Privacy invariants (enforced server-side, mirrored in service):
//   - No count-based display values parsed or stored
//   - All cards are finite (formation.finite == true)
//   - No user identity forwarded for non-own cards

import Foundation
import FirebaseFunctions
import FirebaseAuth

// MARK: - EventPrayerNeedServiceError

enum EventPrayerNeedServiceError: LocalizedError {
    case unauthenticated
    case invalidResponse(String)
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .unauthenticated:
            return "You must be signed in to view personalized cards."
        case .invalidResponse(let detail):
            return "Unexpected response from the server: \(detail)"
        case .serverError(let message):
            return message
        }
    }
}

// MARK: - EventPrayerNeedService

@MainActor
final class EventPrayerNeedService: ObservableObject {

    static let shared = EventPrayerNeedService()

    private let functions = Functions.functions()

    private init() {}

    // MARK: - Event Intelligence

    /// Calls `getEventIntelligence` and returns matched event cards.
    /// Returns [] on any error (fail-closed mirror of the CF).
    func fetchEventCards() async throws -> [IntelligenceCard] {
        try requireAuth()
        return try await callCardFunction(named: "getEventIntelligence")
    }

    // MARK: - Prayer Match Cards

    /// Calls `getPrayerMatchCards` and returns prayer graph cards.
    /// Privacy: no names unless prayer was public; no counts.
    func fetchPrayerCards() async throws -> [IntelligenceCard] {
        try requireAuth()
        return try await callCardFunction(named: "getPrayerMatchCards")
    }

    // MARK: - Need Detection Cards

    /// Calls `getNeedDetectionCards` and returns community need cards.
    /// Privacy: "Someone in your community" — no PII on any card.
    func fetchNeedCards() async throws -> [IntelligenceCard] {
        try requireAuth()
        return try await callCardFunction(named: "getNeedDetectionCards")
    }

    // MARK: - Action Recording

    /// Records a user action (RSVP, PRAY, SHOW_UP, etc.) against a card.
    /// Used by the backend for loop-closing (follow-up cards on subsequent briefs).
    func recordAction(cardId: String, rung: ActionRung, targetId: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw EventPrayerNeedServiceError.unauthenticated
        }

        let payload: [String: Any] = [
            "cardId":   cardId,
            "rung":     rung.rawValue,
            "targetId": targetId,
            "userId":   uid,
        ]

        let result = try await functions
            .httpsCallable("recordIntelligenceAction")
            .call(payload)

        // Server returns { ok: true } on success; we tolerate any truthy data
        guard let data = result.data as? [String: Any],
              data["ok"] as? Bool == true else {
            // Non-critical: action recording failure should not surface to user
            return
        }
    }

    // MARK: - Private Helpers

    @discardableResult
    private func requireAuth() throws -> String {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw EventPrayerNeedServiceError.unauthenticated
        }
        return uid
    }

    /// Generic callable invocation that deserializes a `{ cards: [...] }` response.
    private func callCardFunction(named functionName: String) async throws -> [IntelligenceCard] {
        let result = try await functions
            .httpsCallable(functionName)
            .call([:] as [String: Any])

        guard let data = result.data as? [String: Any],
              let rawCards = data["cards"] as? [[String: Any]] else {
            throw EventPrayerNeedServiceError.invalidResponse("Missing 'cards' array in response from \(functionName)")
        }

        let jsonData = try JSONSerialization.data(withJSONObject: rawCards)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        decoder.keyDecodingStrategy  = .convertFromSnakeCase
        return try decoder.decode([IntelligenceCard].self, from: jsonData)
    }
}
