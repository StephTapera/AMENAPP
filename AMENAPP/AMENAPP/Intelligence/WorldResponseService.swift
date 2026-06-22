// WorldResponseService.swift
// AMENAPP — World Events as Christian Response: Service layer
//
// Fetches GLOBAL IntelligenceCards from the `getWorldResponseCards` Cloud Function.
// All card content is server-computed from admin-curated events — never fabricated on client.
//
// Usage:
//   let service = WorldResponseService.shared
//   let cards = try await service.fetchWorldResponseCards()

import Foundation
import FirebaseFunctions

// MARK: - WorldResponseServiceError

enum WorldResponseServiceError: LocalizedError {
    case invalidResponse
    case unauthenticated

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Received an unexpected response from the server."
        case .unauthenticated:
            return "You must be signed in to view world response cards."
        }
    }
}

// MARK: - WorldResponseService

@MainActor
final class WorldResponseService: ObservableObject {

    static let shared = WorldResponseService()

    private let functions = Functions.functions()

    private init() {}

    // MARK: - fetchWorldResponseCards

    /// Fetches GLOBAL IntelligenceCards for the authenticated user.
    ///
    /// - Returns: An array of IntelligenceCard values with tier == .global.
    ///   Returns [] if the queue is empty or AI processing skipped all events.
    ///
    /// - Throws: WorldResponseServiceError on invalid server response.
    ///   The Cloud Function itself is fail-closed and returns [] rather than erroring,
    ///   so throws here only indicate a wire-format problem.
    func fetchWorldResponseCards() async throws -> [IntelligenceCard] {
        let result = try await functions
            .httpsCallable("getWorldResponseCards")
            .call([:])

        guard let raw = result.data as? [String: Any] else {
            throw WorldResponseServiceError.invalidResponse
        }

        guard let rawCards = raw["cards"] as? [[String: Any]] else {
            // "cards" key absent or wrong type — treat as empty, not an error
            return []
        }

        if rawCards.isEmpty {
            return []
        }

        return try decodeCards(rawCards)
    }

    // MARK: - Private helpers

    private func decodeCards(_ rawCards: [[String: Any]]) throws -> [IntelligenceCard] {
        let jsonData = try JSONSerialization.data(withJSONObject: rawCards)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        decoder.keyDecodingStrategy  = .convertFromSnakeCase
        return try decoder.decode([IntelligenceCard].self, from: jsonData)
    }
}
