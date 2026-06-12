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
//     If the flag is false, the legacy "callModelBerean" callable is used instead.
//   - sessionId is stable for the lifetime of this instance; use clearHistory()
//     to begin a new logical session.
//   - submitFeedback() is best-effort; errors are swallowed silently.
//   - BereanPipelineMode mirrors BereanConstitutionalMode but is the wire type
//     sent to the backend; keep these two enums aligned if you rename values.

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

        do {
            let response: BereanPipelineResponse

            if isPipelineEnabled {
                response = try await callConstitutionalPipeline(
                    query: trimmedQuery,
                    mode: mode,
                    userId: userId
                )
            } else {
                response = try await callLegacyBerean(
                    query: trimmedQuery,
                    mode: mode,
                    userId: userId
                )
            }

            // Append conversation turns before surfacing the response.
            conversationHistory.append(BereanConversationTurn(role: "user", content: trimmedQuery))
            conversationHistory.append(BereanConversationTurn(role: "assistant", content: response.answer))
            lastResponse = response

        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Clears conversation history, last response, and any pending error.
    func clearHistory() {
        conversationHistory = []
        lastResponse = nil
        error = nil
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

    /// Fallback: calls the legacy "callModelBerean" callable and wraps the response
    /// in a minimal `BereanPipelineResponse` so the caller always gets the same type.
    private func callLegacyBerean(
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

        let result = try await functions.httpsCallable("callModelBerean").call(payload)
        // The legacy callable returns a flat dict; map it to a full pipeline response.
        if let data = result.data as? [String: Any],
           let answer = data["response"] as? String ?? data["answer"] as? String {
            return BereanPipelineResponse(
                traceId: data["traceId"] as? String ?? UUID().uuidString,
                answer: answer,
                evidence: [],
                context: data["context"] as? String ?? "",
                interpretations: data["interpretations"] as? [String] ?? [],
                assumptions: [],
                unknowns: [],
                confidence: data["confidence"] as? String ?? "medium",
                trustScore: data["trustScore"] as? Double ?? 0.5,
                reviewVerdict: data["reviewVerdict"] as? String ?? "legacy",
                isVerified: false,
                timestamp: Date()
            )
        }
        throw BereanPipelineError.unexpectedResponseShape
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

// MARK: - BereanPipelineError

enum BereanPipelineError: LocalizedError {
    case unexpectedResponseShape
    case pipelineDisabled

    var errorDescription: String? {
        switch self {
        case .unexpectedResponseShape:
            return "Berean returned an unexpected response format. Please try again."
        case .pipelineDisabled:
            return "The Berean Constitutional Pipeline is currently unavailable."
        }
    }
}

// MARK: - Preview / Demo View

#if DEBUG
private struct BereanPipelinePreview: View {
    @StateObject private var pipeline = BereanConstitutionalPipeline()
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
