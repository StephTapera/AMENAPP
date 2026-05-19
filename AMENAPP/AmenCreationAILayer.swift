// AmenCreationAILayer.swift
// AMENAPP
// AI-powered creation assistance: verse suggestions, caption improvement,
// hashtag suggestions, and content outline generation for Universal Create.

import Foundation
import FirebaseFunctions

@MainActor
final class AmenCreationAILayer: ObservableObject {
    static let shared = AmenCreationAILayer()

    @Published var verseSuggestions: [VerseHint] = []
    @Published var captionImprovement: String? = nil
    @Published var suggestedHashtags: [String] = []
    @Published var isWorking = false

    private let functions = Functions.functions()
    private var debounceTask: Task<Void, Never>? = nil

    // MARK: - Models

    struct VerseHint: Identifiable {
        let id = UUID()
        let reference: String
        let snippet: String
        let reason: String
    }

    // MARK: - Public API

    /// Debounced call: suggest relevant scripture as the user types.
    func suggestVerses(for text: String, intent: AmenCreationIntent) {
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            await _suggestVerses(text: text, intent: intent)
        }
    }

    /// Improve a photo/video caption using Berean's voice.
    func improveCaption(_ caption: String, mediaType: String) async {
        guard !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            captionImprovement = nil
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let result = try await functions.httpsCallable("improveCreationCaption").call([
                "caption": caption,
                "mediaType": mediaType
            ])
            let data = result.data as? [String: Any] ?? [:]
            captionImprovement = data["improved"] as? String
        } catch {
            dlog("[AmenCreationAILayer] improveCaption error: \(error)")
        }
    }

    /// Generate topic-appropriate Christian hashtags.
    func suggestHashtags(for text: String, intent: AmenCreationIntent) async {
        guard text.count > 20 else {
            suggestedHashtags = []
            return
        }
        do {
            let result = try await functions.httpsCallable("suggestCreationHashtags").call([
                "text": String(text.prefix(500)),
                "intent": intent.rawValue
            ])
            let data = result.data as? [String: Any] ?? [:]
            suggestedHashtags = data["hashtags"] as? [String] ?? []
        } catch {
            dlog("[AmenCreationAILayer] suggestHashtags error: \(error)")
        }
    }

    /// Generate a content outline (for notes or long-form posts).
    func generateOutline(topic: String, intent: AmenCreationIntent) async -> [String] {
        guard intent == .note || intent == .discussionPrompt else { return [] }
        do {
            let result = try await functions.httpsCallable("generateCreationOutline").call([
                "topic": topic,
                "intent": intent.rawValue
            ])
            let data = result.data as? [String: Any] ?? [:]
            return data["outline"] as? [String] ?? []
        } catch {
            dlog("[AmenCreationAILayer] generateOutline error: \(error)")
            return []
        }
    }

    func clearSuggestions() {
        verseSuggestions = []
        captionImprovement = nil
        suggestedHashtags = []
    }

    // MARK: - Private

    private func _suggestVerses(text: String, intent: AmenCreationIntent) async {
        guard text.count > 30 else {
            verseSuggestions = []
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let result = try await functions.httpsCallable("suggestCreationVerses").call([
                "text": String(text.prefix(500)),
                "intent": intent.rawValue
            ])
            let data = result.data as? [String: Any] ?? [:]
            let raw = data["verses"] as? [[String: String]] ?? []
            verseSuggestions = raw.compactMap { v in
                guard let ref = v["reference"], let snippet = v["snippet"] else { return nil }
                return VerseHint(reference: ref, snippet: snippet, reason: v["reason"] ?? "")
            }
        } catch {
            dlog("[AmenCreationAILayer] suggestVerses error: \(error)")
        }
    }
}
