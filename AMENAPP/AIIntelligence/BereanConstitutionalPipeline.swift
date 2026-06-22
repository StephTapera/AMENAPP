// BereanConstitutionalPipeline.swift
// AMENAPP
//
// Swift client for the 7-stage Berean Constitutional Pipeline backend.
// Calls the "bereanConstitutionalPipeline" Firebase callable, maintains
// per-session conversation history, and exposes a feedback callable.
//
// Architecture notes:
//   - @MainActor class: all @Published mutations happen on the main thread.
//   - Feature-flagged via "berean_constitutional_pipeline_enabled" in Remote Config.
//     When the flag is false the pipeline is UNAVAILABLE; no legacy path is used
//     because the legacy callable has no constitutional review stage. A
//     .pipelineDisabled error is thrown and the degraded response is surfaced
//     instead — no unverified candidate answer ever reaches the user.
//   - sessionId is stable for the lifetime of this instance; use clearHistory()
//     to begin a new logical session.
//   - submitFeedback() is best-effort; errors are swallowed silently.
//   - BereanPipelineMode mirrors BereanConstitutionalMode but is the wire type
//     sent to the backend; keep these two enums aligned if you rename values.
//
// Fail-secure invariants (P0-fix 2026-06-12):
//   I-1. The legacy "callModelBerean" path is REMOVED. When the pipeline flag is
//        false the caller receives a degraded response, never unverified content.
//   I-2. After a successful pipeline call, if isVerified==false or reviewVerdict
//        is a known failure/legacy sentinel, the answer is replaced with the
//        degraded-response string. The evidence/assumptions/unknowns from the
//        backend are preserved for transparency.
//   I-3. Any throw from the pipeline (network, decode, partial corruption) is
//        caught and replaced with the degraded response. The error is surfaced in
//        self.error for the UI but NO unverified text is published to lastResponse.
//   I-4. Before any flag check or network call, CrisisDetectionService performs a
//        synchronous local scan. If a crisis signal is present the call is aborted,
//        isCrisisEscalated is set to true, and NO Berean response is returned — not
//        even a degraded one. The caller must observe isCrisisEscalated and show
//        the crisis resource card.

import Foundation
import SwiftUI
import FirebaseFunctions
import FirebaseRemoteConfig

// MARK: - BereanPipelineMode

/// The epistemic mode passed to the 7-stage pipeline.
/// Raw values are the exact strings the backend expects.
enum BereanPipelineMode: String, CaseIterable {
    case ask      = "Ask"
    case discern  = "Discern"
    case build    = "Build"
    case guard_   = "Guard"
    case reflect  = "Reflect"
}

// MARK: - BereanPipelineEvidence

struct BereanPipelineEvidence: Codable, Identifiable {
    let id: String
    let citation: String
    let content: String
    let source: String
}

// MARK: - BereanPipelineResponse

struct BereanPipelineResponse: Codable, Identifiable {
    // `id` is the backend trace identifier.
    var id: String { traceId }
    let traceId: String
    let answer: String
    let evidence: [BereanPipelineEvidence]
    let context: String
    let interpretations: [String]
    let assumptions: [String]
    let unknowns: [String]
    let confidence: String
    let trustScore: Double
    let reviewVerdict: String
    let isVerified: Bool
    var isAiGenerated: Bool = true
    let timestamp: Date

    // MARK: - Coding keys (snake_case ↔ camelCase)
    enum CodingKeys: String, CodingKey {
        case traceId
        case answer
        case evidence
        case context
        case interpretations
        case assumptions
        case unknowns
        case confidence
        case trustScore
        case reviewVerdict
        case isVerified
        case isAiGenerated
        case timestamp
    }
}

// MARK: - BereanConstitutionalPipeline

@MainActor
final class BereanConstitutionalPipeline: ObservableObject {

    // MARK: Singleton

    static let shared = BereanConstitutionalPipeline()

    // MARK: Published State

