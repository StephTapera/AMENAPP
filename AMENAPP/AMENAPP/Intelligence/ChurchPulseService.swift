// ChurchPulseService.swift
// AMENAPP — Church Pulse Service
//
// Fetches church pulse data via the `getChurchPulse` Firebase callable.
// All data is server-computed from real Firestore signals — never fabricated on client.
//
// Usage:
//   let pulse = try await ChurchPulseService.shared.fetchPulse(for: churchId)

import Foundation
import FirebaseFunctions

// MARK: - ChurchPulseServiceError

enum ChurchPulseServiceError: LocalizedError {
    case invalidResponse
    case serverError(String)
    case unauthenticated
    case notAMember

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Received an unexpected response from the server."
        case .serverError(let m):
            return m
        case .unauthenticated:
            return "You must be signed in to view church pulse."
        case .notAMember:
            return "You must be a member of this church to view its pulse."
        }
    }
}

// MARK: - ChurchPulseService

/// Singleton service that calls the `getChurchPulse` callable and decodes
/// the result into a `ChurchPulse` value.
///
/// The callable verifies church membership, applies a 6-hour cache,
/// and always derives data from real Firestore documents.
@MainActor
final class ChurchPulseService: ObservableObject {

    static let shared = ChurchPulseService()

    private let functions = Functions.functions()

    private init() {}

    // MARK: - fetchPulse

    /// Returns the computed ChurchPulse for the given church.
    /// Throws `ChurchPulseServiceError` on failure.
    func fetchPulse(for churchId: String) async throws -> ChurchPulse {
        let result = try await functions
            .httpsCallable("getChurchPulse")
            .call(["churchId": churchId])

        guard let raw = result.data as? [String: Any] else {
            throw ChurchPulseServiceError.invalidResponse
        }

        return try decode(ChurchPulse.self, from: raw)
    }

    // MARK: - Private helpers

    private func decode<T: Decodable>(_ type: T.Type, from dict: [String: Any]) throws -> T {
        let jsonData = try JSONSerialization.data(withJSONObject: dict)
        return try JSONDecoder().decode(type, from: jsonData)
    }
}
