// BereanPipelineClient.swift
// AMENAPP
//
// Lightweight async/await client for the Berean Constitutional Pipeline.
// This is the primary call-site entry point for every surface that needs to
// send a query through the 7-stage backend pipeline.
//
// Design invariants:
//   C-1. Feature flag "constitutionalIntelligence_enabled" is checked via Remote
//        Config before any network call. When false, BereanError.pipelineDisabled
//        is thrown immediately — no unverified content is returned.
//   C-2. The CF response is decoded via JSONDecoder with a custom date strategy
//        accepting both epoch-Double and ISO-8601 String (matches all existing
//        Berean callable patterns).
//   C-3. Consent gate: UserDefaults "consentCreatorAI" is checked for AI calls
//        before dispatch; throws BereanError.consentRequired when absent.
//   C-4. No force-unwraps. Offline/degraded state returns a structured error;
//        never crashes.
//   C-5. The Encodable.asDictionary() helper is scoped to this file via a
//        private extension to avoid polluting the global namespace, since
//        AmenAIFeaturesService and others use the same pattern.
//
// CF target: "bereanPipeline" (Gen-2, us-central1)
// Remote Config flag: "constitutionalIntelligence_enabled"

import Foundation
import FirebaseFunctions
import FirebaseRemoteConfig

// MARK: - BereanPipelineClient

@MainActor
final class BereanPipelineClient: ObservableObject {

    // MARK: Singleton

    static let shared = BereanPipelineClient()
    private init() {}

    // MARK: Private Dependencies

    private let functions = Functions.functions(region: "us-central1")
    private let remoteConfig = RemoteConfig.remoteConfig()

    // MARK: - Nested Types

    // MARK: BereanMode

    /// Epistemic mode sent to the pipeline on the wire.
    /// Raw values are the exact strings the backend expects (mirrors BereanPipelineMode).
    enum BereanMode: String, Codable {
        case ask      = "Ask"
        case discern  = "Discern"
        case build    = "Build"
        case guard_   = "Guard"
        case reflect  = "Reflect"
    }

    // MARK: BereanQuery

    struct BereanQuery: Codable {
        let query: String
        let mode: BereanMode
        let userId: String
        /// Conversation history for multi-turn sessions.
        /// Each element is {"role": "user"|"assistant", "content": "…"}.
        var conversationHistory: [[String: String]]?
    }

    // MARK: BereanResponse

    struct BereanResponse: Codable {
        let answer: String
        let evidence: [EvidenceChunk]
        let assumptions: [String]
        let unknowns: [String]
        let confidence: ConfidenceLevel
        let traceId: String

        // MARK: EvidenceChunk

        /// A single retrieved evidence chunk from the backend pipeline (Stage 3).
        struct EvidenceChunk: Codable {
            let id: String
            let source: String
            let content: String
            let sourceType: String
        }

        // MARK: ConfidenceLevel

        /// The confidence tier the backend assigned to this response.
        /// `.unknown` is the fail-secure default when the tier is absent or unrecognised.
        enum ConfidenceLevel: String, Codable {
            case high     = "High"
            case moderate = "Moderate"
            case low      = "Low"
            case unknown  = "Unknown"

