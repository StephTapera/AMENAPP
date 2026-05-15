// AmenSmartPillPriorityEngine.swift
// AMENAPP
//
// Ranks eligible smart pills by contextual weight and returns at most 3 (Phase 4B).

import Foundation

struct AmenSmartPillPriorityEngine {

    static let catchUpUnreadThreshold = 15
    static let longThreadThreshold = 50
    static let longMessageCharThreshold = 200

    static func eligiblePills(
        for context: AmenSmartPillEligibilityContext,
        flags: AMENFeatureFlags
    ) -> [AmenSmartPillDescriptor] {
        var weighted: [(AmenSmartPillDescriptor, Int)] = []

        // Translate — highest priority when language differs
        if flags.messagingTranslationEnabled,
           let detected = context.detectedLanguage,
           !detected.isEmpty,
           detected != context.userLanguageCode {
            weighted.append((.init(type: .translate), 100))
        }

        // Catch Me Up — large unread backlog
        if flags.messagingCatchUpEnabled,
           context.unreadCount >= catchUpUnreadThreshold {
            weighted.append((.init(type: .catchMeUp), 90))
        }

        // Voice transcript — voice message in focus
        if flags.messagingVoiceIntelligenceEnabled,
           context.hasVoiceMessage {
            weighted.append((.init(type: .voiceTranscript), 85))
        }

        // Media actions — media message in focus
        if flags.messagingMediaIntelligenceEnabled,
           context.hasMediaMessage {
            weighted.append((.init(type: .mediaActions), 80))
        }

        // Save to Selah — needs Selah OS enabled
        if flags.messagingCrossSurfaceActionsEnabled,
           flags.selahMediaOSEnabled,
           context.selectedMessage != nil {
            weighted.append((.init(type: .saveToSelah), 60))
        }

        // Add to Church Notes — always available if cross-surface enabled
        if flags.messagingCrossSurfaceActionsEnabled,
           context.selectedMessage != nil {
            weighted.append((.init(type: .addToChurchNotes), 55))
        }

        // Remind Me
        if flags.messagingCrossSurfaceActionsEnabled,
           context.selectedMessage != nil {
            weighted.append((.init(type: .remindMe), 40))
        }

        // Extract actions — long text message
        if flags.messagingCrossSurfaceActionsEnabled,
           context.hasLongText {
            weighted.append((.init(type: .extractActions), 35))
        }

        return weighted
            .sorted { $0.1 > $1.1 }
            .prefix(3)
            .map(\.0)
    }
}
