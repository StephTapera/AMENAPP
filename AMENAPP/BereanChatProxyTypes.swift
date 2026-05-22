//
//  BereanChatProxyTypes.swift
//  AMENAPP
//
//  Codable Swift types mirroring the BereanChatRequest / response contract
//  defined in Backend/functions/src/bereanChatProxy.ts.
//
//  Usage (Firebase Callable):
//    let req = BereanChatProxyRequest(message: msg, mode: "shepherd")
//    let result = try await functions.httpsCallable("bereanChatProxy").call(req)
//    let response = try result.data(as: BereanChatProxyResponse.self)
//
//  IMPORTANT — Response key:
//    The backend returns the AI text under the key "response", NOT "text".
//    Call sites that read dict["text"] will receive nil. Use BereanChatProxyResponse.response
//    or check for both keys when migrating incrementally.
//
//  IMPORTANT — Legacy field mapping:
//    Many existing call sites send "systemPrompt" + "userMessage" as top-level keys.
//    The backend contract defines "message" + optional "systemPromptSuffix".
//    The backend silently ignores "systemPrompt" and "userMessage".
//    Migrated call sites must consolidate their text into "message" and pass
//    any system instruction as "systemPromptSuffix".
//

import Foundation

// MARK: - Request

/// Typed request matching the BereanChatRequest TypeScript interface.
/// All optional fields default to nil and are omitted from the JSON payload
/// when nil, which lets the backend apply its own defaults (mode = "shepherd",
/// maxTokens = 2000, temperature = 0.7).
struct BereanChatProxyRequest: Encodable {

    // MARK: Required
    /// The user's message. Max 4000 characters (enforced server-side).
    let message: String

    // MARK: Optional conversation context
    /// Prior turns in the current conversation. Sanitised server-side;
    /// only "user" / "assistant" roles are forwarded to Anthropic.
    let conversationHistory: [BereanChatMessage]?

    // MARK: Sampling parameters
    /// Maximum tokens in the completion. Server clamps to 128–2000.
    let maxTokens: Int?
    /// Sampling temperature. Server clamps to 0–1.
    let temperature: Double?

    // MARK: Mode / persona
    /// Berean personality mode. Known values: "shepherd" (default), "scholar",
    /// "debater", "prayer", "strategist", "deep_study".
    let mode: String?
    /// Hint for the model tier the client prefers. The server validates against
    /// the user's subscription and downgrades if needed. Pass "deep", "standard",
    /// or a full model ID (e.g. "claude-opus-4-7").
    let modelId: String?

    // MARK: Prompt customisation
    /// Appended to the server-built system prompt. Max 1500 characters (server-enforced).
    let systemPromptSuffix: String?

    // MARK: Memory / identity
    /// Memory scope label forwarded to the context builder (e.g. "conversation", "user").
    let memoryScope: String?

    // MARK: Rich call context
    /// Structured context block for identity, post, and sensitivity data.
    let callData: BereanCallData?
}

// MARK: - Conversation message

/// A single turn in the conversation history.
/// Maps to `{ role: "user" | "assistant", content: string }` in TypeScript.
struct BereanChatMessage: Codable {
    let role: String    // "user" or "assistant"
    let content: String
}

// MARK: - Call data (rich context block)

/// Structured context forwarded to the server-side `buildCallDataPrompt` function.
/// All fields are optional; omit any that are not relevant to the call.
struct BereanCallData: Encodable {
    /// Opaque identifier for the current conversation thread.
    let conversationId: String?
    /// Memory scope label (may duplicate the top-level field; both are accepted by the backend).
    let memoryScope: String?
    /// Faith journey stage from the user's profile (e.g. "new_believer", "mature").
    let faithJourneyStage: String?
    /// User persona or role (e.g. "pastor", "student").
    let userPersona: String?
    /// Preferred scripture translation (e.g. "ESV", "NIV").
    let scriptureTranslation: String?
    /// The response mode determined by client-side preflight (e.g. "standard", "crisis").
    let responseMode: String?
    /// Sensitivity flags raised by client-side preflight (e.g. ["self_harm"]).
    let sensitivityFlags: [String]?
    /// Rich context for the post this Berean chat is anchored to.
    let postContext: BereanPostContextPayload?
}

