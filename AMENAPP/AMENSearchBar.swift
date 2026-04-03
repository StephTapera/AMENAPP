//
//  AMENSearchBar.swift
//  AMENAPP
//
//  Animated search bar: compact pill by default, expands on focus with
//  a lift animation, slide-in cancel, filter chips, and suggestion rows.
//
//  Design spec (matches HTML/React reference):
//  - Shell lifts 4pt on focus with a stronger drop shadow
//  - Cancel slides in from the right (opacity + x-offset)
//  - Panel below expands with opacity + y-offset reveal
//  - Filter chips scroll horizontally
//  - Suggestion rows shift right on tap (tactile feel)
//  - spring: cubic-bezier(0.22, 1, 0.36, 1) ≈ response:0.48 damping:0.82
//
//  Usage:
//    AMENSearchBar(
//        query: $searchText,
//        placeholder: "Search prayers, people...",
//        filterChips: ["Prayer", "Testimonies", "People"],
//        suggestions: viewModel.suggestions,
//        onSubmit: { text in viewModel.search(text) },
//        onChipTap: { chip in viewModel.filterBy(chip) },
//        onSuggestionTap: { s in viewModel.open(s) }
//    )

import SwiftUI

// MARK: - Suggestion Model

struct AMENSearchSuggestion: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    var icon: String = "arrow.right"

    // Convenience
    static func make(_ title: String, subtitle: String = "Quick search") -> AMENSearchSuggestion {
        AMENSearchSuggestion(id: UUID().uuidString, title: title, subtitle: subtitle)
    }
}

// MARK: - AMENSearchBar

struct AMENSearchBar: View {

    @Binding var query: String

    var placeholder: String                  = "Search prayers, people, notes, churches..."
    var filterChips: [String]                = ["Prayer", "Church Notes", "Testimonies", "People", "Resources"]
    var suggestions: [AMENSearchSuggestion]  = []
    var showDefaultSuggestions: Bool         = true

    var onSubmit: ((String) -> Void)?       = nil
    var onChipTap: ((String) -> Void)?      = nil
    var onSuggestionTap: ((AMENSearchSuggestion) -> Void)? = nil
    var onCancel: (() -> Void)?             = nil

    @FocusState private var isFocused: Bool
    @State private var showPanel: Bool = false

    // cubic-bezier(0.22, 1, 0.36, 1)
    private let expandSpring = Animation.spring(response: 0.48, dampingFraction: 0.82)
    private let fastSpring   = Animation.spring(response: 0.32, dampingFraction: 0.82)

    var body: some View {
        VStack(spacing: 0) {
            shellContent
        }
        .onChange(of: isFocused) { _, focused in
            withAnimation(expandSpring) { showPanel = focused }
        }
    }

    // MARK: - Shell

