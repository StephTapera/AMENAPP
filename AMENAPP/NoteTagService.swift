//
//  NoteTagService.swift
//  AMENAPP
//
//  Claude-powered church note services:
//   1. analyzeTags  — detects spiritual themes and returns 3-6 tag strings
//   2. lookupVerse  — returns NIV verse text for a scripture reference
//
//  Routes through bereanChatProxy Cloud Function — no API key on device.
//

import Foundation
import FirebaseFunctions

enum NoteTagService {

    // MARK: - Auto-tag

    /// Sends note content to Claude via bereanChatProxy and returns 3–6 spiritual theme tags.
    /// Returns `[]` silently if the response cannot be parsed.
    static func analyzeTags(content: String) async throws -> [String] {
        guard content.count > 30 else { return [] }

        let systemPrompt = "You are a spiritual theme detector. Analyze this church note and return ONLY a JSON array of 3-6 short spiritual theme tags (1-2 words each). Example: [\"faith\",\"surrender\",\"provision\",\"Romans 8\"]. Return ONLY the JSON array, no other text."

        let text = try await callProxy(systemPrompt: systemPrompt, userMessage: content, maxTokens: 150)

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

    /// Returns the NIV text for a scripture reference via bereanChatProxy.
    static func lookupVerse(reference: String) async throws -> String {
        let ref = reference.trimmingCharacters(in: .whitespaces)
        guard !ref.isEmpty else { return "" }

        let userMessage = "Return the full text of \(ref) from the NIV Bible. Return ONLY the verse text and reference, no other commentary."
        return try await callProxy(systemPrompt: "", userMessage: userMessage, maxTokens: 300)
    }

    // MARK: - Shared proxy helper

    private static func callProxy(systemPrompt: String, userMessage: String, maxTokens: Int) async throws -> String {
        let functions = Functions.functions()
        let callable = functions.httpsCallable("bereanChatProxy")
        var params: [String: Any] = [
            "userMessage": userMessage,
            "maxTokens": maxTokens,
        ]
        if !systemPrompt.isEmpty {
            params["systemPrompt"] = systemPrompt
        }
        let result = try await callable.call(params)
        guard let data = result.data as? [String: Any],
              let text = data["text"] as? String else {
            throw NSError(domain: "NoteTagService", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid proxy response"])
        }
        return text
    }
}
