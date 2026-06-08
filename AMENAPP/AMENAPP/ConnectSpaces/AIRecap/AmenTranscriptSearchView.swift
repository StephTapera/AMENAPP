// AmenTranscriptSearchView.swift
// AMEN Connect + Spaces — Transcript Search
// Built 2026-06-02

import SwiftUI
import FirebaseFunctions

// MARK: - ViewModel

@MainActor
private final class AmenTranscriptSearchViewModel: ObservableObject {
    @Published var query: String = ""
    @Published var results: [AmenTranscriptSegment] = []
    @Published var isSearching: Bool = false
    @Published var searchError: String?

    private var debounceTask: Task<Void, Never>?
    private let functions = Functions.functions()
    let sourceRef: String

    init(sourceRef: String) {
        self.sourceRef = sourceRef
    }

    func onQueryChanged(_ newValue: String) {
        debounceTask?.cancel()
        guard !newValue.trimmingCharacters(in: .whitespaces).isEmpty else {
            results = []
            isSearching = false
            searchError = nil
            return
        }
        debounceTask = Task {
            // 300ms debounce
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await performSearch(query: newValue)
        }
    }

    private func performSearch(query: String) async {
        isSearching = true
        searchError = nil
        defer { isSearching = false }

        do {
            let callable = functions.httpsCallable(AmenSpacesPhase1Callable.searchTranscripts.rawValue)
            let result = try await callable.call(["sourceRef": sourceRef, "query": query])
            guard let data = result.data as? [String: Any],
                  let rows = data["segments"] as? [[String: Any]] else {
                results = []
                return
            }
            results = rows.compactMap { row -> AmenTranscriptSegment? in
                guard let id = row["id"] as? String,
                      let text = row["text"] as? String,
                      let startSecs = row["startSecs"] as? TimeInterval,
                      let endSecs = row["endSecs"] as? TimeInterval,
                      let speakerId = row["speakerId"] as? String else { return nil }
                return AmenTranscriptSegment(
                    id: id,
                    sourceRef: sourceRef,
                    text: text,
                    startSecs: startSecs,
                    endSecs: endSecs,
                    speakerId: speakerId,
                    searchScore: row["searchScore"] as? Double
                )
            }
        } catch {
            searchError = error.localizedDescription
            results = []
        }
    }
}

// MARK: - Timestamp formatter

private func formatTimestamp(_ secs: TimeInterval) -> String {
    let totalSeconds = Int(secs)
    let minutes = totalSeconds / 60
    let seconds = totalSeconds % 60
    return String(format: "%d:%02d", minutes, seconds)
}

// MARK: - Highlighted attributed text

private func highlightedText(_ text: String, query: String) -> AttributedString {
    var attributed = AttributedString(text)
    guard !query.isEmpty else { return attributed }
    let lowercasedText = text.lowercased()
    let lowercasedQuery = query.lowercased()
    var searchRange = lowercasedText.startIndex..<lowercasedText.endIndex
    while let range = lowercasedText.range(of: lowercasedQuery, range: searchRange) {
        if let attrRange = Range(range, in: attributed) {
            attributed[attrRange].foregroundColor = Color(hex: "D9A441")
            attributed[attrRange].font = Font.systemScaled(14, weight: .semibold)
        }
        searchRange = range.upperBound..<lowercasedText.endIndex
    }
    return attributed
}

// MARK: - Transcript Row

private struct TranscriptResultRow: View {
    let segment: AmenTranscriptSegment
    let query: String
    let onJump: (TimeInterval) -> Void

