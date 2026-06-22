// LongPressExtendedRegistry.swift
// AMENAPP — Long-Press Intelligence Layer (Wave 2)
//
// Extension on LongPressActionRegistry that registers the remaining 8 object types:
// .post, .creator, .community, .video, .event, .resource, .profileAvatar, .message
//
// Do NOT modify LongPressActionRegistry.swift. Extend it here only.
//
// Callers should use `allActions(for:)` which merges Wave-1 registry entries
// with these Wave-2 extended actions.

import Foundation

extension LongPressActionRegistry {

    // MARK: - Unified Entry Point

    /// Returns all registered actions for an object type, merging Wave-1 and Wave-2 entries.
    /// Callers should prefer this over the base `actions(for:)`.
    func allActions(for objectType: LongPressObjectType) -> [IntelligenceAction] {
        actions(for: objectType) + extendedActions(for: objectType)
    }

    // MARK: - Extended Actions Dispatch

    func extendedActions(for objectType: LongPressObjectType) -> [IntelligenceAction] {
        switch objectType {
        case .post:           return postActions
        case .creator:        return creatorActions
        case .profileAvatar:  return profileAvatarActions
        case .community:      return communityActions
        case .video:          return videoActions
        case .event:          return eventActions
        case .resource:       return resourceActions
        case .message:        return messageActions
        case .verse, .comment, .textSelection:
            return []
        }
    }

    // MARK: - Post Actions

    private var postActions: [IntelligenceAction] {[
        IntelligenceAction(
            id: "post_summarize",
            label: "Summarize",
            accessibilityLabel: "Summarize",
            category: .smart,
            bereanMode: .ask,
            usesDepthDial: true,
            requiresCitationIntegrity: false,
            requiresGuardianModeration: false,
            privacyZone: .functional,
            applicableObjectTypes: [.post]
        ),
        IntelligenceAction(
            id: "post_extract_ideas",
            label: "Extract Key Ideas",
            accessibilityLabel: "Extract Key Ideas",
            category: .smart,
            bereanMode: .ask,
            usesDepthDial: true,
            requiresCitationIntegrity: false,
            requiresGuardianModeration: false,
            privacyZone: .functional,
            applicableObjectTypes: [.post]
        ),
        IntelligenceAction(
            id: "post_create_study",
            label: "Create Study",
            accessibilityLabel: "Create Study",
            category: .smart,
            bereanMode: .build,
            usesDepthDial: true,
            requiresCitationIntegrity: true,
            requiresGuardianModeration: false,
            privacyZone: .functional,
            applicableObjectTypes: [.post]
        ),
        IntelligenceAction(
            id: "post_save",
            label: "Save",
            accessibilityLabel: "Save",
            category: .quick,
            bereanMode: nil,
            usesDepthDial: false,
            requiresCitationIntegrity: false,
            requiresGuardianModeration: false,
            privacyZone: .functional,
            applicableObjectTypes: [.post]
        ),
        IntelligenceAction(
            id: "post_share",
            label: "Share",
            accessibilityLabel: "Share",
            category: .quick,
            bereanMode: nil,
            usesDepthDial: false,
            requiresCitationIntegrity: false,
            requiresGuardianModeration: false,
            privacyZone: .functional,
            applicableObjectTypes: [.post]
        ),
        IntelligenceAction(
            id: "post_not_interested",
            label: "Not Interested",
            accessibilityLabel: "Not Interested",
            category: .quick,
            bereanMode: nil,
            usesDepthDial: false,
            requiresCitationIntegrity: false,
            requiresGuardianModeration: false,
            privacyZone: .functional,
            applicableObjectTypes: [.post]
        ),
        IntelligenceAction(
            id: "post_report",
            label: "Report",
            accessibilityLabel: "Report",
            category: .safety,
            bereanMode: .guard,
            usesDepthDial: false,
            requiresCitationIntegrity: false,
            requiresGuardianModeration: true,
            privacyZone: .functional,
            applicableObjectTypes: [.post]
        ),
    ]}

    // MARK: - Creator Actions

