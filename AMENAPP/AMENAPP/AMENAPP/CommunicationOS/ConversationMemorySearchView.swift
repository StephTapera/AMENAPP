// ConversationMemorySearchView.swift
// AMENAPP
//
// Natural-language search over conversation history.
// Powered by searchConversationMemory Cloud Function.
// Gated by conversationMemorySearchEnabled.

import SwiftUI
import FirebaseFunctions

struct ConversationMemoryResult: Identifiable {
    let id: String
    let snippet: String
    let type: String
    let messageId: String?
    let timestamp: String?
}

enum ConversationMemorySearchState {
    case idle, loading, results([ConversationMemoryResult]), empty, failed
}

@MainActor
final class ConversationMemorySearchViewModel: ObservableObject {
    @Published var query: String = ""
    @Published var state: ConversationMemorySearchState = .idle

    private var searchTask: Task<Void, Never>?
    private let debounceDelay: TimeInterval = 0.45

    let conversationId: String

    init(conversationId: String) {
        self.conversationId = conversationId
    }

    func search() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { state = .idle; return }
        guard AMENFeatureFlags.shared.conversationMemorySearchEnabled else { return }
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(debounceDelay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            state = .loading
            do {
                let functions = Functions.functions()
                let result = try await functions.httpsCallable("searchConversationMemory").call([
                    "conversationId": conversationId,
                    "query": trimmed
                ])
                guard !Task.isCancelled else { return }
                if let data = result.data as? [String: Any],
                   let items = data["results"] as? [[String: Any]] {
                    let results = items.compactMap { dict -> ConversationMemoryResult? in
                        guard let id = dict["id"] as? String,
                              let snippet = dict["snippet"] as? String else { return nil }
                        return ConversationMemoryResult(
                            id: id,
                            snippet: snippet,
                            type: dict["type"] as? String ?? "message",
                            messageId: dict["messageId"] as? String,
                            timestamp: dict["timestamp"] as? String
                        )
                    }
                    state = results.isEmpty ? .empty : .results(results)
                    AmenMessagingAnalytics.track(.conversationMemorySearch, parameters: ["resultCount": items.count])
                } else {
                    state = .empty
                }
            } catch {
                guard !Task.isCancelled else { return }
                state = .failed
            }
        }
    }

    func clear() {
        searchTask?.cancel()
        query = ""
        state = .idle
    }
}

struct ConversationMemorySearchView: View {
    @StateObject var viewModel: ConversationMemorySearchViewModel
    var onSelectResult: (ConversationMemoryResult) -> Void
    var onDismiss: () -> Void

    init(conversationId: String, onSelectResult: @escaping (ConversationMemoryResult) -> Void, onDismiss: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: ConversationMemorySearchViewModel(conversationId: conversationId))
        self.onSelectResult = onSelectResult
        self.onDismiss = onDismiss
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                Divider()
                resultArea
            }
            .navigationTitle("Search Conversation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: onDismiss)
                }
            }
        }
        .onChange(of: viewModel.query) { _, _ in viewModel.search() }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("What changed since yesterday?", text: $viewModel.query)
                .autocorrectionDisabled()
                .accessibilityLabel("Search conversation history")
            if !viewModel.query.isEmpty {
                Button { viewModel.clear() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var resultArea: some View {
        switch viewModel.state {
        case .idle:
            idleSuggestions
        case .loading:
            ProgressView("Searching…").padding(40)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .results(let items):
            resultsList(items)
        case .empty:
            emptyState
        case .failed:
            failedState
        }
    }

    private var idleSuggestions: some View {
        List {
            Section("Try asking") {
                ForEach(["What changed since yesterday?",
                         "Show unresolved questions",
                         "Show decisions",
                         "Who owns this?",
                         "Show media from last week"], id: \.self) { suggestion in
                    Button { viewModel.query = suggestion } label: {
                        HStack {
                            Image(systemName: "sparkle").foregroundStyle(.secondary).font(.caption)
                            Text(suggestion).font(.subheadline)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func resultsList(_ items: [ConversationMemoryResult]) -> some View {
        List(items) { item in
            Button { onSelectResult(item) } label: {
                resultRow(item)
            }
            .buttonStyle(.plain)
        }
        .listStyle(.insetGrouped)
    }

    private func resultRow(_ item: ConversationMemoryResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                resultTypeBadge(item.type)
                Spacer()
                if let ts = item.timestamp {
                    Text(ts).font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Text(item.snippet)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(3)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.type): \(item.snippet)")
    }

    private func resultTypeBadge(_ type: String) -> some View {
        Text(type.capitalized)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.12), in: Capsule())
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass").font(.largeTitle).foregroundStyle(.tertiary)
            Text("No results found").font(.headline)
            Text("Try a different question or phrase.").font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var failedState: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle").font(.largeTitle).foregroundStyle(.secondary)
            Text("Search failed").font(.headline)
            Button("Retry") { viewModel.search() }
                .buttonStyle(.borderedProminent)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
