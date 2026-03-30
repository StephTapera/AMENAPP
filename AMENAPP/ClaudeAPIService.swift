// ClaudeAPIService.swift
// AMEN App — Shared Claude API Service
// Handles streaming + standard requests for all Berean AI features

import Foundation

// ─── MARK: Response Models ───────────────────────────────────────

struct ClaudeMessage: Codable {
    let role: String
    let content: String
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

    // ⚠️ Store in Info.plist or Secrets.xcconfig — never hardcode in production
    private let apiKey: String = {
        Bundle.main.object(forInfoDictionaryKey: "CLAUDE_API_KEY") as? String ?? ""
    }()

    private let endpoint = "https://api.anthropic.com/v1/messages"
    private let model    = "claude-opus-4-5"
    private let version  = "2023-06-01"

    // ─── Standard (non-streaming) ────────────────────────────────
    func complete(
        system: String,
        userMessage: String,
        maxTokens: Int = 1024
    ) async throws -> String {
        guard !apiKey.isEmpty else { throw ClaudeError.noAPIKey }
        guard let url = URL(string: endpoint) else { throw ClaudeError.invalidURL }

        let requestBody = ClaudeRequest(
            model: model,
            maxTokens: maxTokens,
            system: system,
            messages: [ClaudeMessage(role: "user", content: userMessage)],
            stream: false
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json",   forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey,               forHTTPHeaderField: "x-api-key")
        request.setValue(version,              forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw ClaudeError.networkError(body)
        }

        let decoded = try JSONDecoder().decode(ClaudeResponse.self, from: data)
        guard let text = decoded.content.first?.text else { throw ClaudeError.emptyResponse }
        return text
    }

    // ─── Streaming ───────────────────────────────────────────────
    func stream(
        system: String,
        messages: [ClaudeMessage],
        maxTokens: Int = 1024
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard !apiKey.isEmpty else { throw ClaudeError.noAPIKey }
                    guard let url = URL(string: endpoint) else { throw ClaudeError.invalidURL }

                    let requestBody = ClaudeRequest(
                        model: model,
                        maxTokens: maxTokens,
                        system: system,
                        messages: messages,
                        stream: true
                    )

                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue(apiKey,             forHTTPHeaderField: "x-api-key")
                    request.setValue(version,            forHTTPHeaderField: "anthropic-version")
                    request.httpBody = try JSONEncoder().encode(requestBody)

                    let (bytes, _) = try await URLSession.shared.bytes(for: request)

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let json = String(line.dropFirst(6))
                        guard json != "[DONE]" else { break }
                        guard let data = json.data(using: .utf8),
                              let event = try? JSONDecoder().decode(StreamEvent.self, from: data),
                              event.type == "content_block_delta",
                              let text = event.delta?.text
                        else { continue }
                        continuation.yield(text)
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
