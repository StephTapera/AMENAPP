// AILReentrySummaryCard.swift
// AMENAPP — Accessibility Intelligence Layer (AIL) · Protection Surface (A6)
//
// C-reentry "Catch up" card. When a user returns to a thread/space after time away,
// this routes the gathered thread context through
// AILTransformService.transform(.reentrySummary, …) and shows a QUALITATIVE summary
// of what changed — never a number.
//
// IRON RULES (encoded here, in code AND behavior):
//   • IRON RULE 10 — NO NUMERIC COUNTS. We never render "12 new comments" or any
//     digit-bearing tally. Only qualitative phrasing ("Sarah answered your question").
//     A defensive scrubber (`stripsNumericCounts`) strips count-shaped phrases the
//     backend might still emit, so a count can never reach the screen.
//   • FAIL OPEN: on failOpen (or empty summary) we drop to a quiet, reassuring
//     "Nothing urgent to catch up on" state. Re-entry never alarms.
//   • Protection SUGGESTS; moderation DECIDES. Shares ZERO code path with NeMo /
//     Guardian — only the fail-open AILTransformService.
//   • NO tier checks — accessibility is free at every tier.
//   • Reduce Motion → no animation.

import SwiftUI

/// A qualitative "what changed while you were away" card. Never shows counts.
struct AILReentrySummaryCard: View {

    /// A pre-assembled, human-readable description of the thread activity (no counts
    /// passed in by the caller either — qualitative context only).
    let threadContext: String
    /// Resolvable id/path of the thread — round-tripped for provenance / "View original".
    let originalRef: String

    // The six UI states of the card.
    private enum Phase: Equatable {
        case idle        // not yet requested
        case loading     // summary transform in flight
        case ready       // qualitative summary available
        case quiet       // nothing meaningful to summarize (or scrubbed to empty)
        case failOpen    // transform failed open → quiet, reassuring fallback
    }

    @State private var phase: Phase = .idle
    @State private var summary: String = ""

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: phase)
        .task(id: requestKey) { await summarizeIfNeeded() }
    }

    private var requestKey: String { "\(originalRef)|\(threadContext.hashValue)" }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.uturn.backward.circle")
                .font(.subheadline)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("While you were away")
                .font(.subheadline.weight(.semibold))
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Content (six-state aware)

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .idle, .loading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Catching you up…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("Catching you up"))

        case .ready:
            Text(summary)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(Text(summary))

        case .quiet, .failOpen:
            // Quiet, reassuring fallback — and the fail-open destination.
            Text("Nothing urgent to catch up on.")
                .font(.body)
                .foregroundStyle(.secondary)
                .accessibilityLabel(Text("Nothing urgent to catch up on."))
        }
    }

    // MARK: - Transform

    private func summarizeIfNeeded() async {
        let trimmedContext = threadContext.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContext.isEmpty else {
            await MainActor.run { phase = .quiet }
            return
        }

        await MainActor.run { phase = .loading }

        let result = await AILTransformService.shared.transform(
            task: .reentrySummary,
            input: threadContext,
            originalRef: originalRef
        )

        // FAIL OPEN → quiet, reassuring state.
        guard !result.failOpen else {
            await MainActor.run { phase = .failOpen }
            return
        }

        // IRON RULE 10: scrub any numeric counts before they can ever render.
        let scrubbed = Self.stripNumericCounts(result.text)
        await MainActor.run {
            if scrubbed.isEmpty {
                phase = .quiet
            } else {
                summary = scrubbed
                phase = .ready
            }
        }
    }

    // MARK: - Numeric-count scrubber (IRON RULE 10)

    /// Remove any count-shaped phrasing so a numeric tally can never reach the screen.
    /// Strips standalone digits and digit-led quantity phrases ("12 new comments",
    /// "3 replies"), then tidies the residue. Qualitative sentences survive intact.
    static func stripNumericCounts(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "" }

        // 1) Drop digit-led quantity clauses entirely (e.g. "12 new comments,").
        let quantityPattern = #"\b\d+\s+[\p{L}\s]*?(comments?|replies|reply|messages?|notifications?|likes?|reactions?|posts?|updates?|mentions?|new)\b[\.,;]?"#
        var cleaned = replace(in: raw, pattern: quantityPattern, with: "")

        // 2) Remove any remaining bare digit runs (defensive).
        cleaned = replace(in: cleaned, pattern: #"\b\d[\d,\.]*\b"#, with: "")

        // 3) Tidy doubled spaces / dangling punctuation left by the removals.
        cleaned = replace(in: cleaned, pattern: #"\s{2,}"#, with: " ")
        cleaned = replace(in: cleaned, pattern: #"\s+([\.,;])"#, with: "$1")
        cleaned = replace(in: cleaned, pattern: #"^[\s\.,;]+"#, with: "")

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func replace(in input: String, pattern: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return input
        }
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        return regex.stringByReplacingMatches(in: input, options: [], range: range, withTemplate: template)
    }
}
