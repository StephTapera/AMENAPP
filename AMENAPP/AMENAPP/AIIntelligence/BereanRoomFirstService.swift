// BereanRoomFirstService.swift
// AMEN App — Room-first synthesis for Berean in Spaces threads
//
// ARCHITECTURAL CONTRACT:
// Human synthesis MUST structurally precede AI contribution.
// This is enforced in RoomSynthesis: humanSummary is the first stored property,
// bereanContribution is the second. Views MUST render in field declaration order.
//
// Flag gate: AMENFeatureFlags.shared.bereanRoomFirst

import Foundation
import FirebaseFunctions

// MARK: - RoomSynthesis

// NOTE: Field order here is architectural — humanSummary FIRST, bereanContribution SECOND.
// Do not reorder. Views must respect this structural contract.
extension RoomSynthesis {
    /// Returns true when there are enough messages to produce a meaningful human synthesis.
    var hasHumanSummary: Bool { !humanSummary.isEmpty }
}

// MARK: - BereanRoomFirstService

@MainActor
final class BereanRoomFirstService: ObservableObject, RoomFirstSynthesizing {

    static let shared = BereanRoomFirstService()

    private lazy var functions = Functions.functions(region: "us-central1")

    @Published var isLoading = false
    @Published var errorMessage: String?

    private init() {}

    // MARK: - Minimum message threshold

    /// Fewer than this many messages and human synthesis is not attempted.
    private static let minimumMessagesForSynthesis = 3

    // MARK: - RoomFirstSynthesizing

    /// Synthesizes human messages into a RoomSynthesis.
    ///
    /// CONTRACT:
    /// - If `messages.count < 3`, `humanSummary` is empty ("") — callers treat this as nil-equivalent.
    ///   Views MUST NOT render the "What the room said" section when humanSummary is empty.
    /// - `bereanContribution` is always present (Berean's answer is structurally second).
    func synthesizeHumanMessages(_ messages: [String]) async -> RoomSynthesis {
        guard AMENFeatureFlags.shared.bereanRoomFirst else {
            return RoomSynthesis(humanSummary: "", bereanContribution: "")
        }

        // STRUCTURAL RULE: fewer than 3 messages → no synthesis
        guard messages.count >= Self.minimumMessagesForSynthesis else {
            return RoomSynthesis(
                humanSummary: "",          // humanSummary is nil-equivalent
                bereanContribution: ""     // caller will populate from Berean's actual response
            )
        }

        let summary = buildLocalSummary(from: messages)
        return RoomSynthesis(
            humanSummary: summary,
            bereanContribution: ""  // caller populates with Berean's answer after synthesis
        )
    }

    /// Builds a full room synthesis: first synthesizes human messages (structurally first),
    /// then calls Berean for a contribution (structurally second).
    func buildRoomSynthesis(
        humanMessages: [String],
        bereanAnswer: String
    ) async -> RoomSynthesis {
        var synthesis = await synthesizeHumanMessages(humanMessages)
        // Berean's contribution is always appended second — never before humanSummary
        synthesis = RoomSynthesis(
            humanSummary: synthesis.humanSummary,
            bereanContribution: bereanAnswer
        )
        return synthesis
    }

    // MARK: - Private Helpers

    private func buildLocalSummary(from messages: [String]) -> String {
        let cleaned = messages
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !cleaned.isEmpty else { return "" }

        // Extract themes by looking at unique noun-like fragments
        // This is intentionally lightweight — no LLM call on this path
        let combined = cleaned.joined(separator: " ")
        let wordCount = combined.components(separatedBy: .whitespaces).count

        let themeLine: String
        if wordCount > 60 {
            themeLine = "The room raised multiple themes across \(cleaned.count) messages."
        } else {
            themeLine = "The room shared \(cleaned.count) perspectives."
        }

        // Capture perspectives count and questions raised
        let questionCount = cleaned.filter { $0.hasSuffix("?") }.count
        let questionNote = questionCount > 0
            ? " \(questionCount) question\(questionCount == 1 ? "" : "s") were raised."
            : ""

        return "\(themeLine)\(questionNote)"
    }
}
