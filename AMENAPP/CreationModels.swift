// CreationModels.swift
// AMEN Creator — AI Scene Builder + Living Templates
// All Swift model types for the creation system

import SwiftUI
import FirebaseFirestore

// MARK: - Asset

struct CreationAsset: Identifiable, Codable, Hashable {
    let id: String
    let type: CreationAssetType
    let localURL: String?
    let remoteURL: String?
    let thumbnailURL: String?
    let duration: Double?
    let width: Int?
    let height: Int?
    let createdAt: Date

    static func == (lhs: CreationAsset, rhs: CreationAsset) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

enum CreationAssetType: String, Codable {
    case image
    case video
    case audio
    case text
    case scripture
}

// MARK: - Template

struct CreationTemplate: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let category: CreationTemplateCategory
    let description: String
    let defaultDuration: Double
    let supportsScripture: Bool
    let supportsVoiceover: Bool
    let supportsCaptions: Bool
    let structure: [TemplateStructureRule]
    let adaptationRules: [TemplateAdaptationRule]
    let isSystem: Bool
    let version: Int
    let iconName: String
    let estimatedMinutes: Int

    static func == (lhs: CreationTemplate, rhs: CreationTemplate) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct TemplateStructureRule: Codable, Hashable {
    let kind: CreationSegmentKind
    let maxDuration: Double
    let isRequired: Bool
}

struct TemplateAdaptationRule: Codable, Hashable {
    let condition: String
    let action: String
}

enum CreationTemplateCategory: String, Codable, CaseIterable, Identifiable {
    case testimony      = "testimony"
    case prayer         = "prayer"
    case recap          = "recap"
    case promo          = "promo"
    case verseReflection = "verseReflection"
    case teaching       = "teaching"
    case custom         = "custom"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .testimony:      return "Testimony"
        case .prayer:         return "Prayer"
        case .recap:          return "Recap"
        case .promo:          return "Promo"
        case .verseReflection: return "Verse Reflection"
        case .teaching:       return "Teaching"
        case .custom:         return "Custom"
        }
    }

    var icon: String {
        switch self {
        case .testimony:      return "quote.bubble.fill"
        case .prayer:         return "hands.sparkles.fill"
        case .recap:          return "clock.fill"
        case .promo:          return "megaphone.fill"
        case .verseReflection: return "book.fill"
        case .teaching:       return "graduationcap.fill"
        case .custom:         return "sparkles"
        }
    }

    var color: Color {
        switch self {
        case .testimony:      return .blue
        case .prayer:         return .purple
        case .recap:          return .teal
        case .promo:          return .orange
        case .verseReflection: return Color(red: 0.5, green: 0.3, blue: 0.7)
        case .teaching:       return .brown
        case .custom:         return .gray
        }
    }
}

// MARK: - Scene Plan

struct ScenePlan: Codable, Hashable {
    let id: String
    let templateId: String?
    let titleSuggestion: String?
    let coverTextSuggestion: String?
    let targetDuration: Double
    let tone: CreationSceneTone
    var segments: [CreationTimelineSegment]
    let captionTracks: [CreationCaptionTrack]
    let overlays: [CreationOverlayInstruction]
    let musicSuggestion: CreationMusicSuggestion?
    let safetySummary: CreationSafetySummary
    let createdAt: Date

    static func == (lhs: ScenePlan, rhs: ScenePlan) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Timeline Segment

struct CreationTimelineSegment: Identifiable, Codable, Hashable {
    let id: String
    let kind: CreationSegmentKind
    var assetId: String?
    var startTime: Double?
    var endTime: Double?
    var duration: Double
    var text: String?
    var captionText: String?
    var overlayStyle: CreationOverlayStyle?
    var transitionIn: CreationTransitionStyle?
    var transitionOut: CreationTransitionStyle?
    let emphasis: CreationSegmentEmphasis
    let lockedByAI: Bool

    static func == (lhs: CreationTimelineSegment, rhs: CreationTimelineSegment) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

enum CreationSegmentKind: String, Codable, CaseIterable {
    case intro             = "intro"
    case mainClip          = "mainClip"
    case scriptureOverlay  = "scriptureOverlay"
    case quoteOverlay      = "quoteOverlay"
    case reflectionPrompt  = "reflectionPrompt"
    case outro             = "outro"
    case stillImage        = "stillImage"
    case titleCard         = "titleCard"

