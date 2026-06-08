// AmenMinistryMemorySearchView.swift
// AMEN Connect + Spaces — Liquid Intelligence Seam (Agent 9)
//
// Ministry memory search: "Show me every time Pastor mentioned the building-fund timeline."
// Glass chrome (search bar, result pills). Matte content (transcripts, cards).
//
// Frozen contracts: ConnectSpacesPhase0Contracts.swift — do not modify.
// Callable proxy: AmenConnectSpacesPhase0BindingService.swift

import SwiftUI
import FirebaseAuth

// MARK: - Color helpers (file-local, matching frozen design tokens)

// MARK: - Hint chip labels

private let searchHintChips: [String] = [
    "Scripture", "Decisions", "Prayer requests", "Tasks", "Sermons", "People"
]

// MARK: - ViewModel

@MainActor
final class AmenMinistryMemorySearchViewModel: ObservableObject {

    @Published var query: String = ""
    @Published var results: [AmenConnectSpacesMinistryMemoryResult] = []
    @Published var isLoading: Bool = false
    @Published var hasError: Bool = false
    @Published var expandedResultIds: Set<String> = []

    let spaceId: String

    init(spaceId: String) {
        self.spaceId = spaceId
    }

    func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isLoading = true
        hasError = false
        results = []
        expandedResultIds = []
        do {
            results = try await AmenConnectSpacesCallableProxy.shared.searchMinistryMemory(
                spaceId: spaceId,
                query: trimmed,
                limit: 20
            )
        } catch {
            hasError = true
        }
        isLoading = false
    }

    func toggleExpanded(_ id: String) {
        if expandedResultIds.contains(id) {
            expandedResultIds.remove(id)
        } else {
            expandedResultIds.insert(id)
        }
    }

    func appendHintChip(_ chip: String) {
        if query.isEmpty {
            query = chip
        } else if !query.hasSuffix(" ") {
            query += " \(chip)"
        } else {
            query += chip
        }
    }

    /// Formats a TimeInterval (seconds) as "MM:SS".
    func formattedTimestamp(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    /// Returns a confidence dot count (1–5) from the confidence value (0.0–1.0).
    func confidenceDots(_ confidence: Double) -> Int {
        max(1, min(5, Int((confidence * 5).rounded())))
    }
}

// MARK: - Main view

struct AmenMinistryMemorySearchView: View {

    let spaceId: String

    @StateObject private var vm: AmenMinistryMemorySearchViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var searchFocused: Bool

    init(spaceId: String) {
        self.spaceId = spaceId
        _vm = StateObject(wrappedValue: AmenMinistryMemorySearchViewModel(spaceId: spaceId))
    }

