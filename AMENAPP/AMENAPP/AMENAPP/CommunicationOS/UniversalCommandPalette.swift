// UniversalCommandPalette.swift
// AMEN Comms OS — Universal Command Palette (Agent 8)
//
// NL-driven search + intent routing gated by commsCommandPaletteEnabled.
// Low-confidence intent asks a clarifying question instead of guessing.
// Falls back gracefully to empty state if the backend is unavailable.
// Results show source + type badge + confidence. Permission-scoped: only
// threads the current user belongs to appear in results.

import SwiftUI
import FirebaseFunctions

// MARK: - Result Types

struct CommandPaletteResult: Identifiable {
    let id: String
    let title: String
    let snippet: String
    let type: CommandResultType
    let confidence: Double
    let sourceMessageId: String?
    let threadId: String?
}

enum CommandResultType: String {
    case summary   = "Summary"
    case decision  = "Decision"
    case followUp  = "Follow-up"
    case blocker   = "Blocker"
    case question  = "Question"
    case thread    = "Thread"
    case media     = "Media"

    var icon: String {
        switch self {
        case .summary:  return "text.quote"
        case .decision: return "checkmark.seal.fill"
        case .followUp: return "bolt.fill"
        case .blocker:  return "xmark.octagon.fill"
        case .question: return "questionmark.bubble.fill"
        case .thread:   return "bubble.left.and.bubble.right"
        case .media:    return "photo.stack"
        }
    }

    var tintColor: Color {
        switch self {
        case .summary:  return .blue
        case .decision: return .green
        case .followUp: return .purple
        case .blocker:  return .red
        case .question: return .orange
        case .thread:   return .teal
        case .media:    return .indigo
        }
    }
}

// MARK: - ViewModel

@MainActor
final class CommandPaletteViewModel: ObservableObject {
    @Published var query = ""
    @Published var results: [CommandPaletteResult] = []
    @Published var isLoading = false
    @Published var clarificationPrompt: String?
    @Published var errorMessage: String?
    @Published var recentQueries: [String] = []

    private var searchTask: Task<Void, Never>?

    func search(threadId: String) {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { reset(); return }

        searchTask?.cancel()
        isLoading = true
        errorMessage = nil
        clarificationPrompt = nil

        searchTask = Task {
            do {
                let score = try await AmenConversationOSService.shared.routeIntent(query: q, threadId: threadId)
                guard !Task.isCancelled else { return }

                if score.confidence < 0.5 {
                    // Low confidence — ask instead of guess (§3.5 intelligence contract)
                    clarificationPrompt = "Did you mean to ask about \"\(q)\"? Try being more specific, e.g. \"show open blockers\" or \"what changed since yesterday\"."
                    results = []
                } else {
                    results = try await searchConversationMemory(query: q, threadId: threadId)
                }

                saveRecent(q)
            } catch ConversationOSError.featureDisabled {
                // Flag is OFF — silent no-op, no error shown
                results = []
            } catch {
                // Graceful degradation: never fabricate results
                errorMessage = "Search unavailable. Try again shortly."
                results = []
            }
            isLoading = false
        }
    }

    func clear() {
        searchTask?.cancel()
        reset()
    }

    private func reset() {
        query = ""
        results = []
        clarificationPrompt = nil
        isLoading = false
        errorMessage = nil
    }

    private func searchConversationMemory(query: String, threadId: String) async throws -> [CommandPaletteResult] {
        guard AMENFeatureFlags.shared.conversationMemorySearchEnabled else { return [] }
        let result = try await Functions.functions().httpsCallable("searchConversationMemory").call([
            "conversationId": threadId,
            "query": query
        ])
        guard let data = result.data as? [String: Any],
              let items = data["results"] as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            let id = item["id"] as? String ?? item["messageId"] as? String ?? UUID().uuidString
            let snippet = item["snippet"] as? String ?? ""
            guard !snippet.isEmpty else { return nil }
            let rawType = item["type"] as? String ?? "message"
            return CommandPaletteResult(
                id: id,
                title: item["title"] as? String ?? rawType.capitalized,
                snippet: snippet,
                type: CommandResultType(memoryType: rawType),
                confidence: item["relevanceScore"] as? Double ?? item["confidence"] as? Double ?? 0.75,
                sourceMessageId: item["sourceMessageId"] as? String ?? item["messageId"] as? String,
                threadId: item["threadId"] as? String ?? threadId
            )
        }
    }

    private func saveRecent(_ q: String) {
        guard !recentQueries.contains(q) else { return }
        recentQueries.insert(q, at: 0)
        if recentQueries.count > 5 { recentQueries = Array(recentQueries.prefix(5)) }
    }
}