    var displayName: String {
        switch self {
        case .intro:            return "Intro"
        case .mainClip:         return "Main Clip"
        case .scriptureOverlay: return "Scripture"
        case .quoteOverlay:     return "Quote"
        case .reflectionPrompt: return "Reflection"
        case .outro:            return "Outro"
        case .stillImage:       return "Still Image"
        case .titleCard:        return "Title Card"
        }
    }

    var icon: String {
        switch self {
        case .intro:            return "play.fill"
        case .mainClip:         return "video.fill"
        case .scriptureOverlay: return "book.fill"
        case .quoteOverlay:     return "quote.opening"
        case .reflectionPrompt: return "thought.bubble.fill"
        case .outro:            return "stop.fill"
        case .stillImage:       return "photo.fill"
        case .titleCard:        return "textformat"
        }
    }

    var color: Color {
        switch self {
        case .intro:            return .blue
        case .mainClip:         return .teal
        case .scriptureOverlay: return .purple
        case .quoteOverlay:     return .orange
        case .reflectionPrompt: return Color(red: 0.4, green: 0.6, blue: 0.4)
        case .outro:            return .gray
        case .stillImage:       return .pink
        case .titleCard:        return .brown
        }
    }
}

enum CreationSceneTone: String, Codable, CaseIterable, Identifiable {
    case hopeful       = "hopeful"
    case reflective    = "reflective"
    case joyful        = "joyful"
    case calm          = "calm"
    case urgent        = "urgent"
    case reverent      = "reverent"
    case encouraging   = "encouraging"

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }

    var icon: String {
        switch self {
        case .hopeful:     return "sun.max.fill"
        case .reflective:  return "moon.fill"
        case .joyful:      return "star.fill"
        case .calm:        return "leaf.fill"
        case .urgent:      return "bolt.fill"
        case .reverent:    return "hands.sparkles.fill"
        case .encouraging: return "heart.fill"
        }
    }
}

enum CreationSegmentEmphasis: String, Codable {
    case low, medium, high
}

enum CreationOverlayStyle: String, Codable, CaseIterable {
    case minimalLowerThird = "minimalLowerThird"
    case centeredScripture = "centeredScripture"
    case pullQuote         = "pullQuote"
    case prayerPrompt      = "prayerPrompt"
    case titleCard         = "titleCard"

    var displayName: String {
        switch self {
        case .minimalLowerThird: return "Lower Third"
        case .centeredScripture: return "Scripture Center"
        case .pullQuote:         return "Pull Quote"
        case .prayerPrompt:      return "Prayer Prompt"
        case .titleCard:         return "Title Card"
        }
    }
}

enum CreationTransitionStyle: String, Codable, CaseIterable {
    case cut        = "cut"
    case softFade   = "softFade"
    case dissolve   = "dissolve"
    case gentleZoom = "gentleZoom"

    var displayName: String {
        switch self {
        case .cut:        return "Cut"
        case .softFade:   return "Soft Fade"
        case .dissolve:   return "Dissolve"
        case .gentleZoom: return "Gentle Zoom"
        }
    }
}

// MARK: - Caption + Overlay

struct CreationCaptionTrack: Identifiable, Codable, Hashable {
    let id: String
    let segmentId: String
    var text: String
    let startTime: Double
    let endTime: Double
}

struct CreationOverlayInstruction: Identifiable, Codable, Hashable {
    let id: String
    let segmentId: String
    let style: CreationOverlayStyle
    var text: String
}

struct CreationMusicSuggestion: Codable, Hashable {
    let mood: String
    let tempo: String
    let usageNotes: String
}

// MARK: - Safety

struct CreationSafetySummary: Codable, Hashable {
    let status: CreationSafetyState
    let flags: [CreationSafetyFlag]
    let notes: [String]
    let canPublish: Bool

    static let approved = CreationSafetySummary(
        status: .approved, flags: [], notes: [], canPublish: true
    )
}

enum CreationSafetyState: String, Codable {
    case approved = "approved"
    case review   = "review"
    case blocked  = "blocked"

