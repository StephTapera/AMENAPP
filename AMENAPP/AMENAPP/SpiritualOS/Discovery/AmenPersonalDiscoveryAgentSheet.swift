// AmenPersonalDiscoveryAgentSheet.swift
// AMEN App — Spiritual OS / Community Discovery
//
// AI-powered Personal Discovery Agent sheet — AMEN+ exclusive.
// Presented as a .large bottom sheet from AmenDiscoveryRailsView.
//
// The agent accepts a natural-language prompt and returns ranked
// discovery results (churches, spaces, people, studies) drawn from
// the Firestore graph. Phase 1: static prompt → results mockup.
//
// Design rules (C3):
//   • Background: .ultraThinMaterial over system default — no dark panel
//   • Accent: Color.accentColor only
//   • Fonts: Dynamic Type only — NO Cormorant Garamond

import SwiftUI

// MARK: - AmenPersonalDiscoveryAgentSheet

struct AmenPersonalDiscoveryAgentSheet: View {

    // MARK: Input

    @Binding var isPresented: Bool

    // MARK: State

    @State private var query = ""
    @State private var isSearching = false
    @State private var suggestions: [DiscoverySuggestion] = []
    @FocusState private var fieldFocused: Bool

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    headerSection
                    searchField
                    if !suggestions.isEmpty {
                        suggestionsSection
                    } else if !query.isEmpty && !isSearching {
                        emptyResultsView
                    } else if query.isEmpty {
                        promptChips
                    }
                }
                .padding(20)
                .padding(.bottom, 32)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { isPresented = false }
                        .foregroundStyle(Color.accentColor)
                }
                if isSearching {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        ProgressView()
                            .tint(Color.accentColor)
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.10))
                    .frame(width: 64, height: 64)

                Image(systemName: "sparkles")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .accessibilityHidden(true)

            Text("Personal Discovery Agent")
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)

            Text("Describe what you're looking for and your agent will find communities, people, and studies that fit your faith journey.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Personal Discovery Agent. Describe what you're looking for.")
    }

    // MARK: - Search Field

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField("What are you looking for?", text: $query, axis: .vertical)
                .font(.body)
                .lineLimit(1...4)
                .focused($fieldFocused)
                .submitLabel(.search)
                .onSubmit { runSearch() }

            if !query.isEmpty {
                Button {
                    query = ""
                    suggestions = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .onChange(of: query) { _, newValue in
            if newValue.isEmpty { suggestions = [] }
        }
    }

    // MARK: - Prompt chips

    private var promptChips: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Try asking…")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            FlowLayout(spacing: 8) {
                ForEach(DiscoverySuggestion.examplePrompts, id: \.self) { prompt in
                    Button {
                        query = prompt
                        runSearch()
                    } label: {
                        Text(prompt)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                Capsule()
                                    .fill(Color.accentColor.opacity(0.10))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Search: \(prompt)")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Suggestions List

    private var suggestionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Results for you")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 10) {
                ForEach(suggestions) { suggestion in
                    DiscoverySuggestionRow(suggestion: suggestion)
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyResultsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)

            Text("No results found")
                .font(.headline)
                .foregroundStyle(.primary)

            Text("Try describing your faith interests or the kind of community you're looking for.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 32)
    }

    // MARK: - Search

    private func runSearch() {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        fieldFocused = false
        isSearching = true
        suggestions = []

        // Phase 1: Simulated results — Phase 2 wires to Firestore search CF
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800))
            suggestions = DiscoverySuggestion.mockResults(for: query)
            isSearching = false
        }
    }
}

// MARK: - DiscoverySuggestion

struct DiscoverySuggestion: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let category: Category
    let iconName: String

    enum Category: String {
        case church    = "church"
        case space     = "space"
        case person    = "person"
        case study     = "study"

        var label: String {
            switch self {
            case .church:  return "Church"
            case .space:   return "Space"
            case .person:  return "Person"
            case .study:   return "Study"
            }
        }
    }

    static let examplePrompts: [String] = [
        "Churches near me with strong youth programs",
        "Small group for new believers",
        "Bible study on Psalms",
        "Spaces for prayer and intercession",
        "Mentors for young professionals of faith",
    ]

    static func mockResults(for query: String) -> [DiscoverySuggestion] {
        let lower = query.lowercased()
        if lower.contains("church") || lower.contains("near") {
            return [
                DiscoverySuggestion(id: "c1", title: "Grace Community Church", subtitle: "2.4 mi · Active youth programs", category: .church, iconName: "building.columns"),
                DiscoverySuggestion(id: "c2", title: "Crossroads Fellowship", subtitle: "1.8 mi · Sunday services + small groups", category: .church, iconName: "building.columns"),
            ]
        } else if lower.contains("study") || lower.contains("psalm") || lower.contains("bible") {
            return [
                DiscoverySuggestion(id: "s1", title: "Psalms Through the Year", subtitle: "Scripture study · 340 members", category: .study, iconName: "book"),
                DiscoverySuggestion(id: "s2", title: "Morning Devotions Space", subtitle: "Daily readings community", category: .space, iconName: "sun.horizon"),
            ]
        } else if lower.contains("mentor") || lower.contains("professional") {
            return [
                DiscoverySuggestion(id: "p1", title: "Faith & Work Network", subtitle: "Space · Professionals of faith", category: .space, iconName: "briefcase"),
            ]
        } else {
            return [
                DiscoverySuggestion(id: "g1", title: "Believers Community Space", subtitle: "Open community · Prayer + fellowship", category: .space, iconName: "person.3"),
                DiscoverySuggestion(id: "g2", title: "New Members Bible Study", subtitle: "Study · Welcoming to all", category: .study, iconName: "book.closed"),
            ]
        }
    }
}

// MARK: - DiscoverySuggestionRow

private struct DiscoverySuggestionRow: View {
    let suggestion: DiscoverySuggestion

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.10))
                    .frame(width: 44, height: 44)

                Image(systemName: suggestion.iconName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(suggestion.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(suggestion.category.label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(Color(.tertiarySystemBackground))
                )
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(suggestion.title). \(suggestion.subtitle). \(suggestion.category.label).")
    }
}

// MARK: - FlowLayout (simple horizontal-wrapping layout)

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? UIScreen.main.bounds.width
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Preview

#Preview("Personal Discovery Agent Sheet") {
    @Previewable @State var shown = true
    Color(.systemGroupedBackground)
        .ignoresSafeArea()
        .sheet(isPresented: $shown) {
            AmenPersonalDiscoveryAgentSheet(isPresented: $shown)
        }
}
