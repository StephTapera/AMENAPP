// ClaudeAPIService.swift
// AMEN App — Shared Claude API Service
// All requests are proxied through bereanChatProxy (Cloud Function).
// The Claude API key NEVER touches the client binary.

import Foundation
import FirebaseFunctions

// ─── MARK: Response Models ───────────────────────────────────────

struct ClaudeMessage: Codable {
    let role: String
    let content: String
}

/// Full response from bereanChatProxy, including scripture validation metadata.
struct BereanProxyResponse {
    let text: String
    /// Scripture references extracted from the response (e.g. "John 3:16").
    let scriptureReferences: [String]
    /// True if any scripture references were found — client should show a
    /// "Verify in your Bible app" footer to guard against AI hallucinations.
    let hasUnverifiedReferences: Bool
    /// True if any extracted reference used an unrecognized book name.
    let hasUnrecognizedBook: Bool
}

struct ClaudeRequest: Codable {
    let model: String
    let maxTokens: Int
    let system: String
    let messages: [ClaudeMessage]
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case system, messages, stream
    }
}

struct ClaudeContentBlock: Codable {
    let type: String
    let text: String?
}

struct ClaudeResponse: Codable {
    let content: [ClaudeContentBlock]
}

// ─── MARK: Stream Events ─────────────────────────────────────────

struct StreamDelta: Codable {
    let type: String
    let text: String?
}

struct StreamEvent: Codable {
    let type: String
    let delta: StreamDelta?
}

// ─── MARK: Errors ────────────────────────────────────────────────

enum ClaudeError: LocalizedError {
    case invalidURL
    case noAPIKey
    case networkError(String)
    case decodingError(String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL:                   return "Invalid API URL."
        case .noAPIKey:                     return "Claude API key not configured."
        case .networkError(let msg):        return "Network error: \(msg)"
        case .decodingError(let msg):       return "Decoding error: \(msg)"
        case .emptyResponse:                return "Empty response from Claude."
        }
    }
}

// ─── MARK: Service ───────────────────────────────────────────────

actor ClaudeAPIService {

    static let shared = ClaudeAPIService()

    // ✅ SECURITY FIX: API key removed from client. All requests route through
    // bereanChatProxy (Cloud Function) which holds ANTHROPIC_API_KEY in
    // Firebase Secret Manager. The key never touches the binary.
    private let functions = Functions.functions(region: "us-central1")

    // ─── Standard (non-streaming) ────────────────────────────────
    func complete(
        system: String,
        userMessage: String,
        maxTokens: Int = 1024
    ) async throws -> String {
        try await completeWithValidation(system: system, userMessage: userMessage, maxTokens: maxTokens).text
    }

    /// Full response including scripture validation metadata.
    /// Use this in Berean chat views to conditionally show a "Verify references" footer.
    func completeWithValidation(
        system: String,
        userMessage: String,
        maxTokens: Int = 1024
    ) async throws -> BereanProxyResponse {
        let data: [String: Any] = [
            "systemPrompt": system,
            "userMessage": userMessage,
            "maxTokens": maxTokens
        ]
        let result: HTTPSCallableResult
        do {
            let callable = functions.httpsCallable("bereanChatProxy")
            callable.timeoutInterval = 15  // Fail fast — 70 s SDK default causes blank-screen hangs on Berean ask path
            result = try await callable.call(data)
        } catch {
            // CF-03: surface user-facing message for backend unavailability
            let nsErr = error as NSError
            if nsErr.domain == FunctionsErrorDomain {
                let code = FunctionsErrorCode(rawValue: nsErr.code)
                if code == .unimplemented || code == .`internal` {
                    throw ClaudeError.networkError("Berean AI is temporarily unavailable. Please try again.")
                }
            }
            throw error
        }
        guard let dict = result.data as? [String: Any],
              let text = dict["text"] as? String else {
            throw ClaudeError.emptyResponse
        }

        // Parse scripture validation metadata returned by the proxy
        let refs = (dict["scriptureReferences"] as? [[String: Any]] ?? [])
            .compactMap { $0["reference"] as? String }
        let hasUnverified = dict["hasUnverifiedReferences"] as? Bool ?? false
        let hasUnrecognized = dict["hasUnrecognizedBook"] as? Bool ?? false

        return BereanProxyResponse(
            text: text,
            scriptureReferences: refs,
            hasUnverifiedReferences: hasUnverified,
            hasUnrecognizedBook: hasUnrecognized
        )
    }

    // ─── Streaming (simulated via proxy) ─────────────────────────
    // Firebase Callable Functions don't support server-sent events, so we
    // fetch the full response and emit it word-by-word to preserve the
    // streaming UX that callers expect.
    func stream(
        system: String,
        messages: [ClaudeMessage],
        maxTokens: Int = 1024
    ) -> AsyncThrowingStream<String, Error> {
        // Build a single concatenated prompt from the message history
        let userMessage = messages
            .filter { $0.role == "user" }
            .map { $0.content }
            .joined(separator: "\n")

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let fullText = try await self.complete(
                        system: system,
                        userMessage: userMessage,
                        maxTokens: maxTokens
                    )
                    // Emit word by word to simulate streaming
                    let words = fullText.components(separatedBy: " ")
                    for (i, word) in words.enumerated() {
                        let token = i == 0 ? word : " " + word
                        continuation.yield(token)
                        try await Task.sleep(nanoseconds: 15_000_000) // ~15ms per word
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // ─── JSON Helper ─────────────────────────────────────────────
    func completeJSON<T: Decodable>(
        system: String,
        userMessage: String,
        as type: T.Type,
        maxTokens: Int = 1024
    ) async throws -> T {
        var raw = try await complete(system: system, userMessage: userMessage, maxTokens: maxTokens)
        raw = raw
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```",     with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = raw.data(using: .utf8) else { throw ClaudeError.decodingError("UTF8 fail") }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw ClaudeError.decodingError(error.localizedDescription)
        }
    }
}
