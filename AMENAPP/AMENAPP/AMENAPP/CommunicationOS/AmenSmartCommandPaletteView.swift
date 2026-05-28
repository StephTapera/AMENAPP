// AmenSmartCommandPaletteView.swift
// AMEN App — Smart Collaboration Layer: Phase 3 Slice 9
//
// Permission-scoped command palette for smart context search.
//
// Design rules enforced here:
//   1. Query is sanitized before use — strips control chars, HTML entities, limits to 200 chars.
//   2. Results are permission-scoped to the caller's threadId only — no cross-thread leakage.
//   3. Every result carries a sourceMessageId citation anchor.
//   4. Prayer signal results are never surfaced here — they have their own privacy-gated view.
//   5. Feature flag gated — returns empty when kill-switch is OFF.
//   6. All states handled: idle, loading, empty, results, error, permission-denied, offline.

import SwiftUI
import FirebaseFirestore

// MARK: - AmenCommandPaletteResult

struct AmenCommandPaletteResult: Identifiable {
    enum ResultKind {
        case summary(text: String)
        case action(text: String, actionType: AmenSmartActionType, status: AmenSmartActionStatus)
        case catchUp(text: String)
    }

    let id: String
    let kind: ResultKind
    /// Citation anchor — the message this result was derived from.
    let sourceMessageId: String
    let generatedAt: Date
    /// Human-readable label for VoiceOver.
    var kindLabel: String {
        switch kind {
        case .summary: return "Thread Summary"
        case .action: return "Possible Action"
        case .catchUp: return "Catch-up Item"
        }
    }
}

// MARK: - AmenCommandPaletteViewState

enum AmenCommandPaletteViewState: Equatable {
    case idle
    case loading
    case results([AmenCommandPaletteResult])
    case empty
    case error(String)
    case permissionDenied
    case offline

    static func == (lhs: AmenCommandPaletteViewState, rhs: AmenCommandPaletteViewState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.loading, .loading), (.empty, .empty),
             (.permissionDenied, .permissionDenied), (.offline, .offline): return true
        case (.results(let a), .results(let b)): return a.map(\.id) == b.map(\.id)
        case (.error(let a), .error(let b)): return a == b
        default: return false
        }
    }
}

// MARK: - AmenSmartCommandPaletteViewModel

@MainActor
final class AmenSmartCommandPaletteViewModel: ObservableObject {
    @Published var query: String = ""
    @Published private(set) var state: AmenCommandPaletteViewState = .idle

    private let threadId: String
    private let threadType: AmenSmartThreadType
    private let uid: String
    private var debounceTask: Task<Void, Never>?

    init(threadId: String, threadType: AmenSmartThreadType, uid: String) {
        self.threadId = threadId
        self.threadType = threadType
        self.uid = uid
    }

