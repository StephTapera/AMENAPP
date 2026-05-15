// AmenMessagingFeatureAvailability.swift
// AMENAPP
//
// Single-source availability checks for all messaging intelligence features.
// @MainActor to ensure AMENFeatureFlags.shared is always accessed on the main thread.

import Foundation

@MainActor
struct AmenMessagingFeatureAvailability {

    var smartPills: Bool        { AMENFeatureFlags.shared.messagingSmartPillsEnabled }
    var translation: Bool       { AMENFeatureFlags.shared.messagingTranslationEnabled }
    var summarization: Bool     { false }   // No DM summarizer exists — honest unavailable
    var selah: Bool             { AMENFeatureFlags.shared.messagingCrossSurfaceActionsEnabled
                                  && AMENFeatureFlags.shared.selahMediaOSEnabled }
    var churchNotes: Bool       { AMENFeatureFlags.shared.messagingCrossSurfaceActionsEnabled }
    var reminders: Bool         { AMENFeatureFlags.shared.messagingCrossSurfaceActionsEnabled }
    var voiceTranscript: Bool   { false }   // STT for received voice messages not yet wired — TODO
    var mediaIntelligence: Bool { AMENFeatureFlags.shared.messagingMediaIntelligenceEnabled }
    var safetyReview: Bool      { AMENFeatureFlags.shared.messagingSafetyNudgesEnabled }
    var approvalCards: Bool     { AMENFeatureFlags.shared.messagingApprovalCardsEnabled }
    var catchUp: Bool           { AMENFeatureFlags.shared.messagingCatchUpEnabled }
    var presencePolish: Bool    { AMENFeatureFlags.shared.messagingPresencePolishEnabled }
}