// MARK: - Post context payload

/// Post context block inside `callData.postContext`.
/// All string fields are required by the backend when postContext is present,
/// except those marked optional.
struct BereanPostContextPayload: Encodable {
    let postId: String
    let authorId: String
    let authorName: String
    /// Safe, moderation-filtered preview of the post.
    let previewText: String
    /// Full post body (optional; server caps at 500 chars).
    let bodyText: String?
    let category: String
    let verseReference: String?
    let verseText: String?
    /// AI-generated or human-written media summary.
    let mediaSummary: String?
    let isSensitive: Bool
}

// MARK: - Response

/// Typed response matching the object returned by bereanChatProxy.
///
/// NOTE: The backend returns the AI text under the key "response".
/// The legacy key "text" does NOT exist in the current backend — call sites
/// that read `dict["text"]` receive nil and silently fall back to empty strings
/// or error states.
struct BereanChatProxyResponse: Decodable {
    /// The AI-generated, safety-checked response text.
    let response: String
    /// The model ID that was actually used (entitlement-validated server-side).
    let model: String?
    /// Token usage from Anthropic.
    let usage: BereanChatUsage?
    /// Observability run ID for tracing this request.
    let agentRunId: String?
    /// True when the server downgraded the model tier due to subscription limits.
    let downgraded: Bool?
    /// The user's resolved subscription tier (e.g. "free", "pro").
    let tier: String?
    /// Outcome status from the server-side safety evaluator ("passed", "warned", "blocked").
    let outcomeStatus: String?
    /// Numeric safety score (0–100; higher = more violations).
    let outcomeScore: Int?
    /// Simplified safety signal ("ok", "warned", "blocked").
    let safetyStatus: String?
}

// MARK: - Token usage

/// Anthropic token usage returned inside the proxy response.
/// Uses snake_case keys to match the Anthropic API wire format, which the
/// backend forwards without transformation.
struct BereanChatUsage: Decodable {
    let inputTokens: Int?
    let outputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case inputTokens  = "input_tokens"
        case outputTokens = "output_tokens"
    }
}

// MARK: - Convenience helpers

extension BereanChatProxyRequest {

    /// Minimal request with only a message and optional mode.
    init(message: String, mode: String? = nil) {
        self.message = message
        self.conversationHistory = nil
        self.maxTokens = nil
        self.temperature = nil
        self.mode = mode
        self.modelId = nil
        self.systemPromptSuffix = nil
        self.memoryScope = nil
        self.callData = nil
    }

    /// Standard utility request (system-generated prompts, no conversation history).
    /// This mirrors the pattern used by NoteTagService, KoraViewModel, DisasterAlertService, etc.
    ///
    /// - Parameters:
    ///   - message: The user/content message.
    ///   - systemPromptSuffix: System instruction to append to the Berean system prompt.
    ///   - maxTokens: Max completion tokens (default nil = server default of 2000).
    ///   - mode: Berean personality mode (default nil = server default "shepherd").
    init(
        message: String,
        systemPromptSuffix: String?,
        maxTokens: Int? = nil,
        mode: String? = nil
    ) {
        self.message = message
        self.conversationHistory = nil
        self.maxTokens = maxTokens
        self.temperature = nil
        self.mode = mode
        self.modelId = nil
        self.systemPromptSuffix = systemPromptSuffix
        self.memoryScope = nil
        self.callData = nil
    }
}

extension BereanChatProxyResponse {

    /// The response text, falling back to an empty string when the field is missing.
    /// Use this when you only need the text and want a safe non-optional.
    var responseText: String { response }
}
