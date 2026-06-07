// SabbathBereanGuideView.swift
// AMENAPP — SabbathMode
//
// SwiftUI guide view for Sabbath AI tasks.
// Routes through ClaudeAPIService → bereanChatProxy (Cloud Function).
// Claude-only, fail closed. No retry button (user re-submits). No fabrication.
// Footer: "Berean leads, it does not answer for you."
// Family questions: shows dinner-table note before response.
//
// BANNED tokens: gold, purple, dark gradients, serif fonts, streaks, counts.

import SwiftUI
import FirebaseFunctions

struct SabbathBereanGuideView: View {
    let task: SabbathAITask
    var sermonText: String? = nil
    var onClose: () -> Void

    @State private var userInput = ""
    @State private var isLoading = false
    @State private var responseText: String?
    @State private var errorText: String?

    // MARK: - Derived

    private var title: String {
        switch task {
        case .sabbathGuide:     return "Prayer Guide"
        case .familyQuestions:  return "Family Questions"
        case .sermonPrep:       return "Reflect on the Message"
        case .devotional:       return "Family Devotional"
        case .reflectionPrompt: return "Reflection"
        }
    }

    private var placeholder: String {
        switch task {
        case .sabbathGuide:     return "What are you bringing to prayer today?"
        case .familyQuestions:  return "Any themes from this week your family might explore?"
        case .sermonPrep:       return "Share a phrase or passage from the message you heard today."
        case .devotional:       return "Anything your family is sitting with this Sabbath?"
        case .reflectionPrompt: return "Anything on your heart before you write?"
        }
    }

    private var isFamilyQuestions: Bool { task == .familyQuestions }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer().frame(height: 24)
                    cardView
                    Spacer().frame(height: 40)
                }
            }
        }
    }

    // MARK: - Card (extracted for type-checker)

    private var cardView: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection
            Divider().padding(.bottom, 20)
            inputSection
            beginButton.padding(.bottom, 8)
            loadingSection
            familyNoteSection
            responseSection
            errorSection
            footerSection
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
        )
        .padding(.horizontal, 20)
    }

    // MARK: - Sub-sections

    private var headerSection: some View {
        HStack {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer()
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .background(Color(.systemFill), in: Circle())
            }
            .accessibilityLabel("Close Berean Guide")
        }
        .padding(.bottom, 20)
    }

    private var inputSection: some View {
        ZStack(alignment: .topLeading) {
            if userInput.isEmpty {
                Text(placeholder)
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 14)
                    .padding(.horizontal, 16)
            }
            TextEditor(text: $userInput)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .frame(minHeight: 96)
                .padding(8)
                .scrollContentBackground(.hidden)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color(.separator), lineWidth: 1)
                )
                .disabled(isLoading)
        }
        .accessibilityLabel("Share your context with Berean")
        .padding(.bottom, 16)
    }

    private var beginButton: some View {
        Button {
            Task { await handleBegin() }
        } label: {
            ZStack {
                Capsule()
                    .fill(Color.primary.opacity(isLoading ? 0.4 : 1.0))
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                if isLoading {
                    HStack(spacing: 8) {
                        ProgressView().tint(Color(uiColor: .systemBackground))
                        Text("Preparing...")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color(uiColor: .systemBackground))
                    }
                } else {
                    Text("Begin")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(uiColor: .systemBackground))
                }
            }
        }
        .disabled(isLoading)
        .accessibilityLabel("Begin")
    }

    @ViewBuilder
    private var loadingSection: some View {
        if isLoading {
            Text("Berean is preparing...")
                .font(.subheadline)
                .italic()
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 20)
                .accessibilityLabel("Berean is preparing your response")
        }
    }

    @ViewBuilder
    private var familyNoteSection: some View {
        if isFamilyQuestions, responseText != nil, errorText == nil {
            Text("These questions are for your dinner table. Use them as conversation starters.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(12)
                .background(Color(.systemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.top, 20)
                .accessibilityLabel("Dinner table note")
        }
    }

    @ViewBuilder
    private var responseSection: some View {
        if let responseText {
            VStack(alignment: .leading, spacing: 0) {
                Divider().padding(.vertical, 20)
                Text(responseText)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
                    .accessibilityLabel(responseText)
            }
        }
    }

    @ViewBuilder
    private var errorSection: some View {
        if let errorText {
            VStack(alignment: .leading, spacing: 0) {
                Divider().padding(.vertical, 16)
                Text(errorText)
                    .font(.subheadline)
                    .foregroundStyle(Color(.systemRed))
                    .lineSpacing(3)
                    .accessibilityLabel(errorText)
            }
        }
    }

    private var footerSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider().padding(.vertical, 20)
            Text("Berean leads, it does not answer for you.")
                .font(.caption2)
                .italic()
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    // MARK: - API call

    private func handleBegin() async {
        guard !isLoading else { return }

        responseText = nil
        errorText = nil
        isLoading = true
        defer { isLoading = false }

        let liturgical = getSabbathLiturgicalContext(for: Date())
        let userMsg = buildUserMessage(liturgical: liturgical)

        do {
            // Route through ClaudeAPIService → bereanChatProxy (never direct Claude)
            let result = try await ClaudeAPIService.shared.complete(
                system: "",  // System prompt constructed server-side by bereanChatProxy
                userMessage: userMsg,
                maxTokens: 1024,
                bereanMode: "sabbath_\(task.rawValue)"
            )
            guard !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                errorText = "Berean Guide is not available right now. Please try again in a moment."
                return
            }
            responseText = result
        } catch {
            // Fail closed — no fabrication, no fallback provider
            errorText = "Berean Guide is not available right now. Please try again in a moment."
        }
    }

    private func buildUserMessage(liturgical: SabbathLiturgicalContext) -> String {
        var parts: [String] = []
        parts.append("Sabbath Task: \(task.rawValue)")
        parts.append("Liturgical Season: \(liturgical.season.rawValue)")
        parts.append("Dominant Theme: \(liturgical.dominantTheme)")
        parts.append("Suggested Scriptures: \(liturgical.suggestedScriptures.joined(separator: ", "))")
        if !userInput.isEmpty {
            parts.append("User context: \(userInput.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        if isFamilyQuestions {
            parts.append("Generate dinner-table discussion questions for a family observing Sabbath. Keep questions open and inviting.")
        }
        if let sermon = sermonText, !sermon.isEmpty {
            parts.append("Sermon text excerpt: \(sermon)")
        }
        return parts.joined(separator: "\n")
    }
}

#Preview {
    SabbathBereanGuideView(task: .sabbathGuide, onClose: {})
}
