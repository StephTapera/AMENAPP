//
//  BereanAPIClient.swift
//  AMENAPP
//
//  Thin Swift client for the Berean Spiritual Intelligence Cloud Functions.
//  All calls proxy through Firebase Callable Functions — the API key never
//  leaves the Cloud Function environment.
//
//  Functions called:
//    - bereanGenerateStructuredResponse
//    - bereanStudyPassage
//

import Foundation
import FirebaseFunctions

@MainActor
final class BereanAPIClient {

    static let shared = BereanAPIClient()
    private let functions = Functions.functions()
    private init() {}

    // MARK: - Generate Structured Response

    /// Calls `bereanGenerateStructuredResponse` and returns a decoded
    /// `BereanStructuredResponse`. Throws on network error or API failure.
    func generateStructuredResponse(
        conversationId: String,
        userMessage: String,
        passageContext: String? = nil,
        previousMessages: [(role: String, content: String)] = []
    ) async throws -> BereanStructuredResponse {
        let historyData = previousMessages.map { ["role": $0.role, "content": $0.content] }

        var params: [String: Any] = [
            "conversationId": conversationId,
            "userMessage": userMessage,
            "previousMessages": historyData,
        ]
        if let passage = passageContext {
            params["passageContext"] = passage
        }

        let result = try await functions
            .httpsCallable("bereanGenerateStructuredResponse")
            .call(params)

        guard let data = result.data as? [String: Any] else {
            throw BereanAPIError.invalidResponse
        }

        return try decodeBereanStructuredResponse(from: data)
    }

    // MARK: - Study Passage

    /// Calls `bereanStudyPassage` and returns the full `ScripturePassagePayload`
    /// for the given reference.
    func studyPassage(
        reference: String,
        translation: String = "ESV",
        includeWordStudy: Bool = true,
        includeChristConnection: Bool = true,
        includeImmersionMode: Bool = false
    ) async throws -> ScripturePassagePayload {
        let params: [String: Any] = [
            "reference": reference,
            "translation": translation,
            "includeWordStudy": includeWordStudy,
            "includeChristConnection": includeChristConnection,
            "includeImmersionMode": includeImmersionMode,
        ]

        let result = try await functions
            .httpsCallable("bereanStudyPassage")
            .call(params)

        guard let data = result.data as? [String: Any] else {
            throw BereanAPIError.invalidResponse
        }

        return try decodeScripturePassagePayload(from: data)
    }

    // MARK: - Decoding Helpers

    private func decodeBereanStructuredResponse(
        from data: [String: Any]
    ) throws -> BereanStructuredResponse {
        let jsonData = try JSONSerialization.data(withJSONObject: data)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(BereanStructuredResponse.self, from: jsonData)
    }

    private func decodeScripturePassagePayload(
        from data: [String: Any]
    ) throws -> ScripturePassagePayload {
        let jsonData = try JSONSerialization.data(withJSONObject: data)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(ScripturePassagePayload.self, from: jsonData)
    }
}

// MARK: - Error

enum BereanAPIError: LocalizedError {
    case invalidResponse
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:          return "Berean returned an unexpected response format."
        case .decodingFailed(let msg):  return "Could not parse Berean response: \(msg)"
        }
    }
}
