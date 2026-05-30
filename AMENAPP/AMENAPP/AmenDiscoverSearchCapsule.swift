// AmenDiscoverSearchCapsule.swift
// AMEN App — Discover search bar with AI disambiguation popup.
//
// Tapping the bar shows AmenSearchDisambiguationPopup instead of
// immediately focusing the TextField.  Once the user picks a mode:
//  • "Search People & Posts" → focuses the TextField for normal search
//  • "Ask Berean AI"         → calls onBereanAI with the current query
//  • "Find Scripture"        → calls onFindScripture
//
// The outer dismiss tap-area closes the popup when the user taps
// anywhere outside the bar+card stack.

import SwiftUI

struct AmenDiscoverSearchCapsule: View {
    @Binding var searchQuery: String
    let compactProgress: CGFloat
    var onBereanAI: (String) -> Void = { _ in }
    var onFindScripture: () -> Void = {}

    // MARK: Private state
    @State private var showDisambig = false
    @FocusState private var fieldFocused: Bool
    @State private var showSuggestions = false
    @State private var suggestions: [String] = []
    @State private var suggestionTask: Task<Void, Never>?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    // MARK: Modes

    private let modes: [AmenSearchMode] = [
        AmenSearchMode(
            id: "discover.people",
            icon: "magnifyingglass",
            iconColor: Color.primary,
            label: "Search People & Posts",
            subtitle: "Find testimonies, prayers & communities"
        ),
        AmenSearchMode(
            id: "discover.berean",
            icon: "sparkles",
            iconColor: AmenTheme.Colors.amenGold,
            label: "Ask Berean AI",
            subtitle: "Get scripture-grounded answers"
        ),
        AmenSearchMode(
            id: "discover.scripture",
            icon: "book.fill",
            iconColor: AmenTheme.Colors.amenBlue,
            label: "Find Scripture",
            subtitle: "Search Bible verses & passages"
        )
    ]

    // MARK: Body

    var body: some View {
        ZStack(alignment: .top) {
            // Dismiss layer — tapping outside the card collapses the popup
            if showDisambig || showSuggestions {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture {
                        dismiss()
                        withAnimation(reduceMotion ? .none : .amenSnappy) {
                            showSuggestions = false
                        }
                    }
                    .zIndex(0)
            }

            VStack(alignment: .leading, spacing: 6) {
                // Search bar row
                searchBar
                    .zIndex(1)

                // Typeahead suggestion dropdown
                if showSuggestions && !suggestions.isEmpty {
                    suggestionCard
                        .zIndex(3)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                        .animation(reduceMotion ? .none : .amenSpring, value: showSuggestions)
                }

                // Disambiguation popup, slides down from the bar
                if showDisambig {
                    AmenSearchDisambiguationPopup(
                        modes: modes,
                        onSelect: { mode in
                            handleSelection(mode)
                        },
                        onDismiss: { dismiss() }
                    )
                    .zIndex(2)
                    .animation(reduceMotion ? .none : .amenSpring, value: showDisambig)
                }
            }
        }
        .scaleEffect(1 - (compactProgress * 0.04), anchor: .top)
        .onChange(of: searchQuery) { _, newValue in
            updateSuggestions(for: newValue)
        }
        .onChange(of: fieldFocused) { _, focused in
            withAnimation(reduceMotion ? .none : .amenSnappy) {
                showSuggestions = focused && !searchQuery.isEmpty
            }
        }
    }

    // MARK: - Search bar