    var color: Color {
        switch self {
        case .approved: return .green
        case .review:   return .orange
        case .blocked:  return .red
        }
    }

    var label: String {
        switch self {
        case .approved: return "Approved"
        case .review:   return "Needs Review"
        case .blocked:  return "Blocked"
        }
    }
}

struct CreationSafetyFlag: Identifiable, Codable, Hashable {
    let id: String
    let type: CreationSafetyFlagType
    let severity: Int
    let message: String
}

enum CreationSafetyFlagType: String, Codable {
    case harassment
    case explicit
    case manipulativeEditingPattern
    case misleadingReligiousClaim
    case sensitivePersonalInfo
}

// MARK: - Draft

struct CreationDraft: Identifiable, Codable {
    @DocumentID var id: String?
    var userId: String
    var title: String
    var templateId: String?
    var scenePlanId: String?
    var assetIds: [String]
    var updatedAt: Date
    var status: CreationDraftStatus
    var refinementHistory: [String]

    enum CodingKeys: String, CodingKey {
        case id, userId, title, templateId, scenePlanId
        case assetIds, updatedAt, status, refinementHistory
    }
}

enum CreationDraftStatus: String, Codable {
    case active    = "active"
    case published = "published"
    case abandoned = "abandoned"
}

// MARK: - Studio States

enum CreationStudioState: Equatable {
    case idle
    case selectingAssets
    case selectingTemplate
    case generatingPlan
    case editingTimeline
    case refining(prompt: String)
    case safetyReview
    case previewing
    case publishing
    case published
    case error(String)
}

enum CreationPreviewState: Equatable {
    case idle
    case loading
    case playing
    case paused
    case error(String)
}

enum CreationPublishState: Equatable {
    case idle
    case validating
    case uploading(progress: Double)
    case publishing
    case success
    case failed(String)
}

// MARK: - Refinement Chip

struct CreationRefinementChip: Identifiable {
    let id = UUID()
    let label: String
    let prompt: String
    let icon: String
}

extension CreationRefinementChip {
    static let suggestions: [CreationRefinementChip] = [
        .init(label: "More Hopeful", prompt: "Make the tone more hopeful and uplifting", icon: "sun.max.fill"),
        .init(label: "Shorter",      prompt: "Shorten to 15–20 seconds, keep key moments", icon: "timer"),
        .init(label: "More Scripture", prompt: "Add stronger scripture emphasis throughout", icon: "book.fill"),
        .init(label: "Calmer",       prompt: "Use softer transitions and calmer pacing", icon: "leaf.fill"),
        .init(label: "Simpler",      prompt: "Remove extra text and simplify overlays", icon: "minus.circle.fill"),
        .init(label: "Invite Style", prompt: "Reframe this as an invitation to join or reflect", icon: "envelope.fill"),
        .init(label: "Bold Ending",  prompt: "Strengthen the closing message to be more bold", icon: "bolt.fill"),
        .init(label: "Reflective",   prompt: "Make the overall tone more quiet and reflective", icon: "moon.fill"),
    ]
}

// MARK: - System Templates

extension CreationTemplate {
    static let systemTemplates: [CreationTemplate] = [
        CreationTemplate(
            id: "testimony_story_v1",
            name: "Testimony Story",
            category: .testimony,
            description: "Share how God moved in your life",
            defaultDuration: 30,
            supportsScripture: true,
            supportsVoiceover: true,
            supportsCaptions: true,
            structure: [
                TemplateStructureRule(kind: .intro,            maxDuration: 3,  isRequired: true),
                TemplateStructureRule(kind: .mainClip,         maxDuration: 18, isRequired: true),
                TemplateStructureRule(kind: .scriptureOverlay, maxDuration: 4,  isRequired: false),
                TemplateStructureRule(kind: .reflectionPrompt, maxDuration: 3,  isRequired: false),
                TemplateStructureRule(kind: .outro,            maxDuration: 2,  isRequired: true),
            ],
            adaptationRules: [
                TemplateAdaptationRule(condition: "hasScripture",  action: "prioritize_scripture_overlay"),
                TemplateAdaptationRule(condition: "videoCount>2",  action: "use_best_emotional_window"),
            ],
            isSystem: true, version: 1, iconName: "quote.bubble.fill", estimatedMinutes: 2
        ),
        CreationTemplate(
            id: "prayer_update_v1",
            name: "Prayer Update",
            category: .prayer,
            description: "Share a prayer request or answered prayer",
            defaultDuration: 20,
            supportsScripture: true,
            supportsVoiceover: false,
            supportsCaptions: true,
            structure: [
                TemplateStructureRule(kind: .titleCard,        maxDuration: 3,  isRequired: true),
                TemplateStructureRule(kind: .mainClip,         maxDuration: 12, isRequired: true),
                TemplateStructureRule(kind: .reflectionPrompt, maxDuration: 3,  isRequired: false),
                TemplateStructureRule(kind: .outro,            maxDuration: 2,  isRequired: true),
            ],
            adaptationRules: [],
            isSystem: true, version: 1, iconName: "hands.sparkles.fill", estimatedMinutes: 1
        ),
        CreationTemplate(
            id: "sunday_recap_v1",
            name: "Sunday Recap",
            category: .recap,
            description: "Capture moments from your church service",
            defaultDuration: 45,
            supportsScripture: true,
            supportsVoiceover: false,
            supportsCaptions: true,
            structure: [
                TemplateStructureRule(kind: .intro,            maxDuration: 4,  isRequired: true),
                TemplateStructureRule(kind: .stillImage,       maxDuration: 6,  isRequired: false),
                TemplateStructureRule(kind: .mainClip,         maxDuration: 25, isRequired: true),
                TemplateStructureRule(kind: .scriptureOverlay, maxDuration: 5,  isRequired: false),
                TemplateStructureRule(kind: .outro,            maxDuration: 5,  isRequired: true),
            ],
            adaptationRules: [
                TemplateAdaptationRule(condition: "imageCount>3", action: "create_photo_montage"),
            ],
            isSystem: true, version: 1, iconName: "clock.fill", estimatedMinutes: 3
        ),
        CreationTemplate(
            id: "verse_reflection_v1",
            name: "Verse Reflection",
            category: .verseReflection,
            description: "Meditate on a scripture with imagery",
            defaultDuration: 25,
            supportsScripture: true,
            supportsVoiceover: false,
            supportsCaptions: true,
            structure: [
                TemplateStructureRule(kind: .scriptureOverlay, maxDuration: 6,  isRequired: true),
                TemplateStructureRule(kind: .mainClip,         maxDuration: 15, isRequired: false),
                TemplateStructureRule(kind: .reflectionPrompt, maxDuration: 4,  isRequired: false),
            ],
            adaptationRules: [],
            isSystem: true, version: 1, iconName: "book.fill", estimatedMinutes: 1
        ),
        CreationTemplate(
            id: "church_invite_v1",
            name: "Church Invite",
            category: .promo,
            description: "Invite people to join your service or event",
            defaultDuration: 30,
            supportsScripture: false,
            supportsVoiceover: false,
            supportsCaptions: true,
            structure: [
                TemplateStructureRule(kind: .titleCard,  maxDuration: 4,  isRequired: true),
                TemplateStructureRule(kind: .mainClip,   maxDuration: 18, isRequired: true),
                TemplateStructureRule(kind: .titleCard,  maxDuration: 4,  isRequired: true),
                TemplateStructureRule(kind: .outro,      maxDuration: 4,  isRequired: true),
            ],
            adaptationRules: [],
            isSystem: true, version: 1, iconName: "megaphone.fill", estimatedMinutes: 2
        ),
        CreationTemplate(
            id: "encouragement_clip_v1",
            name: "Encouragement Clip",
            category: .testimony,
            description: "A short word of encouragement for someone",
            defaultDuration: 15,
            supportsScripture: true,
            supportsVoiceover: false,
            supportsCaptions: true,
            structure: [
                TemplateStructureRule(kind: .quoteOverlay, maxDuration: 6,  isRequired: true),
                TemplateStructureRule(kind: .mainClip,     maxDuration: 7,  isRequired: false),
                TemplateStructureRule(kind: .outro,        maxDuration: 2,  isRequired: true),
            ],
            adaptationRules: [],
            isSystem: true, version: 1, iconName: "heart.fill", estimatedMinutes: 1
        ),
    ]
}
