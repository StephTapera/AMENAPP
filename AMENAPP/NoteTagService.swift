//
//  NoteTagService.swift
//  AMENAPP
//
//  Claude-powered church note services:
//   1. analyzeTags  — detects spiritual themes and returns 3-6 tag strings
//   2. lookupVerse  — returns NIV verse text for a scripture reference
//
//  API key is read from Info.plist key ANTHROPIC_API_KEY (set via Config.xcconfig).
//

import Foundation

enum NoteTagService {

    // MARK: - Configuration

    private static var apiKey: String {
        Bundle.main.object(forInfoDictionaryKey: "ANTHROPIC_API_KEY") as? String ?? ""
    }

    private static let apiURL = URL(string: "https://api.anthropic.com/v1/messages")!

    // MARK: - Auto-tag

    /// Sends note content to Claude and returns 3–6 spiritual theme tags.
    /// Returns `[]` silently if the API key is missing or the response cannot be parsed.
    static func analyzeTags(content: String) async throws -> [String] {
        guard content.count > 30 else { return [] }
        guard !apiKey.isEmpty else {
            dlog("NoteTagService: ANTHROPIC_API_KEY not set in Info.plist")
            return []
        }

        let body: [String: Any] = [
            "model": "claude-sonnet-4-6",
            "max_tokens": 150,
            "system": "You are a spiritual theme detector. Analyze this church note and return ONLY a JSON array of 3-6 short spiritual theme tags (1-2 words each). Example: [\"faith\",\"surrender\",\"provision\",\"Romans 8\"]. Return ONLY the JSON array, no other text.",
            "messages": [["role": "user", "content": content]]
        ]

        let text = try await callClaude(body: body)

        // Strip markdown fences if present
        let clean = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = clean.data(using: .utf8),
              let tags = try? JSONDecoder().decode([String].self, from: data) else {
            dlog("NoteTagService: Could not parse tag JSON: \(clean)")
            return []
        }
        return tags
    }

    // MARK: - Verse Lookup

    /// Returns the NIV text for a scripture reference using Claude.
    static func lookupVerse(reference: String) async throws -> String {
        let ref = reference.trimmingCharacters(in: .whitespaces)
        guard !ref.isEmpty else { return "" }
        guard !apiKey.isEmpty else {
            dlog("NoteTagService: ANTHROPIC_API_KEY not set in Info.plist")
            return ""
        }

        let body: [String: Any] = [
            "model": "claude-sonnet-4-6",
            "max_tokens": 300,
            "messages": [[
                "role": "user",
                "content": "Return the full text of \(ref) from the NIV Bible. Return ONLY the verse text and reference, no other commentary."
            ]]
        ]

        return try await callClaude(body: body)
    }

    // MARK: - Shared HTTP helper

    private static func callClaude(body: [String: Any]) async throws -> String {
        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json",   forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey,               forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01",         forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let raw = String(data: data, encoding: .utf8) ?? "unknown"
            throw NSError(domain: "NoteTagService", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: raw])
        }

        let decoded = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        return decoded.content.first?.text ?? ""
    }

    // MARK: - Response models

    private struct AnthropicResponse: Codable {
        let content: [ContentBlock]
        struct ContentBlock: Codable { let text: String }
    }
}
