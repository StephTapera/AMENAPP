// AmenMessagingIntelligenceCoordinator.swift
// AMENAPP
//
// @MainActor coordinator that owns all messaging intelligence state:
// smart pills, translation, catch-up tray, and pre-send safety nudge.
// UnifiedChatView owns this as @StateObject.

import SwiftUI

@MainActor
final class AmenMessagingIntelligenceCoordinator: ObservableObject {

    // MARK: — Smart Pills

    @Published var activePills: [AmenSmartPillDescriptor] = []

    // MARK: — Translation

    /// messageId → TranslationUIState
    @Published var translationStates: [String: TranslationUIState] = [:]
    @Published private(set) var showingOriginalForMessage: Set<String> = []

    // MARK: — Catch Up

    @Published var catchUpState: AmenCatchUpState = .idle
    @Published var catchUpDismissed: Bool = false

    // MARK: — Pre-Send Safety Nudge

    @Published var pendingSafetyNudge: AmenSafetyNudgeContext? = nil

    // MARK: — Availability

    private var availability: AmenMessagingFeatureAvailability

    init(flags: AMENFeatureFlags = .shared) {
        self.availability = AmenMessagingFeatureAvailability(flags: flags)
    }

    // MARK: — Smart Pill Computation

    func update(context: AmenSmartPillEligibilityContext) {
        guard availability.smartPills else {
            if !activePills.isEmpty { activePills = [] }
            return
        }
        let pills = AmenSmartPillPriorityEngine.eligiblePills(
            for: context,
            flags: AMENFeatureFlags.shared
        )
        guard pills.map(\.type) != activePills.map(\.type) else { return }
        activePills = pills
        if !pills.isEmpty {
            AmenMessagingAnalytics.track(.smartPillRowShown, parameters: ["count": pills.count])
        }
    }

    // MARK: — Translation

    func requestTranslation(for message: AppMessage) {
        guard availability.translation else {
            translationStates[message.id] = .disabled
            return
        }
        translationStates[message.id] = .loading
        AmenMessagingAnalytics.track(.translationRequested)

        Task {
            let result = await TranslationService.shared.translate(
                text: message.text,
                contentType: .message,
                contentId: message.id,
                surface: .messages,
                isPublicContent: false   // DMs are never public — belt-and-suspenders guard
            )
            translationStates[message.id] = result
            let isSuccess: Bool
            if case .translated = result { isSuccess = true } else { isSuccess = false }
            AmenMessagingAnalytics.track(
                isSuccess ? .translationSucceeded : .translationFailed
            )
        }
    }

    func toggleOriginal(for messageId: String) {
        if showingOriginalForMessage.contains(messageId) {
            showingOriginalForMessage.remove(messageId)
        } else {
            showingOriginalForMessage.insert(messageId)
            AmenMessagingAnalytics.track(.translationOriginalToggled)
        }
    }

    func isShowingOriginal(for messageId: String) -> Bool {
        showingOriginalForMessage.contains(messageId)
    }

    func translationState(for messageId: String) -> TranslationUIState {
        translationStates[messageId] ?? .notNeeded
    }

    // MARK: — Catch Up

    func requestCatchUp(conversationId: String, messages: [AppMessage]) {
        guard availability.catchUp else {
            catchUpState = .unavailable
            AmenMessagingAnalytics.track(.catchUpUnavailable)
            return
        }
        catchUpState = .loading
        AmenMessagingAnalytics.track(.catchUpRequested)

        // No DM summarizer backend exists — honest unavailable state
        Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            catchUpState = .unavailable
            AmenMessagingAnalytics.track(.catchUpUnavailable)
        }
    }

    func dismissCatchUp() {
        catchUpDismissed = true
        catchUpState = .idle
        AmenMessagingAnalytics.track(.catchUpDismissed)
    }

    // MARK: — Pre-Send Safety

    func evaluatePreSend(
        text: String,
        senderUID: String,
        recipientUID: String,
        conversationId: String
    ) async -> MessageSafetyDecision {
        guard availability.safetyReview else { return .allow }
        return await AMENMessageSafetyEngine.shared.evaluate(
            text: text,
            senderUID: senderUID,
            recipientUID: recipientUID,
            conversationId: conversationId
        )
    }

    func presentSafetyNudge(decision: MessageSafetyDecision, messageText: String) {
        switch decision {
        case .softWarn(let message):
            pendingSafetyNudge = AmenSafetyNudgeContext(
                warningMessage: message,
                messageText: messageText,
                canSendAnyway: true
            )
            AmenMessagingAnalytics.track(.safetyNudgeShown)
        case .requireEdit(let message):
            pendingSafetyNudge = AmenSafetyNudgeContext(
                warningMessage: message,
                messageText: messageText,
                canSendAnyway: false
            )
            AmenMessagingAnalytics.track(.safetyNudgeShown)
        default:
            break
        }
    }

    func dismissSafetyNudge() {
        pendingSafetyNudge = nil
    }
}