    @Published var isLoading = false
    @Published var lastResponse: BereanPipelineResponse? = nil
    @Published var error: String? = nil
    @Published var conversationHistory: [BereanConversationTurn] = []
    /// I-4: Set to true when a crisis signal is detected in the query.
    /// The view must observe this and present the crisis resource card.
    /// Never cleared automatically — call clearHistory() to reset.
    @Published var isCrisisEscalated: Bool = false
    /// PRIV-005: Set to true when a query is attempted before first-run AI consent.
    /// The view observes this (via `.bereanAIConsentGate()`) and presents the
    /// disclosure sheet. The model is NOT called until consent is recorded.
    @Published var requiresAIConsent: Bool = false

    // MARK: Supporting Types

    struct BereanConversationTurn: Codable {
        let role: String
        let content: String
    }

    // MARK: Session Identity

    let sessionId: String = UUID().uuidString

    // MARK: Private

    private let functions = Functions.functions(region: "us-central1")
    private let remoteConfig = RemoteConfig.remoteConfig()

    private init() {}

    // MARK: - Feature Flag

    private var isPipelineEnabled: Bool {
        remoteConfig.configValue(forKey: "berean_constitutional_pipeline_enabled").boolValue
    }

    // MARK: - Conversation History Serialisation

    /// Converts the current conversation history to the [[String: String]] shape
    /// the callable expects.
    private func serialisedHistory() -> [[String: String]] {
        conversationHistory.map { ["role": $0.role, "content": $0.content] }
    }

    // MARK: - Public API

    /// Send a query through the 7-stage constitutional pipeline.
    ///
    /// - Parameters:
    ///   - query: The user's question or prompt.
    ///   - mode: Epistemic mode for the pipeline (defaults to `.ask`).
    ///   - userId: Authenticated user ID for tracing and personalisation.
    func ask(query: String, mode: BereanPipelineMode = .ask, userId: String) async {
        isLoading = true
        error = nil

        defer { isLoading = false }

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            error = "Query cannot be empty."
            return
        }

        // I-4: Crisis pre-screen — runs synchronously before ANY flag check or network
        // call. If a crisis signal is detected the pipeline is halted immediately.
        // The view must observe isCrisisEscalated and show the crisis resource card.
        // Fail-closed: the degraded response is NOT returned either, because any AI
        // response (verified or not) is inappropriate when a crisis signal is present.
        if CrisisDetectionService.shared.hasLocalCrisisSignal(in: trimmedQuery) {
            dlog("[BereanPipeline] I-4: crisis signal detected — aborting pipeline, setting isCrisisEscalated.")
            isCrisisEscalated = true
            return
        }

        // PRIV-005: First-run AI consent gate. Berean is a generative-AI surface;
        // no query content is sent for AI processing until the user has granted
        // informed consent. Fail-closed: if consent is unknown we refuse the call
        // and surface the disclosure sheet via requiresAIConsent.
        guard BereanAIConsentManager.hasConsentedNow() else {
            dlog("[BereanPipeline] PRIV-005: AI consent not granted — refusing pipeline call, surfacing consent sheet.")
            requiresAIConsent = true
            return
        }

        // I-1: Pipeline flag is the single gate. No legacy path — the legacy callable
        // has no constitutional review stage and must never be used as a fallback.
        guard isPipelineEnabled else {
            dlog("[BereanPipeline] Pipeline disabled via Remote Config — surfacing degraded response.")
            self.error = BereanPipelineError.pipelineDisabled.localizedDescription
            lastResponse = BereanPipelineResponse.degraded(
                traceId: UUID().uuidString,
                reason: "pipeline_disabled"
            )
            return
        }

