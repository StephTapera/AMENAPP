// BereanChurchFinderView.swift
// AMENAPP — Phase 5: Conversational church search
//
// Keeps the full conversation history so users can say "smaller please" or
// "any Saturday services?" and the backend gets previousSearchId for context.
//
// Entry points:
//   • "Ask Berean" button on SmartCommunityResultCard  → seeded with that result
//   • Toolbar "Chat" button in SmartCommunitySearchView → blank start

import SwiftUI
import UIKit

// MARK: - Turn model

struct ChurchFinderTurn: Identifiable {
    enum Role { case user, assistant }
    let id = UUID()
    let role: Role
    let text: String
    let results: [SmartCommunityRankedResult]
    let refinements: [String]
    let searchId: String?
    let isError: Bool

    static func user(_ text: String) -> Self {
        .init(role: .user, text: text, results: [], refinements: [], searchId: nil, isError: false)
    }

    static func assistant(
        text: String,
        results: [SmartCommunityRankedResult],
        refinements: [String],
        searchId: String?
    ) -> Self {
        .init(role: .assistant, text: text, results: results, refinements: refinements, searchId: searchId, isError: false)
    }

    static func error(_ message: String) -> Self {
        .init(role: .assistant, text: message, results: [], refinements: [], searchId: nil, isError: true)
    }
}

// MARK: - ViewModel

@MainActor
final class BereanChurchFinderViewModel: ObservableObject {
    @Published var queryText = ""
    @Published private(set) var turns: [ChurchFinderTurn] = []
    @Published private(set) var isSearching = false

    private let searchService = SmartCommunitySearchService.shared
    private let locationManager = SmartCommunityLocationManager.shared

    var lastSearchId: String? {
        turns.last(where: { $0.role == .assistant && !$0.isError })?.searchId
    }

    // Seed with a church result the user tapped "Ask Berean" on
    init(seedResult: SmartCommunityRankedResult? = nil, seedQuery: String? = nil) {
        if let result = seedResult {
            let q = "Tell me more about \(result.title) and why it may fit what I'm looking for."
            turns.append(.user(q))
            Task { await performSearch(query: q) }
        } else if let query = seedQuery, !query.isEmpty {
            turns.append(.user(query))
            Task { await performSearch(query: query) }
        }
    }

    func submit() {
        let trimmed = queryText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !isSearching else { return }
        queryText = ""
        turns.append(.user(trimmed))
        Task { await performSearch(query: trimmed) }
    }

    func applyRefinement(_ chip: String) {
        guard !isSearching else { return }
        turns.append(.user(chip))
        Task { await performSearch(query: chip) }
    }

    private func performSearch(query: String) async {
        isSearching = true
        defer { isSearching = false }

        do {
            let response = try await searchService.search(
                query: query,
                location: locationManager.locationState.searchLocation,
                surface: .findChurch,
                previousSearchId: lastSearchId
            )
            let intro = buildIntro(for: response)
            turns.append(.assistant(
                text: intro,
                results: Array(response.results.prefix(5)),
                refinements: response.refinementSuggestions,
                searchId: response.searchId
            ))
        } catch {
            guard !(error is CancellationError) else { return }
            turns.append(.error("I had trouble searching right now. Try rephrasing?"))
        }
    }

    private func buildIntro(for response: SmartCommunitySearchResponse) -> String {
        let n = response.results.count
        guard n > 0 else {
            return "I didn't find anything matching that. Try adjusting your search — smaller radius, different ministry focus, or broader denomination."
        }
        return n == 1 ? "Here's 1 option that may fit." : "Here are \(n) options that may fit."
    }
}

// MARK: - View

struct BereanChurchFinderView: View {
    @StateObject private var viewModel: BereanChurchFinderViewModel
    @FocusState private var composerFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(seedResult: SmartCommunityRankedResult? = nil, seedQuery: String? = nil) {
        _viewModel = StateObject(
            wrappedValue: BereanChurchFinderViewModel(seedResult: seedResult, seedQuery: seedQuery)
        )
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                finderBackground.ignoresSafeArea()
                VStack(spacing: 0) {
                    conversationScroll
                    composerBar
                }
            }
            .navigationTitle("Find a Church")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: Background

