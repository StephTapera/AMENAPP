// CreatorAssistantView.swift
// AMEN — Creator Profiles (ministry hubs) — Wave 3 UI
//
// Grounded AI assistant. The user asks → CreatorHubService.ask → CreatorHubAssistantAnswer.
//
// GROUNDING CONTRACT (non-negotiable):
//   - refused == true  → render an explicit, calm REFUSAL state ("I can only answer from
//     {creator}'s shared teachings — I don't have material on that.") + refusalReason.
//   - refused == false → render the answer AND its inline Citations list. We NEVER render an
//     answer without showing citations; an answer that arrives with zero citations is itself
//     surfaced as a refusal (defensive — protects the grounding promise).
//   - Every citation is tappable → onOpenCitation(CreatorHubCitation) to open the source at
//     timestampSec / path.
//
// Exact initializer (mandated): CreatorAssistantView(creatorId: String).
//
// Conventions: white bg / black text; single translucent glass input bar (no glass-on-glass);
// AmenTheme.Colors.* tokens; Dynamic Type; VoiceOver labels; reduce-motion safe.

import SwiftUI

struct CreatorAssistantView: View {
    let creatorId: String
    /// Display name used in copy/refusals. Defaults to a neutral phrase if unknown.
    var creatorName: String = "this ministry"
    /// Host opens the cited source (teaching/resource) at timestampSec / path.
    var onOpenCitation: (CreatorHubCitation) -> Void = { _ in }

    @State private var queryText: String = ""
    @State private var state: AssistantState = .idle

    private enum AssistantState {
        case idle
        case loading
        case grounded(answer: String, citations: [CreatorHubCitation])
        case refused(reason: String?)
        case error(String)
    }

    private var trimmed: String {
        queryText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isLoading: Bool {
        if case .loading = state { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    groundingNotice
                    content
                }
                .padding(16)
            }
            inputBar
        }
        .background(AmenTheme.Colors.backgroundPrimary)
    }

    // MARK: Grounding notice (sets honest expectation up front)

    private var groundingNotice: some View {
        Label("Answers come only from \(creatorName)'s approved teachings and resources.",
              systemImage: "checkmark.shield")
            .font(.footnote)
            .foregroundStyle(AmenTheme.Colors.textSecondary)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AmenTheme.Colors.surfaceChip)
            )
            .accessibilityLabel("Answers come only from \(creatorName)'s approved teachings and resources.")
    }

    // MARK: Content states

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle:
            idleState
        case .loading:
            loadingState
        case let .grounded(answer, citations):
            groundedState(answer: answer, citations: citations)
        case let .refused(reason):
            refusalState(reason: reason)
        case let .error(message):
            errorState(message)
        }
    }

    private var idleState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(AmenTheme.Colors.amenGoldText)
            Text("Ask about \(creatorName)'s teachings")
                .font(.headline)
                .foregroundStyle(AmenTheme.Colors.textPrimary)
            Text("For example: \"What did they teach about forgiveness?\"")
                .font(.subheadline)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Ask about \(creatorName)'s teachings.")
    }

    private var loadingState: some View {
        VStack(alignment: .leading, spacing: 10) {
            SkeletonBlock(height: 16, cornerRadius: 6)
            SkeletonBlock(width: 240, height: 16, cornerRadius: 6)
            SkeletonBlock(width: 180, height: 16, cornerRadius: 6)
        }
        .padding(.vertical, 8)
        .accessibilityLabel("Finding an answer")
    }

    private func groundedState(answer: String, citations: [CreatorHubCitation]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(answer)
                .font(.body)
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Answer. \(answer)")

            // Citations are MANDATORY whenever an answer is shown.
            VStack(alignment: .leading, spacing: 8) {
                Text("Sources")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                ForEach(citations) { citation in
                    citationRow(citation)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AmenTheme.Colors.surfaceChip)
            )
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .amenGlassCard(cornerRadius: 18)
    }

    private func citationRow(_ citation: CreatorHubCitation) -> some View {
        Button {
            onOpenCitation(citation)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: sourceIcon(citation.sourceType))
                    .font(.subheadline)
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(sourceLabel(citation.sourceType))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                    if let detail = citationDetail(citation) {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(AmenTheme.Colors.textTertiary)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AmenTheme.Colors.iconSecondary)
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Source: \(sourceLabel(citation.sourceType)). \(citationDetail(citation) ?? "")")
        .accessibilityHint("Opens the source.")
        .accessibilityAddTraits(.isButton)
    }

    private func refusalState(reason: String?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("I can only answer from \(creatorName)'s shared teachings",
                  systemImage: "hand.raised")
                .font(.headline)
                .foregroundStyle(AmenTheme.Colors.textPrimary)

            Text("I don't have material on that.")
                .font(.body)
                .foregroundStyle(AmenTheme.Colors.textSecondary)

            if let reason, !reason.isEmpty {
                Text(reason)
                    .font(.footnote)
                    .foregroundStyle(AmenTheme.Colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AmenTheme.Colors.surfaceChip)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("I can only answer from \(creatorName)'s shared teachings. I don't have material on that. \(reason ?? "")")
    }

    private func errorState(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(AmenTheme.Colors.statusError)
            Button("Try again") { Task { await ask() } }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AmenTheme.Colors.surfaceChip)
        )
    }

    // MARK: Input bar

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Ask about their teachings…", text: $queryText, axis: .vertical)
                .font(.body)
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .lineLimit(1...4)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .accessibilityLabel("Your question")

            Button {
                Task { await ask() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(trimmed.isEmpty
                                     ? AmenTheme.Colors.iconSecondary
                                     : AmenTheme.Colors.textPrimary)
            }
            .buttonStyle(.plain)
            .disabled(trimmed.isEmpty || isLoading)
            .accessibilityLabel("Ask")
            .padding(.trailing, 8)
        }
        .amenGlassInputBar(cornerRadius: 24)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .padding(.top, 6)
    }

    // MARK: Ask

    private func ask() async {
        guard !trimmed.isEmpty else { return }
        let question = trimmed
        state = .loading
        do {
            let answer = try await CreatorHubService.shared.ask(creatorId: creatorId, query: question)
            if answer.refused {
                state = .refused(reason: answer.refusalReason)
            } else if answer.citations.isEmpty {
                // Defensive: an answer without citations breaks the grounding promise → refuse.
                state = .refused(reason: "No supporting source was available.")
            } else {
                state = .grounded(answer: answer.answer, citations: answer.citations)
            }
        } catch {
            state = .error("Couldn't reach the assistant. Please try again.")
        }
    }

    // MARK: Citation labels

    private func sourceLabel(_ source: CreatorHubCitationSource) -> String {
        switch source {
        case .teaching: return "Teaching"
        case .resource: return "Resource"
        case .event:    return "Event"
        case .course:   return "Course"
        }
    }

    private func sourceIcon(_ source: CreatorHubCitationSource) -> String {
        switch source {
        case .teaching: return "play.rectangle"
        case .resource: return "doc.text"
        case .event:    return "calendar"
        case .course:   return "graduationcap"
        }
    }

    private func citationDetail(_ citation: CreatorHubCitation) -> String? {
        if let ts = citation.timestampSec {
            let total = Int(ts.rounded())
            let m = total / 60
            let s = total % 60
            return String(format: "At %d:%02d", m, s)
        }
        if let path = citation.path, !path.isEmpty {
            return path
        }
        return nil
    }
}

#if DEBUG
#Preview("CreatorAssistantView") {
    CreatorAssistantView(creatorId: "demo", creatorName: "Pastor Grace")
}
#endif
