//
//  Feature03_ScriptureEcho.swift
//  AMENAPP
//
//  Scripture Echo — 2s debounce, 20+ char threshold.
//  Calls Anthropic via Cloud Function, caches last 20 results.
//  Never shows ribbon if last ribbon was dismissed within 60s.
//

import SwiftUI
import Combine
import FirebaseFunctions

// MARK: - Model

struct ScriptureEchoResult: Equatable {
    let reference: String
    let preview: String
}

// MARK: - Manager

final class ScriptureEchoManager: ObservableObject {
    static let shared = ScriptureEchoManager()

    @Published var suggestion: ScriptureEchoResult?

    private var debounceTask:      Task<Void, Never>?
    private var lastDismissedAt:   Date?
    private var cache:             [(key: String, result: ScriptureEchoResult)] = []
    private let cacheLimit         = 20
    private let dismissCooldown    = 60.0  // seconds

    private init() {}

    // MARK: - Public API

    func analyze(text: String) {
        guard text.count >= 20 else {
            suggestion = nil
            return
        }

        // Cool-down: if user dismissed a ribbon < 60s ago, suppress
        if let dismissed = lastDismissedAt, Date().timeIntervalSince(dismissed) < dismissCooldown {
            return
        }

        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2s
            guard !Task.isCancelled else { return }

            // Cache lookup (prefix 80 chars as key)
            let cacheKey = String(text.prefix(80))
            if let hit = cache.first(where: { $0.key == cacheKey }) {
                await MainActor.run { self.suggestion = hit.result }
                return
            }

            guard let result = await fetchSuggestion(for: text) else { return }

            // Store in cache, evict oldest if needed
            var updated = cache
            if updated.count >= cacheLimit { updated.removeFirst() }
            updated.append((key: cacheKey, result: result))
            cache = updated

            await MainActor.run { self.suggestion = result }
        }
    }

    func dismiss() {
        suggestion      = nil
        lastDismissedAt = Date()
    }

    func insertVerse() -> String {
        let verse = suggestion.map { "\($0.reference) — \($0.preview)" } ?? ""
        suggestion = nil
        return verse
    }

    // MARK: - Fetch

    private func fetchSuggestion(for text: String) async -> ScriptureEchoResult? {
        // Call the bereanGenericProxy Cloud Function to avoid exposing the key on-device
        let functions = Functions.functions()
        let payload: [String: Any] = [
            "model":      "claude-sonnet-4-6",
            "max_tokens": 128,
            "messages": [[
                "role": "user",
                "content": "The user is writing this message: '\(text.prefix(300))'. Suggest ONE Bible verse (reference + first 12 words of text) that matches the emotional tone. Return only JSON: {\"reference\": string, \"preview\": string}. If no clear match return null."
            ]],
        ]

        do {
            let result = try await functions.httpsCallable("bereanGenericProxy").call(payload)
            guard let dict = result.data as? [String: Any],
                  let text = dict["text"] as? String,
                  let data = text.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
                  let ref  = json["reference"],
                  let prev = json["preview"]
            else { return nil }
            return ScriptureEchoResult(reference: ref, preview: prev)
        } catch {
            dlog("⚠️ [ScriptureEcho] fetch error: \(error.localizedDescription)")
            return nil
        }
    }
}