    private var searchBar: some View {
        Button {
            if fieldFocused {
                // Already in text-search mode; tap again dismisses
                dismiss()
            } else if !showDisambig {
                withAnimation(reduceMotion ? .none : .amenSpring) {
                    showDisambig = true
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.secondary)

                if fieldFocused || !searchQuery.isEmpty {
                    // TextField is active — let the user type
                    TextField("Search churches, testimonies, scripture", text: $searchQuery)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .font(AMENFont.regular(15))
                        .foregroundStyle(Color.primary)
                        .focused($fieldFocused)
                        .submitLabel(.search)
                } else {
                    // Dormant state — shows placeholder, tappable
                    Text("Search...")
                        .font(AMENFont.regular(15))
                        .foregroundStyle(Color.secondary)
                    Spacer()
                }

                // Clear button when text is entered
                if !searchQuery.isEmpty && fieldFocused {
                    Button {
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                    .animation(.amenSnappy, value: searchQuery.isEmpty)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .background(capsuleBackground)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Discover search — tap to choose a search mode")
    }

    // MARK: - Background

    @ViewBuilder
    private var capsuleBackground: some View {
        if reduceTransparency {
            Capsule(style: .continuous)
                .fill(Color(.systemBackground))
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
                }
        } else {
            Capsule(style: .continuous)
                .fill(.regularMaterial)
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.6)
                }
        }
    }

    // MARK: - Suggestion card

    private var suggestionCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(suggestions.prefix(5).enumerated()), id: \.offset) { index, suggestion in
                Button {
                    withAnimation(reduceMotion ? .none : .amenSnappy) {
                        searchQuery = suggestion
                        showSuggestions = false
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.secondary)
                            .frame(width: 20)

                        Text(boldedPrefix(suggestion, matching: searchQuery))
                            .font(AMENFont.regular(15))
                            .foregroundStyle(Color.primary)
                            .lineLimit(1)

                        Spacer()

                        Image(systemName: "arrow.up.left")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(Color.secondary)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if index < min(suggestions.count, 5) - 1 {
                    Divider()
                        .padding(.horizontal, 16)
                }
            }
        }
        .background(suggestionCardBackground)
        .accessibilityLabel("Search suggestions")
    }

    @ViewBuilder
    private var suggestionCardBackground: some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.systemBackground))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.6)
                }
                .shadow(color: .black.opacity(0.10), radius: 16, x: 0, y: 6)
        } else {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.12))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.6)
                }
                .shadow(color: .black.opacity(0.10), radius: 16, x: 0, y: 6)
        }
    }

    /// Returns an `AttributedString` where the prefix matching `query` is bold.
    private func boldedPrefix(_ text: String, matching query: String) -> AttributedString {
        var attributed = AttributedString(text)
        let lowercasedText = text.lowercased()
        let lowercasedQuery = query.lowercased()
        if lowercasedText.hasPrefix(lowercasedQuery),
           let range = attributed.range(of: String(text.prefix(query.count)), options: .caseInsensitive) {
            attributed[range].font = AMENFont.semiBold(15)
        }
        return attributed
    }

    private func updateSuggestions(for query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            suggestionTask?.cancel()
            withAnimation(reduceMotion ? .none : .amenSnappy) {
                suggestions = []
                showSuggestions = false
            }
            return
        }
        suggestionTask?.cancel()
        suggestionTask = Task {
            try? await Task.sleep(nanoseconds: 280_000_000) // 280ms debounce
            guard !Task.isCancelled else { return }
            let users = (try? await AlgoliaSearchService.shared.searchUsers(query: trimmed, limit: 5)) ?? []
            guard !Task.isCancelled else { return }
            // Map display names as suggestions; fallback to keyword completions if no users match.
            let userNames = users.map { $0.displayName }
            let keywordFallbacks = [
                "\(trimmed) churches",
                "\(trimmed) Bible study",
                "\(trimmed) prayer",
            ]
            let merged = Array((userNames + keywordFallbacks).prefix(5))
            await MainActor.run {
                withAnimation(reduceMotion ? .none : .amenSnappy) {
                    suggestions = merged
                    showSuggestions = fieldFocused && !merged.isEmpty
                }
            }
        }
    }

    // MARK: - Handlers

    private func dismiss() {
        withAnimation(reduceMotion ? .none : .amenSpring) {
            showDisambig = false
            showSuggestions = false
        }
    }

    @MainActor
    private func handleSelection(_ mode: AmenSearchMode) {
        withAnimation(reduceMotion ? .none : .amenSnappy) {
            showDisambig = false
        }
        switch mode.id {
        case "discover.people":
            // Normal text search: focus the field so the keyboard appears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                fieldFocused = true
            }
        case "discover.berean":
            onBereanAI(searchQuery)
        case "discover.scripture":
            onFindScripture()
        default:
            break
        }
    }
}
