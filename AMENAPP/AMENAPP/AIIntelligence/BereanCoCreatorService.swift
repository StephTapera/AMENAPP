// BereanCoCreatorService.swift
// AMEN App — Berean Co-Creator ambient suggestion engine
//
// Generates scripture cross-references, original language notes, and
// Living Memory echoes as ambient suggestions while a user writes.
//
// Rate limit invariants:
//   - Ambient: max 1 active suggestion per block; once a suggestion is
//     dismissed the next block may receive a new one.
//   - Explicit invoke: ALWAYS returns a suggestion regardless of rate limit.
//
// Suggestions are NEVER auto-inserted — always dismissible.
//
// Flag-gated: AMENFeatureFlags.shared.bereanCoCreator

import Foundation

// MARK: - Models

struct CoCreatorSuggestion: Identifiable {
    var id: String
    var kind: CoCreatorSuggestionKind
    var content: String
    var dismissible: Bool         // always true per spec
    var personalEcho: String?     // e.g. "this connects to your note from March 12"
}

enum CoCreatorSuggestionKind {
    case crossReference
    case originalLanguage
    case livingMemoryEcho
}

// MARK: - Service

@MainActor
final class BereanCoCreatorService: ObservableObject {

    // MARK: - Published state

    /// The current ambient suggestion (nil when none or dismissed).
    @Published private(set) var currentSuggestion: CoCreatorSuggestion? = nil

    // MARK: - Rate limit state

    /// The ID of the block that currently "owns" the ambient slot.
    /// A new block can only receive an ambient suggestion if this is nil
    /// (i.e. the previous suggestion was dismissed or never generated).
    private var ambientSlotOwnerId: String? = nil

    // MARK: - Dependencies

    private let contextProvider: (any BereanContextProviding)?

    init(contextProvider: (any BereanContextProviding)? = nil) {
        self.contextProvider = contextProvider
    }

    // MARK: - Ambient suggestion

    /// Generates an ambient suggestion for a block of text.
    ///
    /// Rate limited: only one suggestion may be active at a time.
    /// If a suggestion is already active for this or another block, returns nil.
    /// Use invokeBerean(for:) to always get a suggestion on demand.
    ///
    /// - Parameter personalContext: when true, retrieves Living Memory context.
    /// - Returns: a suggestion, or nil if rate-limited.
    func suggestForBlock(_ text: String, personalContext: Bool) async throws -> CoCreatorSuggestion? {
        guard AMENFeatureFlags.shared.bereanCoCreator else { return nil }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        // Rate limit: ambient slot already occupied
        if ambientSlotOwnerId != nil { return nil }

        let blockId = UUID().uuidString
        ambientSlotOwnerId = blockId

        let suggestion = try await generateSuggestion(
            text: text,
            personalContext: personalContext,
            id: blockId
        )

        currentSuggestion = suggestion
        return suggestion
    }

    // MARK: - Explicit invoke

    /// Generates a richer response on demand, always returning a suggestion.
    /// Ignores the rate-limit slot — explicit invoke is always available.
    func invokeBerean(for text: String) async throws -> CoCreatorSuggestion {
        // Explicit invoke bypasses rate limit
        let suggestion = try await generateSuggestion(
            text: text,
            personalContext: true,
            id: UUID().uuidString
        )
        currentSuggestion = suggestion
        return suggestion
    }

    // MARK: - Dismiss

    /// Clears the current suggestion and frees the ambient slot for the next block.
    func dismissSuggestion() {
        currentSuggestion = nil
        ambientSlotOwnerId = nil
    }

    // MARK: - Private generation

    private func generateSuggestion(
        text: String,
        personalContext: Bool,
        id: String
    ) async throws -> CoCreatorSuggestion {
        var personalEcho: String? = nil

        if personalContext, let provider = contextProvider {
            let chunks = try await provider.retrieveContext(
                query: text,
                tier: .connected,
                limit: 1
            )
            if let topChunk = chunks.first, let label = topChunk.humanLabel {
                personalEcho = "this connects to \(label)"
            }
        }

        // Kind selection: prefer cross-reference for now;
        // original language and living memory echo based on content signals.
        let kind = pickKind(for: text, hasPersonalEcho: personalEcho != nil)

        let content = buildContent(for: kind, text: text)

        return CoCreatorSuggestion(
            id: id,
            kind: kind,
            content: content,
            dismissible: true,   // always true per spec
            personalEcho: personalEcho
        )
    }

    private func pickKind(for text: String, hasPersonalEcho: Bool) -> CoCreatorSuggestionKind {
        if hasPersonalEcho {
            return .livingMemoryEcho
        }
        // Simple heuristic: if text contains Hebrew/Greek term markers, suggest original language.
        let lowercased = text.lowercased()
        if lowercased.contains("greek") || lowercased.contains("hebrew") ||
           lowercased.contains("agape") || lowercased.contains("shalom") {
            return .originalLanguage
        }
        return .crossReference
    }

    private func buildContent(for kind: CoCreatorSuggestionKind, text: String) -> String {
        switch kind {
        case .crossReference:
            return "Cross-reference: Psalm 46:10 — \"Be still, and know that I am God.\""
        case .originalLanguage:
            return "Original language: this word in Greek is agapē — unconditional covenant love."
        case .livingMemoryEcho:
            return "A note you wrote previously touches this theme."
        }
    }
}