        do {
            let candidate = try await callConstitutionalPipeline(
                query: trimmedQuery,
                mode: mode,
                userId: userId
            )

            // I-2: Reject any response that has not been confirmed by constitutional review.
            // reviewVerdict values that mean "no full review was applied":
            //   "legacy"          — legacy callable synthetic response (should never appear now)
            //   "fail"            — backend review did not pass
            //   "verified-partial"— backend degraded pass; treat as unverified on the client
            //   "error"           — pipeline error verdict
            let knownFailVerdicts: Set<String> = ["legacy", "fail", "verified-partial", "error"]
            let response: BereanPipelineResponse
            if !candidate.isVerified || knownFailVerdicts.contains(candidate.reviewVerdict.lowercased()) {
                dlog("[BereanPipeline] I-2: response rejected — isVerified=\(candidate.isVerified) reviewVerdict='\(candidate.reviewVerdict)'. Surfacing degraded response.")
                response = BereanPipelineResponse.degraded(
                    traceId: candidate.traceId,
                    reason: candidate.reviewVerdict,
                    evidence: candidate.evidence,
                    assumptions: candidate.assumptions,
                    unknowns: candidate.unknowns
                )
            } else {
                response = candidate
            }

            // Append conversation turns only for verified responses so history
            // does not accumulate unverified content.
            conversationHistory.append(BereanConversationTurn(role: "user", content: trimmedQuery))
            conversationHistory.append(BereanConversationTurn(role: "assistant", content: response.answer))
            lastResponse = response

        } catch {
            // I-3: Any pipeline error (network, decode, partial corruption) surfaces a
            // degraded response with an error message. No unverified text is published.
            dlog("[BereanPipeline] I-3: pipeline error — \(error.localizedDescription). Surfacing degraded response.")
            self.error = error.localizedDescription
            lastResponse = BereanPipelineResponse.degraded(
                traceId: UUID().uuidString,
                reason: "pipeline_error"
            )
        }
    }

    /// Clears conversation history, last response, any pending error, and crisis state.
    func clearHistory() {
        conversationHistory = []
        lastResponse = nil
        error = nil
        isCrisisEscalated = false
    }

    /// Submits star rating + optional comment for the most recent pipeline response.
    /// Best-effort: errors are swallowed so this never disrupts the caller.
    ///
    /// - Parameters:
    ///   - rating: A rating token (e.g. "thumbs_up", "thumbs_down", "1"–"5").
    ///   - comment: Optional free-text comment.
    func submitFeedback(rating: String, comment: String? = nil) async {
        guard let lastResponse else { return }

        var payload: [String: Any] = [
            "traceId": lastResponse.traceId,
            "rating": rating,
        ]
        if let comment { payload["comment"] = comment }

        do {
            _ = try await functions.httpsCallable("bereanSubmitFeedback").call(payload)
        } catch {
            // Feedback is best-effort — log but do not surface.
            dlog("[BereanPipeline] submitFeedback failed (silently): \(error.localizedDescription)")
        }
    }

    // MARK: - Private Callables

    /// Calls the 7-stage "bereanConstitutionalPipeline" Cloud Function.
    private func callConstitutionalPipeline(
        query: String,
        mode: BereanPipelineMode,
        userId: String
    ) async throws -> BereanPipelineResponse {

        let payload: [String: Any] = [
            "query": query,
            "userId": userId,
            "sessionId": sessionId,
            "mode": mode.rawValue,
            "conversationHistory": serialisedHistory(),
        ]

        let result = try await functions.httpsCallable("bereanConstitutionalPipeline").call(payload)
        return try decode(result.data)
    }

    // MARK: - Decoding Helper

    private func decode(_ rawData: Any) throws -> BereanPipelineResponse {
        guard let dict = rawData as? [String: Any] else {
            throw BereanPipelineError.unexpectedResponseShape
        }

        // Normalise the raw dictionary to JSON data so JSONDecoder handles type coercion.
        let jsonData = try JSONSerialization.data(withJSONObject: dict)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            // Accept epoch seconds (Double) or ISO-8601 string.
            if let epoch = try? container.decode(Double.self) {
                return Date(timeIntervalSince1970: epoch)
            }
            if let iso = try? container.decode(String.self) {
                let formatter = ISO8601DateFormatter()
                if let date = formatter.date(from: iso) { return date }
            }
            return Date()
        }

        return try decoder.decode(BereanPipelineResponse.self, from: jsonData)
    }
}

// MARK: - BereanPipelineResponse + Degraded Factory

