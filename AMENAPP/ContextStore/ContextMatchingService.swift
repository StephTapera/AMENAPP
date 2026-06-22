// ContextMatchingService.swift
// AMEN Universal Migration & Context System — Wave 4 (matching-engineer)
//
// CLIENT façade for `matchCommunitiesFromContext` — the Wave-4 CONSUMER that turns a user's
// already-approved Tier-C context facets into community matches (groups, Spaces, events,
// volunteer opportunities), each with a human "Why this community fits you" explanation.
//
// This REUSES the Find-a-Church matching pattern (ChurchMatcherService): the explanation is a
// FIT reason, never a score. There is NO numeric person score anywhere here — by contract §9
// (no spiritual ranking).
//
// HARD INVARIANTS honored here:
//   • Flag-gated on `contextSystemEnabled && contextMatchingEnabled` (both must be true).
//   • The CF reads ONLY the owner's OWN Tier-C facets server-side (never Tier P, faith only
//     after consent). This client never sends facet values — it sends only `{ minor }`.
//   • C60: the client resolves minor-or-unknown status (fail closed to minor) via
//     MinorSafetyService and passes it as `minor`. The SERVER then routes minors to youth-safe
//     community indexes (authoritative C60 gate). We never trust the client to relax this.
//   • App Check + Auth are enforced by the callable itself (enforceAppCheck: true).

import Foundation
import FirebaseAuth
import FirebaseFunctions

// MARK: - Match model (mirrors the CF output { id, type, explanation })

/// One matched community. `explanation` is a FIT reason ("Why this community fits you"),
/// never a score — matching the ChurchMatch.explanation pattern.
struct ContextCommunityMatch: Identifiable, Equatable, Codable {

    /// The community types the matcher spans.
    enum MatchType: String, Codable, CaseIterable {
        case group
        case space
        case event
        case volunteer

        /// Human label for the chip on the match card.
        var displayName: String {
            switch self {
            case .group:     return "Group"
            case .space:     return "Space"
            case .event:     return "Event"
            case .volunteer: return "Volunteer"
            }
        }

        /// SF Symbol used on the match card.
        var symbol: String {
            switch self {
            case .group:     return "person.3.fill"
            case .space:     return "bubble.left.and.bubble.right.fill"
            case .event:     return "calendar"
            case .volunteer: return "hands.and.sparkles.fill"
            }
        }
    }

    let id: String
    let type: MatchType
    /// The "Why this community fits you" sentence. A reason, never a score.
    let explanation: String
}

// MARK: - Errors

enum ContextMatchingError: LocalizedError, Equatable {
    case matchingDisabled
    case notSignedIn
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .matchingDisabled:
            return "Context matching is turned off (contextSystemEnabled && contextMatchingEnabled)."
        case .notSignedIn:
            return "No signed-in user; cannot match communities from context."
        case .invalidResponse:
            return "The matching service returned an invalid response."
        }
    }
}

// MARK: - ContextMatchingService

/// Calls `matchCommunitiesFromContext` and publishes the resulting matches. Holds NO facet
/// values — the server reads them; this service only ferries `{ minor }` out and matches back.
@MainActor
final class ContextMatchingService: ObservableObject {

    static let shared = ContextMatchingService()

    @Published private(set) var matches: [ContextCommunityMatch] = []
    @Published private(set) var isMatching = false
    @Published private(set) var lastError: String?

    private let functions: Functions

    init(functions: Functions = Functions.functions()) {
        self.functions = functions
    }

    // MARK: - Public API

    /// Fetch community matches for the current user from their server-side Tier-C facets.
    /// Resolves minor-or-unknown status (fail closed to minor) and passes it to the CF, which
    /// is the authoritative C60 gate that routes minors to youth-safe community indexes.
    @discardableResult
    func refreshMatches() async throws -> [ContextCommunityMatch] {
        // Both flags must be true (master + feature).
        guard AMENFeatureFlags.shared.contextSystemEnabled,
              AMENFeatureFlags.shared.contextMatchingEnabled else {
            throw ContextMatchingError.matchingDisabled
        }
        guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else {
            throw ContextMatchingError.notSignedIn
        }

        isMatching = true
        lastError = nil
        defer { isMatching = false }

        // C60 — resolve minor-or-unknown (defaults to minor if unknown). The SERVER re-decides
        // authoritatively; this client value can only ever ask for the more-restrictive path.
        let minor = await MinorSafetyService.shared.recipientIsMinorOrUnknown(uid)

        do {
            let result = try await callMatch(minor: minor)
            matches = result
            return result
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    // MARK: - Cloud Function call

    /// Calls `matchCommunitiesFromContext` ({ minor } → { matches: [{id, type, explanation}] }).
    private func callMatch(minor: Bool) async throws -> [ContextCommunityMatch] {
        let callable = functions.httpsCallable("matchCommunitiesFromContext")
        let result = try await callable.call(["minor": minor])

        guard let payload = result.data as? [String: Any] else {
            throw ContextMatchingError.invalidResponse
        }
        guard let rawArray = payload["matches"] as? [[String: Any]] else {
            // A well-formed empty response is allowed (no candidates / no facets yet).
            return []
        }

        return rawArray.compactMap { raw -> ContextCommunityMatch? in
            guard let id = raw["id"] as? String, !id.isEmpty,
                  let typeRaw = raw["type"] as? String,
                  let type = ContextCommunityMatch.MatchType(rawValue: typeRaw),
                  let explanation = raw["explanation"] as? String else {
                return nil
            }
            return ContextCommunityMatch(id: id, type: type, explanation: explanation)
        }
    }
}
