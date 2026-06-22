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

    // MARK: — Crisis Resources

    /// Set to true when offerCrisisResources is returned from the safe messaging gateway
    /// or when on-device self-harm signals are detected in the sender's own message.
    /// The hosting view observes this and presents WellnessCrisisSheet.
    @Published var showCrisisSheet: Bool = false

    // MARK: — Availability

    private var availability: AmenMessagingFeatureAvailability

    init() {
        self.availability = AmenMessagingFeatureAvailability()
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
        // H-16: Skip AI safety scanning if the user has explicitly declined consent.
        // consentDMProcessing is persisted by BereanDMConsentSheet.saveConsent(_:).
        // Default (no key present) is treated as false — consent must be affirmative.
        guard UserDefaults.standard.bool(forKey: "consentDMProcessing") else { return .allow }
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

    // Routes decision/question/task extraction chips to the catch-up surface
    // until a dedicated extraction service exists.
    func extractSmartContext(conversationId: String, messages: [AppMessage]) {
        requestCatchUp(conversationId: conversationId, messages: messages)
    }

    // MARK: — Crisis Resource Surfacing

    /// Call this after receiving a result from SafeMessagingService.sendMessage().
    /// When the gateway returns .deliverWithResources (offerCrisisResources == true),
    /// this sets showCrisisSheet so the hosting view can present WellnessCrisisSheet.
    func handleSafetyGatewayResult(_ result: SafeMessagingService.SendResult) {
        if case .deliverWithResources = result {
            showCrisisSheet = true
        }
    }

    /// Call this after receiving a raw gateway response dictionary directly.
    /// Checks the offerCrisisResources field and surfaces crisis resources to the sender.
    func checkGatewayResponseForCrisis(_ response: [String: Any]) {
        if let offerCrisis = response["offerCrisisResources"] as? Bool, offerCrisis {
            showCrisisSheet = true
        }
    }

    func dismissCrisisSheet() {
        showCrisisSheet = false
    }
}
