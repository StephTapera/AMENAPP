// FaithIntelService.swift
// AMEN Universal Accessibility Engine — A6 Faith Intelligence
// Detects and surfaces scripture references. NEVER generates or fabricates verse text.

import Foundation
import FirebaseFunctions
import FirebaseAuth

// MARK: - CodableNSRange

struct CodableNSRange: Codable {
    let location: Int
    let length: Int
    var nsRange: NSRange { NSRange(location: location, length: length) }
}

// MARK: - Models

struct FaithIntelScriptureRef: Codable {
    let rawReference: String      // e.g. "John 3:16" or "the 23rd Psalm"
    let canonicalRef: String      // e.g. "John 3:16 (NIV)"
    let verseText: String
    let book: String
    let chapter: Int
    let verse: Int
    let range: CodableNSRange?    // character range in source text; optional
}

struct FaithIntelResult: Codable {
    let sourceText: String
    let detectedRefs: [FaithIntelScriptureRef]
    let relatedPassages: [FaithIntelScriptureRef]
    let aiContribution: C2PAAIContribution
}

// MARK: - Actor

actor FaithIntelService {

    static let shared = FaithIntelService()

    private let functions = Functions.functions()

    private init() {}

    // MARK: - Detect Scripture

    /// Scans `text` for scripture references and returns resolved refs with verse text.
    /// This service NEVER fabricates verse text — all verse content comes from the proxy.
    func detectScripture(in text: String) async throws -> FaithIntelResult {

        let flags = await TrustAccessibilityFeatureFlags.shared.a11yFaithIntelEnabled
        guard flags else {
            throw FaithIntelError.featureDisabled
        }

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FaithIntelError.emptyInput
        }

        let params: [String: Any] = ["text": text]

        let result: HTTPSCallableResult
        do {
            result = try await functions
                .httpsCallable(TrustA11yCallable.scriptureResolveProxy.rawValue)
                .call(params)
        } catch let error as NSError {
            throw FaithIntelError.from(error)
        }

        guard let data = result.data as? [String: Any] else {
            throw FaithIntelError.malformedResponse("Top-level data was not a dictionary")
        }

        let jobId = data["jobId"] as? String ?? UUID().uuidString
        let model = data["model"] as? String ?? "unknown"

        let detectedRefs   = parseRefs(from: data["detectedRefs"])
        let relatedPassages = parseRefs(from: data["relatedPassages"])

        let contribution = C2PAAIContribution(
            type: .scriptureDetect,
            model: model,
            jobId: jobId,
            timestamp: Date(),
            humanEdited: false
        )

        return FaithIntelResult(
            sourceText: text,
            detectedRefs: detectedRefs,
            relatedPassages: relatedPassages,
            aiContribution: contribution
        )
    }

    // MARK: - Resolve Single Reference

    /// Resolves a single raw scripture reference string (e.g. "John 3:16") to a `FaithIntelScriptureRef`.
    /// Returns nil if the proxy cannot resolve the reference.
    func resolveReference(_ rawRef: String) async throws -> FaithIntelScriptureRef? {
        guard !rawRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let params: [String: Any] = ["singleRef": rawRef]

        let result: HTTPSCallableResult
        do {
            result = try await functions
                .httpsCallable(TrustA11yCallable.scriptureResolveProxy.rawValue)
                .call(params)
        } catch let error as NSError {
            throw FaithIntelError.from(error)
        }

        guard let data = result.data as? [String: Any] else {
            return nil
        }

        // Single-ref response: the top-level dict IS the ref, or it may be under "ref"
        let refDict: [String: Any]
        if let nested = data["ref"] as? [String: Any] {
            refDict = nested
        } else {
            refDict = data
        }

        return parseRef(from: refDict)
    }

    // MARK: - Private Parsing Helpers

    private func parseRefs(from value: Any?) -> [FaithIntelScriptureRef] {
        guard let array = value as? [[String: Any]] else { return [] }
        return array.compactMap { parseRef(from: $0) }
    }

    private func parseRef(from dict: [String: Any]) -> FaithIntelScriptureRef? {
        guard
            let rawReference  = dict["rawReference"]  as? String,
            let canonicalRef  = dict["canonicalRef"]  as? String,
            let verseText     = dict["verseText"]      as? String,
            let book          = dict["book"]           as? String,
            let chapter       = dict["chapter"]        as? Int,
            let verse         = dict["verse"]          as? Int
        else { return nil }

        var codableRange: CodableNSRange?
        if
            let rangeDict = dict["range"] as? [String: Any],
            let location  = rangeDict["location"] as? Int,
            let length    = rangeDict["length"]   as? Int
        {
            codableRange = CodableNSRange(location: location, length: length)
        }

        return FaithIntelScriptureRef(
            rawReference: rawReference,
            canonicalRef: canonicalRef,
            verseText: verseText,
            book: book,
            chapter: chapter,
            verse: verse,
            range: codableRange
        )
    }
}

// MARK: - Error

enum FaithIntelError: LocalizedError {
    case featureDisabled
    case emptyInput
    case malformedResponse(String)
    case cloudFunctionError(String)
    case unknown

    var errorDescription: String? {
        switch self {
        case .featureDisabled:
            return "Scripture detection is not available right now."
        case .emptyInput:
            return "There is no text to scan for scripture references."
        case .malformedResponse(let detail):
            return "We received an unexpected response from the server. (\(detail))"
        case .cloudFunctionError(let message):
            return message
        case .unknown:
            return "Something went wrong. Please try again."
        }
    }

    static func from(_ error: NSError) -> FaithIntelError {
        if error.domain == FunctionsErrorDomain {
            let code = FunctionsErrorCode(rawValue: error.code)
            switch code {
            case .resourceExhausted:
                return .cloudFunctionError("You have reached the scripture lookup limit. Please try again later.")
            case .unauthenticated:
                return .cloudFunctionError("Please sign in to use scripture detection.")
            case .permissionDenied:
                return .cloudFunctionError("You don't have permission to use this feature.")
            case .unavailable:
                return .cloudFunctionError("The scripture service is temporarily unavailable.")
            default:
                let message = error.localizedDescription
                return .cloudFunctionError(message.isEmpty ? "An error occurred." : message)
            }
        }
        return .unknown
    }
}