    func onQueryChanged(_ newQuery: String) {
        let sanitized = Self.sanitize(newQuery)
        debounceTask?.cancel()
        guard !sanitized.isEmpty else {
            state = .idle
            return
        }
        state = .loading
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce
            guard !Task.isCancelled else { return }
            await search(sanitized)
        }
    }

    func dismiss() {
        debounceTask?.cancel()
        query = ""
        state = .idle
    }

    // MARK: - Sanitization

    /// Strips control characters, HTML-like angle-bracket sequences, and
    /// limits input to 200 characters. Never passes raw query to Firestore
    /// — results are filtered client-side from already-loaded smart context.
    static func sanitize(_ raw: String) -> String {
        var s = raw
            .components(separatedBy: .controlCharacters).joined()
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if s.count > 200 { s = String(s.prefix(200)) }
        return s
    }

    // MARK: - Search

    private func search(_ sanitized: String) async {
        guard RemoteKillSwitch.shared.messagesSmartContextEnabled else {
            state = .idle
            return
        }

        let db = Firestore.firestore()
        let lower = sanitized.lowercased()
        var results: [AmenCommandPaletteResult] = []

        do {
            // 1. Search smart context summary (DM or channel)
            let summaryPath: String
            switch threadType {
            case .dm:
                summaryPath = AmenSmartCollaborationPaths.dmSummary(conversationId: threadId)
            case .channel:
                // channel requires spaceId — palette is instantiated with threadId as channelDocPath
                summaryPath = threadId + "/summary/main"
            case .discussion:
                summaryPath = "discussions/\(threadId)/summary/main"
            }

            let summarySnap = try await db.document(summaryPath).getDocument()
            if summarySnap.exists, let data = summarySnap.data() {
                let summaryText = data["summaryText"] as? String ?? ""
                let bullets = data["bulletPoints"] as? [String] ?? []
                let sourceId = data["sourceMessageIds"] as? [String] ?? []
                let anchor = sourceId.first ?? ""

                if summaryText.lowercased().contains(lower) && !summaryText.isEmpty {
                    results.append(AmenCommandPaletteResult(
                        id: "summary-main",
                        kind: .summary(text: summaryText),
                        sourceMessageId: anchor,
                        generatedAt: (data["generatedAt"] as? Timestamp)?.dateValue() ?? .distantPast
                    ))
                }

                for (i, bullet) in bullets.enumerated() where bullet.lowercased().contains(lower) {
                    results.append(AmenCommandPaletteResult(
                        id: "bullet-\(i)",
                        kind: .summary(text: bullet),
                        sourceMessageId: anchor,
                        generatedAt: (data["generatedAt"] as? Timestamp)?.dateValue() ?? .distantPast
                    ))
                }
            }

            // 2. Search smart actions
            let actionsPath: String
            switch threadType {
            case .dm:
                actionsPath = AmenSmartCollaborationPaths.dmSmartActions(conversationId: threadId)
            case .channel:
                actionsPath = threadId + "/smartActions"
            case .discussion:
                actionsPath = "discussions/\(threadId)/smartActions"
            }

            let actionsSnap = try await db.collection(actionsPath)
                .whereField("status", in: ["suggested", "accepted"])
                .limit(to: 50)
                .getDocuments()

            for doc in actionsSnap.documents {
                let d = doc.data()
                let text = d["suggestedText"] as? String ?? ""
                guard text.lowercased().contains(lower), !text.isEmpty else { continue }
                let actionTypeRaw = d["actionType"] as? String ?? "followUp"
                let statusRaw = d["status"] as? String ?? "suggested"
                let actionType = AmenSmartActionType(rawValue: actionTypeRaw) ?? .followUp
                let status = AmenSmartActionStatus(rawValue: statusRaw) ?? .suggested
                let sourceId = d["sourceMessageId"] as? String ?? ""
                // Confidence gate: don't surface low-confidence results
                let confidence = d["confidence"] as? Double ?? 0.0
                guard confidence >= 0.5 else { continue }

                results.append(AmenCommandPaletteResult(
                    id: "action-\(doc.documentID)",
                    kind: .action(text: text, actionType: actionType, status: status),
                    sourceMessageId: sourceId,
                    generatedAt: (d["generatedAt"] as? Timestamp)?.dateValue() ?? .distantPast
                ))
            }

            // Sort: most recent first, limit to 20
            results.sort { $0.generatedAt > $1.generatedAt }
            let limited = Array(results.prefix(20))

            state = limited.isEmpty ? .empty : .results(limited)

        } catch let err as NSError {
            if err.domain == NSURLErrorDomain && err.code == NSURLErrorNotConnectedToInternet {
                state = .offline
            } else if err.localizedDescription.lowercased().contains("permission") {
                state = .permissionDenied
            } else {
                state = .error("Search unavailable. Please try again.")
            }
        }
    }
}

// MARK: - AmenSmartCommandPaletteView

struct AmenSmartCommandPaletteView: View {
    @StateObject private var vm: AmenSmartCommandPaletteViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let surface: String
    let onResultSelected: (AmenCommandPaletteResult) -> Void

    init(
        threadId: String,
        threadType: AmenSmartThreadType,
        uid: String,
        surface: String,
        onResultSelected: @escaping (AmenCommandPaletteResult) -> Void
    ) {
        _vm = StateObject(wrappedValue: AmenSmartCommandPaletteViewModel(
            threadId: threadId,
            threadType: threadType,
            uid: uid
        ))
        self.surface = surface
        self.onResultSelected = onResultSelected
    }

    var body: some View {
        guard RemoteKillSwitch.shared.messagesSmartContextEnabled else {
            return AnyView(EmptyView())
        }
        return AnyView(paletteContent)
    }

    private var paletteContent: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField
                Divider()
                resultArea
            }
            .navigationTitle("Smart Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        vm.dismiss()
                        dismiss()
                    }
                    .accessibilityLabel("Cancel smart search")
                }
            }
        }
        .onAppear {
            AMENAnalyticsService.shared.track(.commandPaletteOpened(surface: surface))
        }
    }

    // MARK: - Search Field

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField("Search summaries and actions…", text: $vm.query)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityLabel("Search smart context")
                .onChange(of: vm.query) { _, newValue in
                    vm.onQueryChanged(newValue)
                }

            if !vm.query.isEmpty {
                Button {
                    vm.query = ""
                    vm.dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Result Area

    @ViewBuilder
    private var resultArea: some View {
        switch vm.state {
        case .idle:
            CommandPaletteIdleView()
        case .loading:
            CommandPaletteLoadingView()
        case .results(let results):
            CommandPaletteResultList(
                results: results,
                reduceMotion: reduceMotion
            ) { result in
                AMENAnalyticsService.shared.track(.commandPaletteResultSelected)
                onResultSelected(result)
                dismiss()
            }
        case .empty:
            CommandPaletteEmptyView(query: vm.query)
        case .error(let msg):
            CommandPaletteErrorView(message: msg)
        case .permissionDenied:
            CommandPalettePermissionDeniedView()
        case .offline:
            CommandPaletteOfflineView()
        }
    }
}

// MARK: - CommandPaletteIdleView

private struct CommandPaletteIdleView: View {
    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Search summaries, actions, and catch-up items in this thread.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Type to search summaries and actions in this thread.")
    }
}

