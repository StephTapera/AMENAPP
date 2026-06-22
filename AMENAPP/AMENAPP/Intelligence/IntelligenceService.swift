// IntelligenceService.swift — AMEN Living Intelligence
// Calls Firebase Cloud Functions to fetch and record intelligence briefs.
// All errors are typed; callers can pattern-match on IntelligenceServiceError.

import Foundation
import FirebaseFunctions
import FirebaseAuth

// MARK: - Errors

enum IntelligenceServiceError: LocalizedError {
    case unauthenticated
    case invalidResponse
    case serverError(String)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .unauthenticated:
            return "You must be signed in to load your brief."
        case .invalidResponse:
            return "Received an unexpected response from the server."
        case .serverError(let msg):
            return msg
        case .networkError(let err):
            return "Network error: \(err.localizedDescription)"
        }
    }
}

// MARK: - IntelligenceService

@MainActor
final class IntelligenceService: ObservableObject {
    static let shared = IntelligenceService()

    private let functions = Functions.functions()
    private init() {}

    // MARK: - Fetch Brief

    /// Calls the `getIntelligenceBrief` CF callable and decodes the result.
    /// The CF generates a fresh brief server-side on each invocation.
    func fetchBrief() async throws -> IntelligenceBrief {
        guard Auth.auth().currentUser != nil else {
            throw IntelligenceServiceError.unauthenticated
        }

        let callable = functions.httpsCallable("getIntelligenceBrief")

        do {
            let result = try await callable.call([:] as [String: Any])

            guard let raw = result.data as? [String: Any] else {
                throw IntelligenceServiceError.invalidResponse
            }

            return try decodeBrief(from: raw)

        } catch let error as IntelligenceServiceError {
            throw error
        } catch let nsError as NSError where nsError.domain == FunctionsErrorDomain {
            let msg = nsError.localizedDescription
            // Map common CF error codes to user-friendly messages
            if nsError.code == FunctionsErrorCode.unauthenticated.rawValue {
                throw IntelligenceServiceError.unauthenticated
            }
            throw IntelligenceServiceError.serverError(msg)
        } catch {
            throw IntelligenceServiceError.networkError(error)
        }
    }

    // MARK: - Record Action

    /// Calls the `recordIntelligenceAction` CF callable to persist user engagement.
    /// Non-critical — callers should not block on this; failures are surfaced but not fatal.
    func recordAction(cardId: String, rung: ActionRung, targetId: String) async throws {
        guard Auth.auth().currentUser != nil else {
            throw IntelligenceServiceError.unauthenticated
        }

        let payload: [String: Any] = [
            "cardId": cardId,
            "rung": rung.rawValue,
            "targetId": targetId,
        ]

        let callable = functions.httpsCallable("recordIntelligenceAction")

        do {
            _ = try await callable.call(payload)
        } catch let nsError as NSError where nsError.domain == FunctionsErrorDomain {
            throw IntelligenceServiceError.serverError(nsError.localizedDescription)
        } catch {
            throw IntelligenceServiceError.networkError(error)
        }
    }

    // MARK: - Decoding

    private func decodeBrief(from dict: [String: Any]) throws -> IntelligenceBrief {
        let jsonData = try JSONSerialization.data(withJSONObject: dict)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(IntelligenceBrief.self, from: jsonData)
    }
}
