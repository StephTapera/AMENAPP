//
//  SelahFunctionsService.swift
//  AMENAPP
//
//  Swift bridge to the three Selah Firebase callable functions:
//    - classifyVerseTheme
//    - bereanStudySheet
//    - classifySafety
//
//  All calls use JSONSerialization to pack the request and unpack the response,
//  keeping a clean boundary between the Codable domain model and the Firebase
//  SDK's [String: Any] wire format. Auth errors are surfaced as
//  `SelahFunctionsError.notAuthenticated`.
//

import Foundation
import FirebaseFunctions
import FirebaseAuth

// MARK: - Error

enum SelahFunctionsError: LocalizedError {
    case callFailed(String)
    case parseError(String)
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .callFailed(let message):
            return "Selah function call failed: \(message)"
        case .parseError(let detail):
            return "Selah response parse error: \(detail)"
        case .notAuthenticated:
            return "You must be signed in to use Selah AI features."
        }
    }
}

// MARK: - Service

@MainActor
final class SelahFunctionsService {

    static let shared = SelahFunctionsService()
    private let functions = Functions.functions()

    private init() {}

    // MARK: - classifyVerseTheme

    func classifyVerseTheme(
        verseId: String,
        translation: SelahTranslation,
        verseText: String
    ) async throws -> ClassifyVerseThemeResponse {
        guard Auth.auth().currentUser != nil else {
            throw SelahFunctionsError.notAuthenticated
        }

        let payload: [String: Any] = [
            "verseId": verseId,
            "translation": translation.rawValue,
            "verseText": verseText
        ]

        let result = try await callFunction(named: "classifyVerseTheme", payload: payload)
        return try decode(ClassifyVerseThemeResponse.self, from: result, function: "classifyVerseTheme")
    }

    // MARK: - bereanStudySheet

    func bereanStudySheet(
        verseId: String,
        translation: SelahTranslation,
        verseText: String
    ) async throws -> BereanStudySheetResponse {
        guard Auth.auth().currentUser != nil else {
            throw SelahFunctionsError.notAuthenticated
        }

        let payload: [String: Any] = [
            "verseId": verseId,
            "translation": translation.rawValue,
            "verseText": verseText,
            "locale": Locale.current.identifier
        ]

        let result = try await callFunction(named: "bereanStudySheet", payload: payload)
        return try decode(BereanStudySheetResponse.self, from: result, function: "bereanStudySheet")
    }

    // MARK: - classifySafety

    func classifySafety(
        reflectionText: String,
        verseId: String?
    ) async throws -> ClassifySafetyResponse {
        guard Auth.auth().currentUser != nil else {
            throw SelahFunctionsError.notAuthenticated
        }

        var payload: [String: Any] = [
            "reflectionText": reflectionText,
            "locale": Locale.current.identifier
        ]
        if let verseId {
            payload["verseId"] = verseId
        }

        let result = try await callFunction(named: "classifySafety", payload: payload)
        return try decode(ClassifySafetyResponse.self, from: result, function: "classifySafety")
    }

    // MARK: - Private Helpers

    /// Invokes a Firebase callable and returns the raw [String: Any] data.
    private func callFunction(named name: String, payload: [String: Any]) async throws -> [String: Any] {
        do {
            let callable = functions.httpsCallable(name)
            let result = try await callable.call(payload)
            guard let dict = result.data as? [String: Any] else {
                throw SelahFunctionsError.parseError("Expected [String: Any] response from \(name), got \(type(of: result.data))")
            }
            return dict
        } catch let error as SelahFunctionsError {
            throw error
        } catch {
            // Map Firebase / network errors to our typed error.
            throw SelahFunctionsError.callFailed(error.localizedDescription)
        }
    }

    /// Serializes a [String: Any] dictionary back to JSON Data and decodes it
    /// into the target Codable type. Uses ISO8601 date decoding to match
    /// the Firestore / Cloud Functions date format.
    private func decode<T: Decodable>(
        _ type: T.Type,
        from dict: [String: Any],
        function: String
    ) throws -> T {
        let data: Data
        do {
            data = try JSONSerialization.data(withJSONObject: dict, options: [])
        } catch {
            throw SelahFunctionsError.parseError("Could not serialize \(function) response to JSON: \(error.localizedDescription)")
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw SelahFunctionsError.parseError("Could not decode \(function) response as \(type): \(error.localizedDescription)")
        }
    }
}