            // Custom decoding: gracefully maps any unrecognised string to .unknown
            // so that a new backend tier never crashes existing clients.
            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                let raw = try container.decode(String.self)
                self = ConfidenceLevel(rawValue: raw) ?? .unknown
            }
        }
    }

    // MARK: BereanError

    enum BereanError: Error, LocalizedError {
        /// Remote Config flag "constitutionalIntelligence_enabled" is false.
        case pipelineDisabled
        /// The callable returned data in an unexpected shape.
        case invalidResponse
        /// The user has not granted AI consent.
        case consentRequired
        /// Backend constitutional review did not pass (or could not be confirmed).
        case constitutionalFailure

        var errorDescription: String? {
            switch self {
            case .pipelineDisabled:
                return "Berean is not available right now."
            case .invalidResponse:
                return "Received an unexpected response. Please try again."
            case .consentRequired:
                return "Please enable AI features in Settings before using Berean."
            case .constitutionalFailure:
                return "Response could not be verified. Please try again or consult a pastor."
            }
        }
    }

    // MARK: - Public API

    /// Sends a query through the Berean Constitutional Pipeline.
    ///
    /// - Parameter query: A fully constructed `BereanQuery` (mode, userId, optional history).
    /// - Returns: A decoded `BereanResponse` if the pipeline succeeded and passed
    ///   constitutional review.
    /// - Throws:
    ///   - `BereanError.pipelineDisabled` when Remote Config flag is false.
    ///   - `BereanError.consentRequired` when the user has not granted AI consent.
    ///   - `BereanError.invalidResponse` when the CF response cannot be decoded.
    ///   - `BereanError.constitutionalFailure` when the response's confidence is `.unknown`
    ///     (indicating the backend review stage was not completed or was rejected).
    ///   - Any `Functions.FunctionsErrorCode` error propagated from the callable.
    ///
    /// Invariant: this function never returns a response with confidence == .unknown.
    /// When the pipeline returns `.unknown` confidence, `constitutionalFailure` is thrown
    /// so the caller can surface the degraded advisory message rather than unverified content.
    func sendQuery(_ query: BereanQuery) async throws -> BereanResponse {

        // C-1: Feature flag gate — checked first, before any network I/O.
        let enabled = remoteConfig.configValue(forKey: "constitutionalIntelligence_enabled").boolValue
        guard enabled else {
            dlog("[BereanPipelineClient] C-1: constitutionalIntelligence_enabled is false — throwing pipelineDisabled.")
            throw BereanError.pipelineDisabled
        }

        // C-3: Consent gate — AI indexing consent is required for pipeline calls.
        guard UserDefaults.standard.bool(forKey: "consentCreatorAI") else {
            dlog("[BereanPipelineClient] C-3: consentCreatorAI not granted — throwing consentRequired.")
            throw BereanError.consentRequired
        }

        // C-2: Encode query to [String: Any] payload for the callable.
        let payload: [String: Any]
        do {
            payload = try query.asDictionary()
        } catch {
            dlog("[BereanPipelineClient] payload serialisation failed: \(error.localizedDescription)")
            throw BereanError.invalidResponse
        }

        // Call the Gen-2 Firebase callable.
        let callable = functions.httpsCallable("bereanPipeline")
        let result = try await callable.call(payload)

        // C-4: Decode with no force-unwraps.
        guard let data = result.data as? [String: Any] else {
            dlog("[BereanPipelineClient] C-4: result.data is not [String: Any] — throwing invalidResponse.")
            throw BereanError.invalidResponse
        }

        let response: BereanResponse
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: data)
            let decoder = JSONDecoder()
            // Custom date strategy matches all existing Berean callable patterns:
            // accept epoch-Double or ISO-8601 String; fall back to now.
            decoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                if let epoch = try? container.decode(Double.self) {
                    return Date(timeIntervalSince1970: epoch)
                }
                if let iso = try? container.decode(String.self) {
                    let formatter = ISO8601DateFormatter()
                    if let date = formatter.date(from: iso) { return date }
                }
                return Date()
            }
            response = try decoder.decode(BereanResponse.self, from: jsonData)
        } catch {
            dlog("[BereanPipelineClient] decode failed: \(error.localizedDescription) — throwing invalidResponse.")
            throw BereanError.invalidResponse
        }

        // C-1 (client-side gate): Reject any response the pipeline could not verify.
        // confidence == .unknown means the backend returned an unrecognised tier,
        // the review stage failed, or the response was a degraded/partial pass.
        // In all cases we throw constitutionalFailure so the caller surfaces the
        // safe advisory message, never unverified content.
        guard response.confidence != .unknown else {
            dlog("[BereanPipelineClient] constitutional gate: confidence==.unknown — throwing constitutionalFailure.")
            throw BereanError.constitutionalFailure
        }

        return response
    }
}

// MARK: - Encodable + asDictionary (file-private)

// This helper is declared private to this file to avoid namespace collisions with
// any identical extension in AmenAIFeaturesService or other files.
private extension Encodable {
    /// Encodes `self` to a `[String: Any]` dictionary suitable for Firebase callable payloads.
    /// - Throws: `EncodingError` or `BereanPipelineClient.BereanError.invalidResponse`
    ///   (the caller wraps this).
    func asDictionary() throws -> [String: Any] {
        let data = try JSONEncoder().encode(self)
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BereanPipelineClient.BereanError.invalidResponse
        }
        return dict
    }
}