    private var shellContent: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Search row ────────────────────────────────────────────────
            HStack(alignment: .center, spacing: 0) {
                searchPill
                    .frame(maxWidth: .infinity)

                // Cancel — slides in from right on focus
                if showPanel {
                    Button { cancel() } label: {
                        Text("Cancel")
                            .font(AMENFont.medium(14))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.leading, 10)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .offset(x: 10)),
                            removal:   .opacity.combined(with: .offset(x: 10))
                        )
                    )
                }
            }

            // ── Expand panel ──────────────────────────────────────────────
            if showPanel {
                panelContent
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .offset(y: -8)),
                            removal:   .opacity.combined(with: .offset(y: -8))
                        )
                    )
            }
        }
        .padding(16)
        // Glass shell background
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.92), location: 0),
                            .init(color: Color(.systemGray6).opacity(0.95), location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(Color.black.opacity(isFocused ? 0.08 : 0.06), lineWidth: 1)
                )
        )
        // Lift + deepen shadow on focus
        .shadow(color: .black.opacity(isFocused ? 0.10 : 0.06),
                radius: isFocused ? 28 : 18, x: 0, y: isFocused ? 14 : 9)
        .offset(y: isFocused ? -4 : 0)
        .animation(expandSpring, value: isFocused)
        .animation(expandSpring, value: showPanel)
    }

    // MARK: - Search Pill

    private var searchPill: some View {
        HStack(spacing: 10) {
            // Magnifier — scales slightly on focus
            Image(systemName: "magnifyingglass")
                .font(.systemScaled(16, weight: .medium))
                .foregroundStyle(.secondary)
                .scaleEffect(isFocused ? 1.06 : 1.0)
                .animation(expandSpring, value: isFocused)

            // Text field
            TextField(placeholder, text: $query)
                .font(AMENFont.regular(16))
                .foregroundStyle(.primary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($isFocused)
                .submitLabel(.search)
                .onSubmit { onSubmit?(query) }
                .accessibilityLabel("Search field")

            // Clear x — shown while typing
            if !query.isEmpty {
                Button {
                    withAnimation(fastSpring) { query = "" }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.systemScaled(15))
                        .foregroundStyle(Color(.tertiaryLabel))
                }
                .transition(.opacity.combined(with: .scale(scale: 0.7)))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(
                cornerRadius: isFocused ? 20 : 999,
                style: .continuous
            )
            .fill(Color(.systemGray6))
            .overlay(
                RoundedRectangle(
                    cornerRadius: isFocused ? 20 : 999,
                    style: .continuous
                )
                .strokeBorder(Color.black.opacity(0.05), lineWidth: 1)
            )
            .animation(expandSpring, value: isFocused)
        )
    }

    // MARK: - Expand Panel

    private var panelContent: some View {
        VStack(alignment: .leading, spacing: 12) {

            // Filter chips
            if !filterChips.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(filterChips, id: \.self) { chip in
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                query = chip
                                onChipTap?(chip)
                            } label: {
                                Text(chip)
                                    .font(AMENFont.medium(13))
                                    .foregroundStyle(Color(.label).opacity(0.72))
                                    .padding(.horizontal, 13)
                                    .padding(.vertical, 7)
                                    .background(
                                        Capsule()
                                            .fill(Color.black.opacity(0.03))
                                            .overlay(
                                                Capsule()
                                                    .strokeBorder(Color.black.opacity(0.05), lineWidth: 1)
                                            )
                                    )
                            }
                            .buttonStyle(AMENChipButtonStyle())
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.top, 2)
                }
            }

            // Suggestion rows
            let rows = suggestionRows
            if !rows.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, suggestion in
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            query = suggestion.title
                            onSuggestionTap?(suggestion)
                            withAnimation(fastSpring) { showPanel = false; isFocused = false }
                        } label: {
                            HStack(spacing: 0) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(suggestion.title)
                                        .font(AMENFont.semiBold(15))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text(suggestion.subtitle)
                                        .font(AMENFont.regular(13))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: "arrow.right")
                                    .font(.systemScaled(13, weight: .medium))
                                    .foregroundStyle(Color(.tertiaryLabel))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(AMENSuggestionRowStyle())
                        .accessibilityLabel(suggestion.title)

                        if index < rows.count - 1 {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(.systemBackground).opacity(0.98))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(Color.black.opacity(0.05), lineWidth: 1)
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
        .padding(.top, 12)
    }

    // MARK: - Suggestion rows (live + defaults)

    private var suggestionRows: [AMENSearchSuggestion] {
        if !suggestions.isEmpty {
            return Array(suggestions.prefix(5))
        }
        guard showDefaultSuggestions else { return [] }
        let defaults: [AMENSearchSuggestion] = [
            .make("Prayer requests",   subtitle: "Quick search"),
            .make("Church Notes",      subtitle: "Jump directly into content"),
            .make("Testimonies",       subtitle: "Quick search"),
            .make("Find a Church",     subtitle: "Jump directly into content"),
            .make("Berean answers",    subtitle: "Quick search"),
        ]
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            return defaults
        }
        let lower = query.lowercased()
        let filtered = defaults.filter { $0.title.lowercased().contains(lower) }
        return filtered.isEmpty ? defaults : filtered
    }

    // MARK: - Cancel

    private func cancel() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        isFocused = false
        withAnimation(fastSpring) {
            query     = ""
            showPanel = false
        }
        onCancel?()
    }
}

// MARK: - Button Styles

struct AMENChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .offset(y: configuration.isPressed ? 1 : 0)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct AMENSuggestionRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.black.opacity(0.03) : Color.clear)
            .offset(x: configuration.isPressed ? 3 : 0)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

// MARK: - Compact variant (no panel, just the pill — for toolbar / navigation bar)

struct AMENCompactSearchField: View {
    @Binding var query: String
    var placeholder: String = "Search..."
    var onSubmit: ((String) -> Void)? = nil
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.systemScaled(14, weight: .medium))
                .foregroundStyle(.secondary)

            TextField(placeholder, text: $query)
                .font(AMENFont.regular(15))
                .foregroundStyle(.primary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($isFocused)
                .submitLabel(.search)
                .onSubmit { onSubmit?(query) }

            if !query.isEmpty {
                Button {
                    withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.8))) { query = "" }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.systemScaled(14))
                        .foregroundStyle(Color(.tertiaryLabel))
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(Color(.systemGray6))
                .overlay(Capsule().strokeBorder(Color.black.opacity(0.05), lineWidth: 1))
        )
    }
}

// MARK: - Preview

#if DEBUG
#Preview("AMENSearchBar — expanded") {
    @Previewable @State var q = ""
    ScrollView {
        VStack(spacing: 24) {
            AMENSearchBar(
                query: $q,
                filterChips: ["Prayer", "Church Notes", "Testimonies", "People", "Resources"]
            )
            Spacer(minLength: 300)
        }
        .padding(20)
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("AMENCompactSearchField") {
    @Previewable @State var q = ""
    AMENCompactSearchField(query: $q, placeholder: "Search followers...")
        .padding(20)
        .background(Color(.systemGroupedBackground))
}
#endif