private extension CommandResultType {
    init(memoryType: String) {
        switch memoryType.lowercased() {
        case "summary": self = .summary
        case "decision": self = .decision
        case "task", "action", "follow_up", "follow-up": self = .followUp
        case "blocker", "blocked": self = .blocker
        case "question": self = .question
        case "media", "file": self = .media
        default: self = .thread
        }
    }
}

// MARK: - View

struct UniversalCommandPalette: View {
    let threadId: String
    var onSelectResult: (CommandPaletteResult) -> Void
    var onDismiss: () -> Void

    @StateObject private var viewModel = CommandPaletteViewModel()
    @FocusState  private var isInputFocused: Bool

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion)       private var reduceMotion

    private let flags = AMENFeatureFlags.shared

    var body: some View {
        if flags.commsCommandPaletteEnabled {
            VStack(spacing: 0) {
                searchBar
                Divider().opacity(0.5)
                contentArea
            }
            .commsGlass(signal: .neutral, cornerRadius: 20)
            .onAppear { isInputFocused = true }
            .onDisappear { viewModel.clear() }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Command palette")
        }
    }

    // MARK: Search Bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.body.weight(.medium))

            TextField("Ask anything: blockers, decisions, what changed…", text: $viewModel.query)
                .textFieldStyle(.plain)
                .focused($isInputFocused)
                .submitLabel(.search)
                .onSubmit { viewModel.search(threadId: threadId) }
                .onChange(of: viewModel.query) { _, q in
                    if q.isEmpty { viewModel.results = []; viewModel.clarificationPrompt = nil }
                }

            if viewModel.isLoading {
                ProgressView().scaleEffect(0.75)
            } else if !viewModel.query.isEmpty {
                Button(action: viewModel.clear) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(14)
    }

    // MARK: Content Area

    @ViewBuilder
    private var contentArea: some View {
        if let clarification = viewModel.clarificationPrompt {
            clarificationView(clarification)
        } else if !viewModel.results.isEmpty {
            resultsList
        } else if let error = viewModel.errorMessage {
            errorView(error)
        } else if viewModel.query.isEmpty && !viewModel.recentQueries.isEmpty {
            recentView
        } else {
            suggestionsView
        }
    }

    private func clarificationView(_ text: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "questionmark.circle").font(.title2).foregroundStyle(.orange)
            Text(text).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(24)
    }

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.results) { result in
                    resultRow(result)
                    if result.id != viewModel.results.last?.id {
                        Divider().padding(.leading, 44)
                    }
                }
            }
        }
        .frame(maxHeight: 320)
    }

    private func resultRow(_ result: CommandPaletteResult) -> some View {
        Button {
            AmenMessagingAnalytics.track(.commandPaletteResultSelected, parameters: ["type": result.type.rawValue])
            onSelectResult(result)
            onDismiss()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: result.type.icon)
                    .font(.body)
                    .foregroundStyle(result.type.tintColor)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(result.title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        Spacer()
                        typeBadge(result.type)
                        if result.confidence < 0.75 {
                            Text("Possible")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                    Text(result.snippet)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(result.type.rawValue): \(result.title)\(result.confidence < 0.75 ? ", possible match" : "")")
    }

    private func typeBadge(_ type: CommandResultType) -> some View {
        Text(type.rawValue)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(type.tintColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(type.tintColor.opacity(0.12), in: Capsule())
    }

    private func errorView(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
            Text(message).font(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
    }

    private var recentView: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Recent")
            ForEach(viewModel.recentQueries, id: \.self) { q in
                queryRow(q, icon: "clock") {
                    viewModel.query = q
                    viewModel.search(threadId: threadId)
                }
            }
        }
    }

    private var suggestionsView: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Try asking…")
            ForEach(suggestedQueries, id: \.self) { prompt in
                queryRow(prompt, icon: "sparkle") {
                    viewModel.query = prompt
                    viewModel.search(threadId: threadId)
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 6)
    }

    private func queryRow(_ text: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .frame(width: 20)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(text)
    }

    private let suggestedQueries = [
        "What changed since yesterday?",
        "Show open blockers",
        "Who owns the pending decisions?",
        "What's unresolved in this group?",
        "Summarize this conversation"
    ]
}
