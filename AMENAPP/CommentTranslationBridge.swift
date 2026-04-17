// CommentTranslationBridge.swift
// AMEN App — Accessibility Intelligence Layer (Phase 6)
//
// Batch language detection + translation orchestrator for comment threads.
// Detects languages across all comments, identifies which need translation,
// and generates a thread-level language summary for the ThreadSummaryView.

import Foundation

@MainActor
final class CommentTranslationBridge: ObservableObject {

    static let shared = CommentTranslationBridge()

    // MARK: - Published State

    @Published private(set) var threadLanguageMap: [String: String] = [:]  // commentId → languageCode
    @Published private(set) var foreignCommentIds: Set<String> = []        // comments needing translation
    @Published private(set) var threadLanguageSummary: ThreadLanguageSummary?

    // MARK: - Private

    private let translationService = TranslationService.shared
    private let settings = TranslationSettingsManager.shared

    private init() {}

    // MARK: - Public API

    /// Analyze a thread's comments and detect languages.
    /// Call this once when CommentsView loads its comments.
    func analyzeThread(comments: [Comment]) async {
        guard AMENFeatureFlags.shared.conversationBridgeEnabled else { return }

        var langMap: [String: String] = [:]
        var foreignIds: Set<String> = []
        var languageCounts: [String: Int] = [:]
        let userLang = settings.userLanguageCode

        for comment in comments {
            guard let commentId = comment.id else { continue }
            let trimmed = comment.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 10 else { continue } // Skip very short comments

            let detection = await translationService.detectLanguage(trimmed)
            guard detection.isReliable else { continue }

            let detectedLang = detection.languageCode
            langMap[commentId] = detectedLang
            languageCounts[detectedLang, default: 0] += 1

            if detectedLang != userLang &&
               !settings.preferences.understoodLanguages.contains(detectedLang) {
                foreignIds.insert(commentId)
            }
        }

        threadLanguageMap = langMap
        foreignCommentIds = foreignIds

        // Build summary
        if languageCounts.count > 1 {
            let sorted = languageCounts.sorted { $0.value > $1.value }
            let languages = sorted.map { $0.key }
            threadLanguageSummary = ThreadLanguageSummary(
                languages: languages,
                foreignCommentCount: foreignIds.count,
                totalCommentCount: comments.count
            )
        } else {
            threadLanguageSummary = nil
        }
    }

    /// Check if a specific comment is in a foreign language
    func isForeignLanguage(commentId: String) -> Bool {
        foreignCommentIds.contains(commentId)
    }

    /// Get the detected language for a comment
    func detectedLanguage(for commentId: String) -> String? {
        threadLanguageMap[commentId]
    }

    /// Reset state (call when leaving comments view)
    func reset() {
        threadLanguageMap = [:]
        foreignCommentIds = []
        threadLanguageSummary = nil
    }
}

// MARK: - Thread Language Summary

struct ThreadLanguageSummary {
    let languages: [String]          // Ordered by frequency
    let foreignCommentCount: Int
    let totalCommentCount: Int

    var displayText: String {
        let names = languages.prefix(3).compactMap { SupportedLanguage.displayName(for: $0) }
        let joined = names.joined(separator: ", ")
        return "This thread includes comments in \(joined)"
    }

    var foreignRatio: Double {
        guard totalCommentCount > 0 else { return 0 }
        return Double(foreignCommentCount) / Double(totalCommentCount)
    }
}