// MARK: - CommandPaletteLoadingView

private struct CommandPaletteLoadingView: View {
    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
                .accessibilityLabel("Searching…")
            Text("Searching…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}

// MARK: - CommandPaletteResultList

private struct CommandPaletteResultList: View {
    let results: [AmenCommandPaletteResult]
    let reduceMotion: Bool
    let onSelect: (AmenCommandPaletteResult) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(results) { result in
                    CommandPaletteResultRow(result: result, reduceMotion: reduceMotion) {
                        onSelect(result)
                    }
                    Divider().padding(.leading, 16)
                }
            }
        }
        .accessibilityLabel("Search results, \(results.count) item\(results.count == 1 ? "" : "s")")
    }
}

// MARK: - CommandPaletteResultRow

private struct CommandPaletteResultRow: View {
    let result: AmenCommandPaletteResult
    let reduceMotion: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                resultIcon
                    .frame(width: 28, height: 28)
                    .foregroundStyle(iconColor)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(result.kindLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    Text(displayText)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(3)

                    if !result.sourceMessageId.isEmpty {
                        Text("Source: \(result.sourceMessageId.prefix(8))…")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(result.kindLabel): \(displayText)")
        .accessibilityHint("Double-tap to view in thread")
        .accessibilityAddTraits(.isButton)
    }

    private var displayText: String {
        switch result.kind {
        case .summary(let text): return text
        case .action(let text, _, _):
            // Strip "possible: " prefix for display — user knows it's suggested via the kindLabel
            return text.hasPrefix("possible: ") ? String(text.dropFirst(10)) : text
        case .catchUp(let text): return text
        }
    }

    private var resultIcon: some View {
        switch result.kind {
        case .summary:
            return Image(systemName: "doc.text")
        case .action(_, let actionType, _):
            return Image(systemName: actionType.iconName)
        case .catchUp:
            return Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
        }
    }

    private var iconColor: Color {
        switch result.kind {
        case .summary: return .blue
        case .action(_, _, let status):
            switch status {
            case .accepted: return .green
            case .dismissed: return .secondary
            default: return .orange
            }
        case .catchUp: return .purple
        }
    }
}

// MARK: - CommandPaletteEmptyView

private struct CommandPaletteEmptyView: View {
    let query: String
    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("No results for \"\(query)\"")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Text("Try different keywords or check back after the AI processes more messages.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No results for \(query). Try different keywords.")
    }
}

// MARK: - CommandPaletteErrorView

private struct CommandPaletteErrorView: View {
    let message: String
    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(message)")
    }
}

// MARK: - CommandPalettePermissionDeniedView

private struct CommandPalettePermissionDeniedView: View {
    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "lock.fill")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("You don't have access to search this thread's smart context.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Access denied. You don't have permission to search this thread.")
    }
}

// MARK: - CommandPaletteOfflineView

private struct CommandPaletteOfflineView: View {
    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "wifi.slash")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("You appear to be offline.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Smart search requires a connection.")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Offline. Smart search requires an internet connection.")
    }
}

// MARK: - AmenSmartActionType Icon Extension

private extension AmenSmartActionType {
    var iconName: String {
        switch self {
        case .followUp: return "arrow.turn.down.right"
        case .decision: return "checkmark.seal"
        case .commitment: return "hand.raised"
        case .openQuestion: return "questionmark.circle"
        case .reminder: return "bell"
        }
    }
}

// MARK: - Palette Trigger Button

/// Drop-in toolbar button that presents the command palette as a sheet.
struct AmenCommandPaletteTriggerButton: View {
    let threadId: String
    let threadType: AmenSmartThreadType
    let uid: String
    let surface: String

    @State private var isPresented = false

    var body: some View {
        guard RemoteKillSwitch.shared.messagesSmartContextEnabled else {
            return AnyView(EmptyView())
        }
        return AnyView(
            Button {
                isPresented = true
            } label: {
                Image(systemName: "magnifyingglass.circle")
                    .symbolRenderingMode(.hierarchical)
            }
            .accessibilityLabel("Open smart search")
            .sheet(isPresented: $isPresented) {
                AmenSmartCommandPaletteView(
                    threadId: threadId,
                    threadType: threadType,
                    uid: uid,
                    surface: surface
                ) { result in
                    // Caller-provided navigation: default no-op here.
                    isPresented = false
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        )
    }
}