    private var finderBackground: some View {
        ZStack {
            Color(red: 0.956, green: 0.956, blue: 0.936)
            LinearGradient(
                colors: [
                    Color.white.opacity(0.78),
                    Color(red: 0.94, green: 0.95, blue: 0.93).opacity(0.72),
                    Color(red: 0.98, green: 0.965, blue: 0.94).opacity(0.58)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    // MARK: Conversation

    private var conversationScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if viewModel.turns.isEmpty {
                        welcomeView
                    }
                    ForEach(viewModel.turns) { turn in
                        turnRow(turn).id(turn.id)
                    }
                    if viewModel.isSearching {
                        thinkingRow.id("typing")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 104) // clear the composer
            }
            .onChange(of: viewModel.turns.count) { _ in
                guard let lastId = viewModel.turns.last?.id else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
                    proxy.scrollTo(lastId, anchor: .bottom)
                }
            }
            .onChange(of: viewModel.isSearching) { searching in
                if searching {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                        proxy.scrollTo("typing", anchor: .bottom)
                    }
                }
            }
        }
    }

    private var welcomeView: some View {
        VStack(spacing: 16) {
            Image(systemName: "building.columns.fill")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Color(red: 0.60, green: 0.50, blue: 0.28))
            Text("Tell me about the church you're looking for")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            Text("Describe the vibe, community needs, worship style, or ministries that matter to you.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            // Quick-start chips
            suggestionChips([
                "Charismatic non-denom, young adults ministry",
                "Small church, strong Bible teaching",
                "Family-friendly with Spanish service",
                "Recovery community, welcoming to newcomers",
            ])
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
        .padding(.bottom, 32)
    }

    private func suggestionChips(_ items: [String]) -> some View {
        VStack(alignment: .center, spacing: 8) {
            ForEach(items, id: \.self) { item in
                Button { viewModel.queryText = item } label: {
                    Text(item)
                        .font(.caption)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                }
                .foregroundStyle(.primary)
                .accessibilityLabel("Try: \(item)")
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }

    // MARK: Turn rows

    @ViewBuilder
    private func turnRow(_ turn: ChurchFinderTurn) -> some View {
        switch turn.role {
        case .user:
            userBubble(turn.text).padding(.bottom, 10)
        case .assistant:
            assistantTurn(turn).padding(.bottom, 18)
        }
    }

    private func userBubble(_ text: String) -> some View {
        HStack {
            Spacer(minLength: 60)
            Text(text)
                .font(.body)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    Color(red: 0.25, green: 0.25, blue: 0.25),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
        }
        .accessibilityLabel("You said: \(text)")
    }

    private func assistantTurn(_ turn: ChurchFinderTurn) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Intro / error text
            if !turn.text.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: turn.isError ? "exclamationmark.circle" : "sparkles")
                        .font(.caption)
                        .foregroundStyle(
                            turn.isError
                                ? Color.orange
                                : Color(red: 0.60, green: 0.50, blue: 0.28)
                        )
                        .padding(.top, 3)
                    Text(turn.text)
                        .font(.subheadline)
                        .foregroundStyle(turn.isError ? .orange : .primary)
                }
                .accessibilityLabel(turn.text)
            }

            // Inline result cards (cap at 3 to keep conversation readable)
            if !turn.results.isEmpty {
                VStack(spacing: 10) {
                    ForEach(turn.results.prefix(3)) { result in
                        SmartCommunityResultCard(
                            result: result,
                            onAction: { handleAction($0, result: result) },
                            onAskBerean: { r in
                                viewModel.queryText = "Tell me more about \(r.title)"
                                viewModel.submit()
                            }
                        )
                    }
                    if turn.results.count > 3 {
                        Text("+\(turn.results.count - 3) more matched")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 4)
                    }
                }
            }

            // Refinement chips
            if !turn.refinements.isEmpty {
                refinementChipRow(turn.refinements)
            }
        }
    }

    private func refinementChipRow(_ chips: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chips, id: \.self) { chip in
                    Button { viewModel.applyRefinement(chip) } label: {
                        Text(chip)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay(Capsule().stroke(Color.primary.opacity(0.1), lineWidth: 1))
                    }
                    .foregroundStyle(.primary)
                    .disabled(viewModel.isSearching)
                    .accessibilityLabel("Refine: \(chip)")
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var thinkingRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.caption)
                .foregroundStyle(Color(red: 0.60, green: 0.50, blue: 0.28))
            Text("Searching...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .accessibilityLabel("Berean is searching")
    }

    // MARK: Composer

    private var composerBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Refine or start a new search…", text: $viewModel.queryText, axis: .vertical)
                .font(.body)
                .lineLimit(1...4)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                )
                .focused($composerFocused)
                .submitLabel(.send)
                .onSubmit {
                    viewModel.submit()
                }
                .accessibilityLabel("Church search message")

            Button {
                viewModel.submit()
                composerFocused = false
            } label: {
                Image(systemName: viewModel.isSearching ? "hourglass" : "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(sendButtonColor)
                    .animation(.easeInOut(duration: 0.15), value: viewModel.isSearching)
            }
            .disabled(viewModel.queryText.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isSearching)
            .accessibilityLabel(viewModel.isSearching ? "Searching" : "Send")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(Color.primary.opacity(0.06)),
            alignment: .top
        )
    }

    private var sendButtonColor: Color {
        if viewModel.isSearching {
            return .secondary
        }
        if viewModel.queryText.trimmingCharacters(in: .whitespaces).isEmpty {
            return .secondary
        }
        return Color(red: 0.60, green: 0.50, blue: 0.28)
    }

    // MARK: Action handler

    private func handleAction(_ action: SmartCommunityAction, result: SmartCommunityRankedResult) {
        Task { await SmartCommunitySearchService.shared.logInteraction(event: action.type.rawValue, result: result) }

        switch action.type {
        case .directions:
            let urlString = action.payload?["mapsUrl"] ?? action.payload?["url"]
            if let raw = urlString, let url = URL(string: raw) {
                UIApplication.shared.open(url)
            } else if let coord = result.locationCoord {
                let url = URL(string: "maps://?daddr=\(coord.lat),\(coord.lng)")!
                UIApplication.shared.open(url)
            }
        case .view:
            if let raw = action.payload?["url"], let url = URL(string: raw) {
                UIApplication.shared.open(url)
            }
        default:
            break
        }
    }
}