    private var creatorActions: [IntelligenceAction] {[
        IntelligenceAction(
            id: "creator_follow",
            label: "Follow",
            accessibilityLabel: "Follow",
            category: .quick,
            bereanMode: nil,
            usesDepthDial: false,
            requiresCitationIntegrity: false,
            requiresGuardianModeration: false,
            privacyZone: .functional,
            applicableObjectTypes: [.creator]
        ),
        // "Suggested by Berean" — labeled via accessibilityLabel addendum
        IntelligenceAction(
            id: "creator_summary",
            label: "Creator Summary",
            accessibilityLabel: "Creator Summary, Suggested by Berean",
            category: .smart,
            bereanMode: .ask,
            usesDepthDial: true,
            requiresCitationIntegrity: false,
            requiresGuardianModeration: false,
            privacyZone: .functional,
            applicableObjectTypes: [.creator]
        ),
        // note: "descriptive, never a popularity rank"
        IntelligenceAction(
            id: "creator_foundational",
            label: "Foundational Teachings",
            accessibilityLabel: "Foundational Teachings",
            category: .smart,
            bereanMode: .ask,
            usesDepthDial: false,
            requiresCitationIntegrity: false,
            requiresGuardianModeration: false,
            privacyZone: .functional,
            applicableObjectTypes: [.creator]
        ),
        IntelligenceAction(
            id: "creator_message",
            label: "Message",
            accessibilityLabel: "Message",
            category: .relationship,
            bereanMode: nil,
            usesDepthDial: false,
            requiresCitationIntegrity: false,
            requiresGuardianModeration: false,
            privacyZone: .functional,
            applicableObjectTypes: [.creator]
        ),
        IntelligenceAction(
            id: "creator_share",
            label: "Share",
            accessibilityLabel: "Share",
            category: .quick,
            bereanMode: nil,
            usesDepthDial: false,
            requiresCitationIntegrity: false,
            requiresGuardianModeration: false,
            privacyZone: .functional,
            applicableObjectTypes: [.creator]
        ),
    ]}

    // MARK: - Profile / Avatar Actions

    private var profileAvatarActions: [IntelligenceAction] {[
        IntelligenceAction(
            id: "profile_follow",
            label: "Follow",
            accessibilityLabel: "Follow",
            category: .relationship,
            bereanMode: nil,
            usesDepthDial: false,
            requiresCitationIntegrity: false,
            requiresGuardianModeration: false,
            privacyZone: .functional,
            applicableObjectTypes: [.profileAvatar]
        ),
        IntelligenceAction(
            id: "profile_message",
            label: "Message",
            accessibilityLabel: "Message",
            category: .relationship,
            bereanMode: nil,
            usesDepthDial: false,
            requiresCitationIntegrity: false,
            requiresGuardianModeration: false,
            privacyZone: .functional,
            applicableObjectTypes: [.profileAvatar]
        ),
        IntelligenceAction(
            id: "profile_shared_topics",
            label: "Shared Study Topics",
            accessibilityLabel: "Shared Study Topics",
            category: .smart,
            bereanMode: .ask,
            usesDepthDial: false,
            requiresCitationIntegrity: false,
            requiresGuardianModeration: false,
            privacyZone: .functional,
            applicableObjectTypes: [.profileAvatar]
        ),
        IntelligenceAction(
            id: "profile_mute",
            label: "Mute",
            accessibilityLabel: "Mute",
            category: .safety,
            bereanMode: nil,
            usesDepthDial: false,
            requiresCitationIntegrity: false,
            requiresGuardianModeration: false,
            privacyZone: .functional,
            applicableObjectTypes: [.profileAvatar]
        ),
    ]}

    // MARK: - Community Actions

    private var communityActions: [IntelligenceAction] {[
        IntelligenceAction(
            id: "community_join",
            label: "Join",
            accessibilityLabel: "Join",
            category: .quick,
            bereanMode: nil,
            usesDepthDial: false,
            requiresCitationIntegrity: false,
            requiresGuardianModeration: false,
            privacyZone: .functional,
            applicableObjectTypes: [.community]
        ),
        IntelligenceAction(
            id: "community_snapshot",
            label: "Community Snapshot",
            accessibilityLabel: "Community Snapshot",
            category: .smart,
            bereanMode: .ask,
            usesDepthDial: false,
            requiresCitationIntegrity: false,
            requiresGuardianModeration: false,
            privacyZone: .functional,
            applicableObjectTypes: [.community]
        ),
        IntelligenceAction(
            id: "community_invite",
            label: "Invite Friends",
            accessibilityLabel: "Invite Friends",
            category: .quick,
            bereanMode: nil,
            usesDepthDial: false,
            requiresCitationIntegrity: false,
            requiresGuardianModeration: false,
            privacyZone: .functional,
            applicableObjectTypes: [.community]
        ),
        IntelligenceAction(
            id: "community_save",
            label: "Save",
            accessibilityLabel: "Save",
            category: .quick,
            bereanMode: nil,
            usesDepthDial: false,
            requiresCitationIntegrity: false,
            requiresGuardianModeration: false,
            privacyZone: .functional,
            applicableObjectTypes: [.community]
        ),
    ]}

    // MARK: - Video Actions

