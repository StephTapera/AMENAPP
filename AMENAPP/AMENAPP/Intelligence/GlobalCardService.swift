// GlobalCardService.swift
// AMEN Living Intelligence — GLOBAL Tier
//
// Fetches GLOBAL intelligence cards from the backend via Firebase callable.
// Never returns DEVELOPING as the top card (mirrors FORMATION_INVARIANTS.DEVELOPING_NEVER_TOP).
// All Firestore reads happen server-side; this service is read-only on the client.

import Foundation
import FirebaseFirestore
import FirebaseFunctions
import FirebaseAuth

// MARK: - Errors

enum GlobalCardError: LocalizedError {
    case unauthenticated
    case networkError(Error)
    case decodingError(Error)
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .unauthenticated:
            return "Please sign in to view world events."
        case .networkError(let err):
            return "Network error: \(err.localizedDescription)"
        case .decodingError(let err):
            return "Could not parse world events: \(err.localizedDescription)"
        case .serverError(let msg):
            return msg
        }
    }
}

// MARK: - GlobalCardService

/// Fetches GLOBAL intelligence cards via the `getGlobalIntelligenceCards` callable.
/// Thread-safe: all async methods return on the calling context.
@MainActor
final class GlobalCardService: ObservableObject {
    static let shared = GlobalCardService()

    @Published var cards: [IntelligenceCard] = []
    @Published var isLoading = false
    @Published var error: GlobalCardError?

    private let functions = Functions.functions(region: "us-central1")
    private init() {}

    /// Fetches GLOBAL cards and updates `cards`. Never surfaces DEVELOPING as position 0.
    func fetchGlobalCards() async throws -> [IntelligenceCard] {
        guard Auth.auth().currentUser != nil else {
            throw GlobalCardError.unauthenticated
        }

        isLoading = true
        error = nil

        defer { isLoading = false }

        do {
            let callable = functions.httpsCallable("getGlobalIntelligenceCards")
            let result = try await callable.call([:] as [String: Any])

            guard let data = result.data as? [String: Any],
                  let rawCards = data["cards"] as? [[String: Any]] else {
                return []
            }

            let decoded = try decodeCards(from: rawCards)

            // Client-side safety net: never show DEVELOPING first
            let ranked = demoteDevelopingFromTop(decoded)
            self.cards = ranked
            return ranked

        } catch let httpsError as NSError where httpsError.domain == FunctionsErrorDomain {
            let msg = httpsError.localizedDescription
            let wrapped = GlobalCardError.serverError(msg)
            self.error = wrapped
            throw wrapped
        } catch let err as GlobalCardError {
            self.error = err
            throw err
        } catch {
            let wrapped = GlobalCardError.networkError(error)
            self.error = wrapped
            throw wrapped
        }
    }

    // MARK: - Private helpers

    private func decodeCards(from raw: [[String: Any]]) throws -> [IntelligenceCard] {
        let jsonData = try JSONSerialization.data(withJSONObject: raw)
        let decoder = JSONDecoder()
        return try decoder.decode([IntelligenceCard].self, from: jsonData)
    }

    /// Mirrors FORMATION_INVARIANTS.DEVELOPING_NEVER_TOP on the client side as a safety net.
    private func demoteDevelopingFromTop(_ cards: [IntelligenceCard]) -> [IntelligenceCard] {
        guard cards.count > 1, cards[0].truthLevel == .developing else {
            return cards
        }
        var reranked = cards
        let developingCard = reranked.removeFirst()
        if let firstNonDeveloping = reranked.firstIndex(where: { $0.truthLevel != .developing }) {
            reranked.insert(developingCard, at: firstNonDeveloping + 1)
        } else {
            reranked.append(developingCard)
        }
        return reranked
    }
}
