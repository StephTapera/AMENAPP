// CreatorBereanAssistView.swift
// AMENAPP — Creator Studio / Wave 5
//
// Berean-assist tools for creators.
// Berean proposes; creator decides — no output is applied without explicit approval.
// All suggestions labeled "Suggested by Berean"; no fabricated titles, credentials, or quotes.
// Fail-closed: renders EmptyView when creatorBereanAssistEnabled is off.

import SwiftUI

struct CreatorBereanAssistView: View {

    // MARK: - Action

    enum AssistAction: String, CaseIterable, Identifiable {
        case draftDiscussionQuestions = "Draft discussion questions"
        case summarizeQuestions       = "Summarize what people are asking"
        case studyGuideOutline        = "Suggest a study-guide outline"
        case flagUnclearSections      = "Flag unclear sections"
        case liveSessionBrief         = "Prep a live session brief"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .draftDiscussionQuestions: return "bubble.left.and.bubble.right.fill"
            case .summarizeQuestions:       return "text.magnifyingglass"
            case .studyGuideOutline:        return "list.bullet.rectangle.portrait.fill"
            case .flagUnclearSections:      return "flag.fill"
            case .liveSessionBrief:         return "video.badge.checkmark.fill"
            }
        }
    }

    // MARK: - Result State per Action

    enum ResultState {
        case idle
        case loading
        case ready(String)
        case approved
    }

    // MARK: - State

    @State private var activeAction: AssistAction? = nil
    @State private var resultStates: [AssistAction: ResultState] = [:]
    @State private var editingAction: AssistAction? = nil
    @State private var editText: String = ""

    // MARK: - Body

    var body: some View {
        guard AMENFeatureFlags.shared.creatorBereanAssistEnabled else {
            return AnyView(EmptyView())
        }
        return AnyView(content)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Attribution header
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.caption)
                Text("Berean proposes; you decide.")
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)

            // Action chips
            actionChips

            // Result panel for active action
            if let action = activeAction {
                resultPanel(for: action)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3), value: activeAction)
    }

    // MARK: - Action Chips

    private var actionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AssistAction.allCases) { action in
                    assistChip(action)
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func assistChip(_ action: AssistAction) -> some View {
        let isActive = activeAction == action
        Button {
            withAnimation(.spring(response: 0.25)) {
                if activeAction == action {
                    // Toggle off
                    activeAction = nil
                } else {
                    activeAction = action
                    if resultStates[action] == nil {
                        Task { await requestResult(for: action) }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: action.icon)
                    .font(.system(size: 12, weight: .medium))
                Text(action.rawValue)
                    .font(.system(size: 13, weight: .medium))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(
                        isActive ? Color.accentColor.opacity(0.6) : Color.clear,
                        lineWidth: 1
                    )
            )
            .foregroundStyle(isActive ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Result Panel

    @ViewBuilder
    private func resultPanel(for action: AssistAction) -> some View {
        let state = resultStates[action] ?? .idle

        Group {
            switch state {
            case .idle:
                EmptyView()

            case .loading:
                loadingCard

            case .ready(let suggestion):
                if editingAction == action {
                    editCard(action: action, text: editText)
                } else {
                    suggestionCard(action: action, suggestion: suggestion)
                }

            case .approved:
                approvedBanner(action: action)
            }
        }
    }

    // MARK: - Loading Card (skeleton)

    private var loadingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                Text("Suggested by Berean")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                Spacer()
                ProgressView()
                    .scaleEffect(0.7)
            }

            // Skeleton lines
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemFill))
                    .frame(maxWidth: index == 2 ? 180 : .infinity)
                    .frame(height: 13)
                    .shimmer()
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.07), radius: 6, x: 0, y: 2)
        )
    }

    // MARK: - Suggestion Card

    private func suggestionCard(action: AssistAction, suggestion: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                Text("Suggested by Berean")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                Spacer()
            }

            Text(suggestion)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                // Approve & Use
                Button {
                    withAnimation(.spring(response: 0.25)) {
                        approve(action: action, suggestion: suggestion)
                    }
                } label: {
                    Text("Approve & Use")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.accentColor))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                // Edit
                Button {
                    editText = suggestion
                    withAnimation(.spring(response: 0.25)) {
                        editingAction = action
                    }
                } label: {
                    Text("Edit")
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color(.secondarySystemBackground)))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)

                // Dismiss
                Button {
                    withAnimation(.spring(response: 0.25)) {
                        activeAction = nil
                        resultStates.removeValue(forKey: action)
                    }
                } label: {
                    Text("Dismiss")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.07), radius: 6, x: 0, y: 2)
        )
    }

    // MARK: - Edit Card

    private func editCard(action: AssistAction, text: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Edit suggestion")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    withAnimation { editingAction = nil }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            TextEditor(text: $editText)
                .font(.subheadline)
                .frame(minHeight: 80)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color(.systemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack(spacing: 8) {
                Button {
                    withAnimation(.spring(response: 0.25)) {
                        approve(action: action, suggestion: editText)
                        editingAction = nil
                    }
                } label: {
                    Text("Approve & Use")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.green))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation { editingAction = nil }
                } label: {
                    Text("Cancel")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.07), radius: 6, x: 0, y: 2)
        )
    }

    // MARK: - Approved Banner

    private func approvedBanner(action: AssistAction) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.green)
            Text("Added to clipboard. Paste it where you need it.")
                .font(.subheadline)
                .foregroundStyle(.primary)
            Spacer()
            Button {
                withAnimation(.spring(response: 0.25)) {
                    activeAction = nil
                    resultStates.removeValue(forKey: action)
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.green.opacity(0.10))
        )
    }

    // MARK: - Request (stub)

    private func requestResult(for action: AssistAction) async {
        resultStates[action] = .loading

        // Simulated network delay — replace with real Berean callable
        try? await Task.sleep(nanoseconds: 1_200_000_000)

        // TODO: call Berean assist callable (e.g. bereanAssistCreatorAction)
        // The callable should accept { creatorId, actionKind, contentContext }
        // and return { suggestion: String, label: "Suggested by Berean" }
        let stub = stubSuggestion(for: action)
        resultStates[action] = .ready(stub)
    }

    private func stubSuggestion(for action: AssistAction) -> String {
        switch action {
        case .draftDiscussionQuestions:
            return "1. What does this passage reveal about God's character?\n2. How does this theme connect to your current spiritual season?\n3. What is one step you feel called to take this week?"
        case .summarizeQuestions:
            return "People are asking about applying the teachings to daily work life and relationships. Several questions touch on the meaning of grace in hard circumstances."
        case .studyGuideOutline:
            return "Session 1: Context & Background\nSession 2: Key Themes\nSession 3: Application\nSession 4: Group Reflection & Prayer"
        case .flagUnclearSections:
            return "The transition between the historical context and the modern application in the second section may benefit from a clearer bridge sentence."
        case .liveSessionBrief:
            return "Opening prayer (5 min) → Welcome & framing (3 min) → Main teaching (20 min) → Q&A (15 min) → Closing prayer (5 min). Suggested scripture: Romans 8:28."
        }
    }

    // MARK: - Approve

    private func approve(action: AssistAction, suggestion: String) {
        // TODO: wire to real integration (e.g. paste into composer, save to Church Notes)
        // For now, copy to clipboard as a safe default.
        UIPasteboard.general.string = suggestion
        resultStates[action] = .approved
        editingAction = nil
    }
}

// MARK: - Shimmer modifier (lightweight skeleton animation)

private extension View {
    func shimmer() -> some View {
        self.opacity(0.6)
    }
}