extension BereanPipelineResponse {
    /// Builds a fail-secure degraded response that is safe to surface to the user.
    ///
    /// A degraded response:
    ///  - carries `isVerified = false` and `reviewVerdict = "degraded"` so the
    ///    UI can render a clear "unverified" trust badge.
    ///  - replaces the candidate answer with a safe advisory string.
    ///  - preserves evidence/assumptions/unknowns from the backend (if supplied)
    ///    so the evidence sheet can still show what was retrieved.
    ///  - sets `trustScore = 0.0` and `confidence = "Unknown"`.
    ///
    /// - Parameters:
    ///   - traceId: Trace ID from the original backend call, or a new UUID for client-side errors.
    ///   - reason: Internal reason string (e.g. "pipeline_disabled", "pipeline_error", or the reviewVerdict).
    ///   - evidence: Evidence chunks from the backend, if available.
    ///   - assumptions: Assumptions from the backend, if available.
    ///   - unknowns: Unknowns from the backend, if available.
    static func degraded(
        traceId: String,
        reason: String,
        evidence: [BereanPipelineEvidence] = [],
        assumptions: [String] = [],
        unknowns: [String] = []
    ) -> BereanPipelineResponse {
        BereanPipelineResponse(
            traceId: traceId,
            answer: "I could not verify this response. Please try again or consult your pastor for guidance on this topic.",
            evidence: evidence,
            context: "",
            interpretations: [],
            assumptions: assumptions,
            unknowns: unknowns,
            confidence: "Unknown",
            trustScore: 0.0,
            reviewVerdict: "degraded",
            isVerified: false,
            timestamp: Date()
        )
    }
}

// MARK: - BereanPipelineError

enum BereanPipelineError: LocalizedError {
    case unexpectedResponseShape
    case pipelineDisabled
    case constitutionalFailure

    var errorDescription: String? {
        switch self {
        case .unexpectedResponseShape:
            return "Berean returned an unexpected response format. Please try again."
        case .pipelineDisabled:
            return "The Berean Constitutional Pipeline is currently unavailable."
        case .constitutionalFailure:
            return "Response could not be verified. Please try again or consult a pastor."
        }
    }
}

// MARK: - Preview / Demo View

#if DEBUG
private struct BereanPipelinePreview: View {
    @StateObject private var pipeline = BereanConstitutionalPipeline.shared
    @State private var query = "What does Romans 8:28 mean for daily life?"

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                TextField("Ask Berean…", text: $query, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3)
                    .padding(.horizontal)

                Button(action: {
                    Task {
                        await pipeline.ask(query: query, mode: .discern, userId: "preview-user")
                    }
                }) {
                    Label("Ask (Discern mode)", systemImage: "text.book.closed")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)
                .disabled(pipeline.isLoading)

                if pipeline.isLoading {
                    ProgressView("Consulting the pipeline…")
                }

                if let err = pipeline.error {
                    Text("Error: \(err)")
                        .foregroundStyle(.red)
                        .font(.caption)
                        .padding(.horizontal)
                }

                if let response = pipeline.lastResponse {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            // Degraded-state warning banner (I-2 / I-3)
                            if !response.isVerified {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.shield")
                                        .foregroundStyle(.orange)
                                    Text("Constitutional review was not completed for this response.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(10)
                                .background(Color.orange.opacity(0.08),
                                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }

                            Text(response.answer)
                                .font(.body)

                            Divider()

                            Label("Confidence: \(response.confidence)", systemImage: "checkmark.seal")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Label(
                                String(format: "Trust: %.0f%%", response.trustScore * 100),
                                systemImage: "shield.lefthalf.filled"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)

                            if !response.interpretations.isEmpty {
                                Text("Interpretations:")
                                    .font(.caption.bold())
                                ForEach(response.interpretations, id: \.self) { item in
                                    Text("• \(item)").font(.caption)
                                }
                            }

                            if !response.evidence.isEmpty {
                                Text("Evidence:")
                                    .font(.caption.bold())
                                ForEach(response.evidence) { chunk in
                                    Text("[\(chunk.citation)] \(chunk.content)")
                                        .font(.caption)
                                }
                            }
                        }
                        .padding()
                    }

                    HStack {
                        Button("Helpful") {
                            Task { await pipeline.submitFeedback(rating: "thumbs_up") }
                        }
                        Button("Not helpful") {
                            Task { await pipeline.submitFeedback(rating: "thumbs_down") }
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                }

                Spacer()
            }
            .navigationTitle("Berean Pipeline Demo")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear") { pipeline.clearHistory() }
                        .disabled(pipeline.conversationHistory.isEmpty)
                }
            }
        }
    }
}

#Preview("Berean Constitutional Pipeline") {
    BereanPipelinePreview()
}
#endif