    var body: some View {
        VStack(spacing: 0) {
            glassSearchBar
            hintChipsRow
            Divider()
            resultsContent
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Ministry Memory")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Glass search bar

    private var glassSearchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(searchFocused ? Color.accentColor : Color.amenBlack.opacity(0.4))
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: searchFocused)

            TextField("Search ministry memory…", text: $vm.query)
                .font(.body)
                .foregroundStyle(Color.amenBlack)
                .submitLabel(.search)
                .focused($searchFocused)
                .onSubmit {
                    Task { await vm.search() }
                }
                .accessibilityLabel("Search ministry memory")

            if !vm.query.isEmpty {
                Button {
                    vm.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.amenBlack.opacity(0.35))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            searchFocused ? Color.accentColor : Color.white.opacity(0.28),
                            lineWidth: searchFocused ? 1.5 : 0.5
                        )
                )
        )
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    // MARK: - Hint chip row (glass pills)

    private var hintChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(searchHintChips, id: \.self) { chip in
                    Button {
                        vm.appendHintChip(chip)
                    } label: {
                        Text(chip)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.amenBlue)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(.ultraThinMaterial)
                                    .overlay(
                                        Capsule(style: .continuous)
                                            .strokeBorder(Color.amenBlue.opacity(0.35), lineWidth: 0.5)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Filter by \(chip)")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Results content

    @ViewBuilder
    private var resultsContent: some View {
        if vm.isLoading {
            skeletonList
        } else if vm.hasError {
            errorState
        } else if vm.results.isEmpty && !vm.query.isEmpty {
            emptyState
        } else {
            resultsList
        }
    }

    // MARK: - Skeleton (matte shimmer rows)

    private var skeletonList: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(0..<3, id: \.self) { _ in
                    skeletonRow
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
    }

    private var skeletonRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(.systemFill))
                .frame(height: 14)
                .frame(maxWidth: 120)

            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(.systemFill))
                .frame(height: 12)
                .frame(maxWidth: .infinity)

            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(.systemFill))
                .frame(height: 12)
                .frame(maxWidth: 200)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .accessibilityLabel("Loading result")
        .accessibilityHidden(true)
    }

    // MARK: - Results list

    private var resultsList: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(vm.results) { result in
                    resultCard(result)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
    }

    private func resultCard(_ result: AmenConnectSpacesMinistryMemoryResult) -> some View {
        let isExpanded = vm.expandedResultIds.contains(result.id)
        return VStack(alignment: .leading, spacing: 10) {
            // Timestamp + video ID
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.caption2)
                    .foregroundStyle(Color.amenBlack.opacity(0.4))
                    .accessibilityHidden(true)

                Text(vm.formattedTimestamp(result.timestampSeconds))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.amenBlack.opacity(0.7))
                    .accessibilityLabel("At \(vm.formattedTimestamp(result.timestampSeconds))")

                Text("·")
                    .font(.caption)
                    .foregroundStyle(Color.amenBlack.opacity(0.3))
                    .accessibilityHidden(true)

                Text(result.videoId.prefix(12))
                    .font(.caption)
                    .foregroundStyle(Color.amenBlue)
                    .accessibilityLabel("Video \(result.videoId.prefix(12))")
            }

            // Transcript excerpt (matte — never glass)
            Button {
                vm.toggleExpanded(result.id)
            } label: {
                Text(result.transcriptExcerpt)
                    .font(.subheadline)
                    .foregroundStyle(Color.amenBlack)
                    .lineLimit(isExpanded ? nil : 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: isExpanded)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(result.transcriptExcerpt)
            .accessibilityHint(isExpanded ? "Tap to collapse" : "Tap to expand full excerpt")

            // Owner label (amenPurple)
            if let owner = result.owner, !owner.isEmpty {
                Label(owner, systemImage: "person.circle")
                    .font(.caption)
                    .foregroundStyle(Color.amenPurple)
                    .accessibilityLabel("Owner: \(owner)")
            }

            // Bottom row: action item badge + confidence dots
            HStack(spacing: 8) {
                // Action item badge (glass pill)
                if result.actionItemId != nil {
                    Text("Action item")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(.label))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    Capsule(style: .continuous)
                                        .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 0.5)
                                )
                        )
                        .accessibilityLabel("Has linked action item")
                }

                Spacer()

                // Confidence dots (private visual indicator — no percentage)
                confidenceDotsView(vm.confidenceDots(result.confidence))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.amenBlack.opacity(0.06), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
    }

    /// Five dots, filled count indicates confidence. No text percentage label (private metric).
    private func confidenceDotsView(_ filled: Int) -> some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { index in
                Circle()
                    .fill(index <= filled ? Color.amenPurple : Color.amenBlack.opacity(0.12))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityLabel("Relevance: \(filled) out of 5")
        .accessibilityHidden(false)
    }

    // MARK: - Empty state (matte)

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.systemScaled(40, weight: .light))
                .foregroundStyle(Color.accentColor.opacity(0.6))
            Text("Nothing found. Try a different phrasing.")
                .font(.subheadline)
                .foregroundStyle(Color.amenBlack.opacity(0.55))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 64)
        .padding(.horizontal, 32)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No results found. Try a different phrasing.")
    }

    // MARK: - Error state (matte)

    private var errorState: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.systemScaled(36, weight: .light))
                .foregroundStyle(Color.amenBlack.opacity(0.25))
            Text("Search unavailable right now.")
                .font(.subheadline)
                .foregroundStyle(Color.amenBlack.opacity(0.55))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 64)
        .padding(.horizontal, 32)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Search unavailable right now.")
    }
}