    private var videoActions: [IntelligenceAction] {[
        IntelligenceAction(
            id: "video_generate_notes",
            label: "Generate Notes",
            accessibilityLabel: "Generate Notes",
            category: .smart,
            bereanMode: .build,
            usesDepthDial: true,
            requiresCitationIntegrity: true,
            requiresGuardianModeration: false,
            privacyZone: .functional,
            applicableObjectTypes: [.video]
        ),
        IntelligenceAction(
            id: "video_find_verses",
            label: "Find Mentioned Verses",
            accessibilityLabel: "Find Mentioned Verses",
            category: .smart,
            bereanMode: .ask,
            usesDepthDial: true,
            requiresCitationIntegrity: true,
            requiresGuardianModeration: false,
            privacyZone: .functional,
            applicableObjectTypes: [.video]
        ),
        IntelligenceAction(
            id: "video_ask_berean",
            label: "Ask Berean About This",
            accessibilityLabel: "Ask Berean About This",
            category: .smart,
            bereanMode: .ask,
            usesDepthDial: true,
            requiresCitationIntegrity: false,
            requiresGuardianModeration: false,
            privacyZone: .functional,
            applicableObjectTypes: [.video]
        ),
        IntelligenceAction(
            id: "video_save",
            label: "Save",
            accessibilityLabel: "Save",
            category: .quick,
            bereanMode: nil,
            usesDepthDial: false,
            requiresCitationIntegrity: false,
            requiresGuardianModeration: false,
            privacyZone: .functional,
            applicableObjectTypes: [.video]
        ),
        IntelligenceAction(
            id: "video_share",
            label: "Share",
            accessibilityLabel: "Share",
            category: .quick,
            bereanMode: nil,
            usesDepthDial: false,
            requiresCitationIntegrity: false,
            requiresGuardianModeration: false,
            privacyZone: .functional,
            applicableObjectTypes: [.video]
        ),
    ]}

    // MARK: - Event Actions

    private var eventActions: [IntelligenceAction] {[
        IntelligenceAction(
            id: "event_register",
            label: "Register",
            accessibilityLabel: "Register",
            category: .quick,
            bereanMode: nil,
            usesDepthDial: false,
            requiresCitationIntegrity: false,
            requiresGuardianModeration: false,
            privacyZone: .functional,
            applicableObjectTypes: [.event]
        ),
        IntelligenceAction(
            id: "event_save",
            label: "Save",
            accessibilityLabel: "Save",
            category: .quick,
            bereanMode: nil,
            usesDepthDial: false,
            requiresCitationIntegrity: false,
            requiresGuardianModeration: false,
            privacyZone: .functional,
            applicableObjectTypes: [.event]
        ),
        IntelligenceAction(
            id: "event_share",
            label: "Share",
            accessibilityLabel: "Share",
            category: .quick,
            bereanMode: nil,
            usesDepthDial: false,
            requiresCitationIntegrity: false,
            requiresGuardianModeration: false,
            privacyZone: .functional,
            applicableObjectTypes: [.event]
        ),
        IntelligenceAction(
            id: "event_ask_berean",
            label: "Ask Berean About This",
            accessibilityLabel: "Ask Berean About This",
            category: .smart,
            bereanMode: .ask,
            usesDepthDial: true,
            requiresCitationIntegrity: false,
            requiresGuardianModeration: false,
            privacyZone: .functional,
            applicableObjectTypes: [.event]
        ),
    ]}

    // MARK: - Resource Actions

    private var resourceActions: [IntelligenceAction] {[
        IntelligenceAction(
            id: "resource_save",
            label: "Save",
            accessibilityLabel: "Save",
            category: .quick,
            bereanMode: nil,
            usesDepthDial: false,
            requiresCitationIntegrity: false,
            requiresGuardianModeration: false,
            privacyZone: .functional,
            applicableObjectTypes: [.resource]
        ),
        IntelligenceAction(
            id: "resource_create_study",
            label: "Create Study",
            accessibilityLabel: "Create Study",
            category: .smart,
            bereanMode: .build,
            usesDepthDial: true,
            requiresCitationIntegrity: true,
            requiresGuardianModeration: false,
            privacyZone: .functional,
            applicableObjectTypes: [.resource]
        ),
        IntelligenceAction(
            id: "resource_share",
            label: "Share",
            accessibilityLabel: "Share",
            category: .quick,
            bereanMode: nil,
            usesDepthDial: false,
            requiresCitationIntegrity: false,
            requiresGuardianModeration: false,
            privacyZone: .functional,
            applicableObjectTypes: [.resource]
        ),
    ]}

    // MARK: - Message Actions

    private var messageActions: [IntelligenceAction] {[
        IntelligenceAction(
            id: "message_find_verses",
            label: "Find Bible Verses",
            accessibilityLabel: "Find Bible Verses",
            category: .smart,
            bereanMode: .ask,
            usesDepthDial: true,
            requiresCitationIntegrity: true,
            requiresGuardianModeration: false,
            privacyZone: .functional,
            applicableObjectTypes: [.message]
        ),
        IntelligenceAction(
            id: "message_turn_into_prayer",
            label: "Turn Into Prayer",
            accessibilityLabel: "Turn Into Prayer",
            category: .smart,
            bereanMode: .reflect,
            usesDepthDial: false,
            requiresCitationIntegrity: false,
            requiresGuardianModeration: false,
            privacyZone: .functional,
            applicableObjectTypes: [.message]
        ),
        IntelligenceAction(
            id: "message_save_insight",
            label: "Save Insight",
            accessibilityLabel: "Save Insight",
            category: .quick,
            bereanMode: nil,
            usesDepthDial: false,
            requiresCitationIntegrity: false,
            requiresGuardianModeration: false,
            privacyZone: .functional,
            applicableObjectTypes: [.message]
        ),
    ]}
}
