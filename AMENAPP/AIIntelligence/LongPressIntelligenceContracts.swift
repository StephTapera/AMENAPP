// LongPressIntelligenceContracts.swift
// AMENAPP — Long-Press Intelligence Layer ("Press to Ask Berean")
//
// Wave 0 Swift mirrors of src/berean/longPressContracts.ts.
// TypeScript is source of truth. Keep in sync; add no behavior here.
//
// ARCHITECTURE INVARIANTS:
//   - ONE BereanDepth enum app-wide (BereanSpiritualIntelligenceContracts.swift)
//   - ONE LongPressIntelligenceMenu component; no per-screen reimplementation
//   - Entry surface into existing Berean (mode × depth × context)
//   - Adding an object type = registering its actions; no bespoke menus
//   - Text selection uses OS selection + Berean-in-selection-menu; no collision

import Foundation

// MARK: - Object Type

enum LongPressObjectType: String, Codable, CaseIterable, Sendable {
    case post           = "post"
    case comment        = "comment"
    case verse          = "verse"
    case creator        = "creator"
    case community      = "community"
    case video          = "video"
    case event          = "event"
    case resource       = "resource"
    case profileAvatar  = "profile_avatar"
    case message        = "message"
    case textSelection  = "text_selection"
}

enum LongPressSourceSurface: String, Codable, Sendable {
    case feed           = "feed"
    case creatorPage    = "creator_page"
    case community      = "community"
    case scriptureReader = "scripture_reader"
    case conversation   = "conversation"
    case search         = "search"
    case notification   = "notification"
    case spotlight      = "spotlight"
}

// MARK: - Object Context

/// Captured on press — tells Berean what it is reasoning about.
/// Captured at press time (not action-tap time) so warm-up can begin.
struct BereanObjectContext: Codable, Sendable {
    let objectType: LongPressObjectType
    let objectId: String
    let sourceSurface: LongPressSourceSurface
    /// epoch seconds — captured on press
    let capturedAt: TimeInterval

    // Typed payload fields (only relevant fields populated per objectType)
    let payloadText: String?
    let payloadAuthorId: String?
    let payloadThreadId: String?
    let payloadReference: String?    // Verse reference
    let payloadTranslation: String?  // Verse translation
    let payloadCreatorId: String?
    let payloadDisplayName: String?
    let payloadCommunityId: String?
    let payloadVideoId: String?
    let payloadDurationSeconds: Int?
    let payloadEventId: String?
    let payloadResourceId: String?
    let payloadFormat: String?
    let payloadUserId: String?
    let payloadMessageId: String?
    let payloadSelectedText: String?
    let payloadSourceObjectId: String?
    let payloadSourceObjectType: String?
}

// MARK: - Intelligence Action Descriptor

enum IntelligenceActionCategory: String, Codable, Sendable {
    case quick        = "quick"        // Non-AI: Reply, Save, Share
    case smart        = "smart"        // AI-powered via Berean
    case relationship = "relationship" // Social: Follow, View profile
    case safety       = "safety"       // Report, Hide, Mute → GUARDIAN
}

struct IntelligenceAction: Codable, Identifiable, Sendable {
    let id: String
    let label: String
    /// Required for VoiceOver rotor custom action
    let accessibilityLabel: String
    let category: IntelligenceActionCategory
    /// nil for non-AI actions; maps to existing BereanMode
    let bereanMode: BereanMode?
    /// Show depth dial UI only when true
    let usesDepthDial: Bool
    /// All scripture output must pass CitationVerdict when true
    let requiresCitationIntegrity: Bool
    /// Route through GUARDIAN when true
    let requiresGuardianModeration: Bool
    let privacyZone: PrivacyCoreZone
    let applicableObjectTypes: [LongPressObjectType]
}

// MARK: - Action Registry (extension model)

struct ActionRegistryEntry: Codable, Sendable {
    let objectType: LongPressObjectType
    let actions: [IntelligenceAction]
}

typealias ActionRegistry = [ActionRegistryEntry]

// MARK: - Depth Dial State

/// Manual override of auto-selected depth. ONE unified dial.
/// Defaults to IntentSwitch auto-selected value.
struct DepthDialState: Codable, Sendable {
    /// Proposed by Intent Switch; this is the default shown
    let autoSelectedDepth: BereanDepth
    /// Set when user nudges the dial
    let manualOverride: BereanDepth?
    /// = manualOverride ?? autoSelectedDepth
    var effectiveDepth: BereanDepth { manualOverride ?? autoSelectedDepth }
    let threadId: String
}

// MARK: - Adaptive Reach (on-device only; user-resettable; never exported)

/// Local tap-frequency record. Actions migrate toward thumb based on usage.
/// Stored on-device only; cleared on user reset; never uploaded or exported.
struct AdaptiveReachRecord: Codable, Sendable {
    let actionId: String
    let objectType: LongPressObjectType
    var tapCount: Int
    var lastTappedAt: TimeInterval
    // Invariant: zone is always .functional (lowest viable)
    let privacyZone: PrivacyCoreZone  // Always .functional
}
