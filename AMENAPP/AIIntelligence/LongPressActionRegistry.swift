// LongPressActionRegistry.swift
// AMENAPP — Long-Press Intelligence Layer (Wave 1)
//
// Single source of truth for per-object-type IntelligenceActions.
// Adding a new object type = add a case here; no bespoke menus elsewhere.

import Foundation

@MainActor
final class LongPressActionRegistry {

    static let shared = LongPressActionRegistry()

    private init() {}

    func actions(for objectType: LongPressObjectType) -> [IntelligenceAction] {
        switch objectType {
        case .verse:
            return verseActions
        case .comment:
            return commentActions
        default:
            return []
        }
    }

    // MARK: - Verse Actions

    private let verseActions: [IntelligenceAction] = [
        IntelligenceAction(
            id: "verse_ask_why",
            label: "Ask Berean Why",
            accessibilityLabel: "Ask Berean why this passage was written and why it matters",
            category: .smart,
            bereanMode: .discern,
            usesDepthDial: true,
            requiresCitationIntegrity: true,
            requiresGuardianModeration: false,
            privacyZone: .functional,
            applicableObjectTypes: [.verse]
        ),
        IntelligenceAction(
            id: "verse_explain_simply",
            label: "Explain Simply",
            accessibilityLabel: "Explain Simply",
            category: .smart,
            bereanMode: .ask,
            usesDepthDial: true,
            requiresCitationIntegrity: true,
            requiresGuardianModeration: false,
            privacyZone: .functional,
            applicableObjectTypes: [.verse]
        ),
        IntelligenceAction(
            id: "verse_original_language",
            label: "Original Language",
            accessibilityLabel: "Original Language",
            category: .smart,
            bereanMode: .ask,
            usesDepthDial: true,
            requiresCitationIntegrity: true,
            requiresGuardianModeration: false,
            privacyZone: .functional,
            applicableObjectTypes: [.verse]
        ),
        IntelligenceAction(
            id: "verse_cross_references",
            label: "Cross References",
            accessibilityLabel: "Cross References",
            category: .smart,
            bereanMode: .ask,
            usesDepthDial: true,
            requiresCitationIntegrity: true,
            requiresGuardianModeration: false,
            privacyZone: .functional,
            applicableObjectTypes: [.verse]
        ),
        IntelligenceAction(
            id: "verse_apply",
            label: "Apply to My Situation",
            accessibilityLabel: "Apply to My Situation",
            category: .smart,
            bereanMode: .reflect,
            usesDepthDial: true,
            requiresCitationIntegrity: false,
            requiresGuardianModeration: false,
            privacyZone: .sensitive,
            applicableObjectTypes: [.verse]
        ),
        IntelligenceAction(
            id: "verse_save",
            label: "Save",
            accessibilityLabel: "Save",
            category: .quick,
            bereanMode: nil,
            usesDepthDial: false,
            requiresCitationIntegrity: false,
            requiresGuardianModeration: false,
            privacyZone: .preference,
            applicableObjectTypes: [.verse]
        ),
        IntelligenceAction(
            id: "verse_highlight",
            label: "Highlight",
            accessibilityLabel: "Highlight",
            category: .quick,
            bereanMode: nil,
            usesDepthDial: false,
            requiresCitationIntegrity: false,
            requiresGuardianModeration: false,
            privacyZone: .preference,
            applicableObjectTypes: [.verse]
        ),
    ]

    // MARK: - Comment Actions

    private let commentActions: [IntelligenceAction] = [
        IntelligenceAction(
            id: "comment_ask_berean",
            label: "Ask Berean",
            accessibilityLabel: "Ask Berean",
            category: .smart,
            bereanMode: .ask,
            usesDepthDial: true,
            requiresCitationIntegrity: false,
            requiresGuardianModeration: false,
            privacyZone: .functional,
            applicableObjectTypes: [.comment]
        ),
        IntelligenceAction(
            id: "comment_find_verses",
            label: "Find Supporting Verses",
            accessibilityLabel: "Find Supporting Verses",
            category: .smart,
            bereanMode: .ask,
            usesDepthDial: true,
            requiresCitationIntegrity: true,
            requiresGuardianModeration: false,
            privacyZone: .functional,
            applicableObjectTypes: [.comment]
        ),
        IntelligenceAction(
            id: "comment_find_opposing",
            label: "Find Opposing Views",
            accessibilityLabel: "Find Opposing Views",
            category: .smart,
            bereanMode: .discern,
            usesDepthDial: true,
            requiresCitationIntegrity: false,
            requiresGuardianModeration: false,
            privacyZone: .functional,
            applicableObjectTypes: [.comment]
        ),
        IntelligenceAction(
            id: "comment_reply",
            label: "Reply",
            accessibilityLabel: "Reply",
            category: .quick,
            bereanMode: nil,
            usesDepthDial: false,
            requiresCitationIntegrity: false,
            requiresGuardianModeration: false,
            privacyZone: .functional,
            applicableObjectTypes: [.comment]
        ),
        IntelligenceAction(
            id: "comment_save",
            label: "Save Insight",
            accessibilityLabel: "Save Insight",
            category: .quick,
            bereanMode: nil,
            usesDepthDial: false,
            requiresCitationIntegrity: false,
            requiresGuardianModeration: false,
            privacyZone: .preference,
            applicableObjectTypes: [.comment]
        ),
        IntelligenceAction(
            id: "comment_report",
            label: "Report",
            accessibilityLabel: "Report",
            category: .safety,
            bereanMode: .guard,
            usesDepthDial: false,
            requiresCitationIntegrity: false,
            requiresGuardianModeration: true,
            privacyZone: .functional,
            applicableObjectTypes: [.comment]
        ),
    ]
}
