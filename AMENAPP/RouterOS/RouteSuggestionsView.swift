// RouteSuggestionsView.swift
// AMENAPP — RouterOS
// Displays AI routing suggestions inline on a ContentCard.

import SwiftUI

struct RouteSuggestionsView: View {
    let card: ContentCard
    let suggestions: [ContentRouteSuggestion]
    let isLoading: Bool
    let onSelect: (ContentRouteSuggestion) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isLoading {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.75)
                    Text("Finding the best places for this…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
            } else if !suggestions.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                    Text("Suggested")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestions) { suggestion in
                            SuggestionChip(suggestion: suggestion) {
                                onSelect(suggestion)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Suggestion Chip

private struct SuggestionChip: View {
    let suggestion: ContentRouteSuggestion
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: suggestion.action.icon)
                    .font(.systemScaled(12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text(suggestion.label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(Color(.secondarySystemBackground), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(suggestion.label)
        .accessibilityHint(suggestion.rationale)
    }
}

// MARK: - Loaded Wrapper

struct LoadedRouteSuggestionsView: View {
    let card: ContentCard
    let context: ContentRouterContext
    let onSelect: (ContentRouteSuggestion) -> Void

    @State private var suggestions: [ContentRouteSuggestion] = []
    @State private var isLoading = false
    private let router: any ContentRouter = ContentRouterImpl()

    var body: some View {
        RouteSuggestionsView(
            card: card,
            suggestions: suggestions,
            isLoading: isLoading,
            onSelect: onSelect
        )
        .task {
            isLoading = true
            suggestions = await router.suggestDestinations(for: card, context: context)
            isLoading = false
        }
    }
}
