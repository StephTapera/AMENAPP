//
//  BereanSpiritualViewModel.swift
//  AMENAPP
//
//  ViewModel for the Berean Spiritual Intelligence chat surface.
//  Manages conversation state, structured response handling, and
//  spiritual state display. All AI calls go through BereanAPIClient.
//

import Foundation
import Combine

@MainActor
final class BereanSpiritualViewModel: ObservableObject {

    // MARK: - Published State

    @Published var messages: [BereanSpiritualMessage] = []
    @Published var currentInput: String = ""
    @Published var isLoading = false
    @Published var errorMessage: String? = nil
    @Published var currentState: SpiritualPrimaryState? = nil
    @Published var showLeadershipPrompt = false
    @Published var leadershipPromptMessage: String? = nil
    @Published var activePassageContext: String? = nil

    // MARK: - Private

    private let conversationId: String
    private let apiClient = BereanAPIClient.shared

    init(conversationId: String = UUID().uuidString) {
        self.conversationId = conversationId
    }

    // MARK: - Send Message

    func sendMessage() async {
        let text = currentInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isLoading else { return }

        currentInput = ""
        errorMessage = nil

        // Append user message immediately
        let userMessage = BereanSpiritualMessage(
            id: UUID().uuidString,
            conversationId: conversationId,
            role: .user,
            content: text,
            structuredResponse: nil,
            responseMode: nil,
            leadershipPromptShown: false,
            createdAt: Date(),
            feedbackGiven: false
        )
        messages.append(userMessage)
        isLoading = true

        defer { isLoading = false }

        do {
            let history = messages
                .filter { $0.role != BereanSpiritualMessage.MessageRole.system }
                .dropLast()  // Exclude the message we just appended
                .suffix(10)   // Keep context window manageable
                .map { (role: $0.role.rawValue, content: $0.content) }

            let response = try await apiClient.generateStructuredResponse(
                conversationId: conversationId,
                userMessage: text,
                passageContext: activePassageContext,
                previousMessages: Array(history)
            )

            // Update spiritual state display
            currentState = response.spiritualState?.primaryState

            // Leadership prompt
            if response.leadershipPromptShown {
                showLeadershipPrompt = true
                leadershipPromptMessage = buildLeadershipPromptText(flags: response.sensitivityFlags)
            }

            let assistantMessage = BereanSpiritualMessage(
                id: UUID().uuidString,
                conversationId: conversationId,
                role: .assistant,
                content: response.answer,
                structuredResponse: response,
                responseMode: response.responseMode,
                leadershipPromptShown: response.leadershipPromptShown,
                createdAt: Date(),
                feedbackGiven: false
            )
            messages.append(assistantMessage)

        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Passage Study

    func studyPassage(reference: String) async {
        guard AMENFeatureFlags.shared.livingScriptureGraphEnabled else { return }
        activePassageContext = reference
        currentInput = "Let's study \(reference)"
        await sendMessage()
    }

    // MARK: - Dismiss Leadership Prompt

    func dismissLeadershipPrompt() {
        showLeadershipPrompt = false
        leadershipPromptMessage = nil
    }

    // MARK: - Private Helpers

    private func buildLeadershipPromptText(flags: [SensitivityFlag]) -> String {
        if flags.contains(.crisisEscalation) {
            return "You are not alone. If you are in crisis, please reach out to a trusted person, your pastor, or a crisis line (988 in the US)."
        }
        if flags.contains(.pastoralEscalation) || flags.contains(.controversialDoctrine) {
            return "This is a great question to bring to your pastor or a trusted spiritual mentor. Berean can help you explore Scripture, but your leaders know you and your situation in ways I don't."
        }
        if flags.contains(.scrupulosityRisk) {
            return "I want to encourage you — God's grace is greater than our anxiety about getting it right. Your pastor or a Christian counselor can be a wonderful resource here."
        }
        return "Consider connecting with your pastor or a mentor about this. Their wisdom and your relationship with them goes far beyond what I can offer."
    }
}