    var body: some View {
        Button {
            onJump(segment.startSecs)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                // Timestamp badge — glass pill (chrome control)
                Text(formatTimestamp(segment.startSecs))
                    .font(.systemScaled(11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color(hex: "D9A441"))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background {
                        Capsule().fill(.ultraThinMaterial)
                            .overlay {
                                Capsule().strokeBorder(Color(hex: "D9A441").opacity(0.35), lineWidth: 1)
                            }
                    }
                    .frame(minWidth: 44, alignment: .center)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(segment.speakerId)
                        .font(.systemScaled(11, weight: .semibold))
                        .foregroundStyle(Color(hex: "6E4BB5"))
                        .lineLimit(1)

                    Text(highlightedText(segment.text, query: query))
                        .font(.systemScaled(14))
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Image(systemName: "play.circle")
                    .font(.systemScaled(18))
                    .foregroundStyle(Color.white.opacity(0.35))
                    .accessibilityHidden(true)
            }
            .padding(12)
            .background(Color(hex: "070607"))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Jump to \(formatTimestamp(segment.startSecs)), speaker \(segment.speakerId): \(segment.text)")
        .accessibilityHint("Activates to jump to this point in the recording")
    }
}

// MARK: - Main View

struct AmenTranscriptSearchView: View {
    let sourceRef: String
    let sourceTitle: String
    let onJumpToTimestamp: (TimeInterval) -> Void

    @StateObject private var viewModel: AmenTranscriptSearchViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(sourceRef: String, sourceTitle: String, onJumpToTimestamp: @escaping (TimeInterval) -> Void) {
        self.sourceRef = sourceRef
        self.sourceTitle = sourceTitle
        self.onJumpToTimestamp = onJumpToTimestamp
        _viewModel = StateObject(wrappedValue: AmenTranscriptSearchViewModel(sourceRef: sourceRef))
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
                .opacity(0.15)

            Group {
                if viewModel.isSearching {
                    loadingState
                } else if let error = viewModel.searchError {
                    errorState(error)
                } else if viewModel.results.isEmpty && !viewModel.query.isEmpty {
                    noResultsState
                } else if viewModel.results.isEmpty {
                    emptyState
                } else {
                    resultsList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(hex: "070607"))
        .onChange(of: viewModel.query) { _, newValue in
            viewModel.onQueryChanged(newValue)
        }
    }

    // MARK: - Search bar (glass pill — chrome control)

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.systemScaled(15))
                .foregroundStyle(Color.white.opacity(0.5))
                .accessibilityHidden(true)

            TextField("Search transcript…", text: $viewModel.query)
                .font(.systemScaled(15))
                .foregroundStyle(.primary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityLabel("Search transcript")

            if !viewModel.query.isEmpty {
                Button {
                    viewModel.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.systemScaled(15))
                        .foregroundStyle(Color.white.opacity(0.4))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background {
            Capsule().fill(.ultraThinMaterial)
                .overlay { Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - States

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.systemScaled(40))
                .foregroundStyle(Color.white.opacity(0.25))
                .accessibilityHidden(true)
            Text("Search across the full transcript")
                .font(.systemScaled(15, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Type a word or phrase to find moments in \(sourceTitle)")
                .font(.systemScaled(13))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Search the full transcript of \(sourceTitle)")
    }

    private var noResultsState: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.systemScaled(36))
                .foregroundStyle(Color.white.opacity(0.2))
                .accessibilityHidden(true)
            Text("No results found")
                .font(.systemScaled(15, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("Try different keywords or a shorter phrase.")
                .font(.systemScaled(13))
                .foregroundStyle(.tertiary)
        }
        .accessibilityLabel("No transcript results found for \(viewModel.query)")
    }

    private var loadingState: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(Color(hex: "6E4BB5"))
            Text("Searching…")
                .font(.systemScaled(13))
                .foregroundStyle(.secondary)
        }
        .accessibilityLabel("Searching transcript")
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.systemScaled(32))
                .foregroundStyle(Color.orange.opacity(0.7))
                .accessibilityHidden(true)
            Text("Search unavailable")
                .font(.systemScaled(15, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.systemScaled(12))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .accessibilityLabel("Search error: \(message)")
    }

    // MARK: - Results

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(viewModel.results) { segment in
                    TranscriptResultRow(
                        segment: segment,
                        query: viewModel.query,
                        onJump: onJumpToTimestamp
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        AmenTranscriptSearchView(
            sourceRef: "video-001",
            sourceTitle: "Sunday Morning Teaching",
            onJumpToTimestamp: { _ in }
        )
        .navigationTitle("Transcript Search")
        .navigationBarTitleDisplayMode(.inline)
    }
    .preferredColorScheme(.dark)
}
