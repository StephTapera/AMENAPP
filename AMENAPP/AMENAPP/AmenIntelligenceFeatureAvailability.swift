// AmenIntelligenceFeatureAvailability.swift
// AMENAPP
//
// Single-source availability checks for all System 29 Liquid Glass Intelligence features.
// Every call site reads from here — never query AMENFeatureFlags directly for these flags.
// @MainActor ensures AMENFeatureFlags.shared is always accessed on the main thread.

import Foundation

@MainActor
struct AmenIntelligenceFeatureAvailability {

    // Master kill-switch. When false, ALL sub-features are unavailable.
    var system: Bool {
        AMENFeatureFlags.shared.liquidGlassSystemEnabled
    }

    var presencePills: Bool {
        system && AMENFeatureFlags.shared.liquidGlassPresencePillsEnabled
    }

    var semanticUnderline: Bool {
        system && AMENFeatureFlags.shared.semanticUnderlineEnabled
    }

    var inlineDefinitionPopover: Bool {
        system && AMENFeatureFlags.shared.inlineDefinitionPopoverEnabled
    }

    var smartActionDetection: Bool {
        system && AMENFeatureFlags.shared.smartActionDetectionEnabled
    }

    var pulseAwareness: Bool {
        system && AMENFeatureFlags.shared.pulseAwarenessEnabled
    }

    var knowledgeThreads: Bool {
        system && AMENFeatureFlags.shared.knowledgeThreadsEnabled
    }

    var selahSemanticSave: Bool {
        system && AMENFeatureFlags.shared.selahSemanticSaveEnabled
    }

    var churchNotesSemanticActions: Bool {
        system && AMENFeatureFlags.shared.churchNotesSemanticActionsEnabled
    }

    var mediaChromeLiquidGlass: Bool {
        system && AMENFeatureFlags.shared.mediaChromeLiquidGlassEnabled
    }

    var composerPresenceActions: Bool {
        system && AMENFeatureFlags.shared.composerPresenceActionsEnabled
    }

    var bottomBarLiquidGlass: Bool {
        system && AMENFeatureFlags.shared.bottomBarLiquidGlassEnabled
    }
}
