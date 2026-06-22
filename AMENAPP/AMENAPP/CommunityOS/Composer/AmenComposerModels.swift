// AmenComposerModels.swift
// AMEN App — CommunityOS / Composer
//
// Phase 2 — Agent A3 (Universal Composer)
// Domain models for the single unified creation surface.
//
// Types: ComposerSourceType, ComposerSource, ComposerConfig, ComposerDraft
//
// Design (C3): no custom hex colors, no brand colors, no public post counts.
// Uses AmenIntent from CommunityObjectTypes.swift.
// Transform matrix filtering via AmenTransformEngine.

import Foundation

// MARK: - ComposerSourceType

/// The type of content that is seeding (or triggering) the composer.
/// Mirrors the C2 §3 source type set, cast to a composer-side enum so the
/// Composer layer never imports internal graph types directly.
enum ComposerSourceType: String, CaseIterable {
    case newPost            = "post"
    case churchNote         = "churchNote"
    case bereanInsight      = "bereanInsight"
    case event              = "event"
    case prayerRequest      = "prayer"
    case job                = "job"
    case mentorshipRequest  = "mentorship"
    case sermonNote         = "sermon"
    case mediaObject        = "mediaObject"
    case studyNote          = "study"
    case spaceObject        = "space"
    case organizationObject = "organization"
    case scriptureReference = "scriptureReference"

    /// Maps to the canonical AmenObjectType raw value used by the transform engine.
    var amenObjectTypeRaw: String { rawValue }

    /// Human-readable name for provenance banners and accessibility labels.
    var displayName: String {
        switch self {
        case .newPost:            return "Post"
        case .churchNote:         return "Church Note"
        case .bereanInsight:      return "Berean Insight"
        case .event:              return "Event"
        case .prayerRequest:      return "Prayer Request"
        case .job:                return "Job"
        case .mentorshipRequest:  return "Mentorship Request"
        case .sermonNote:         return "Sermon"
        case .mediaObject:        return "Media"
        case .studyNote:          return "Study"
        case .spaceObject:        return "Space"
        case .organizationObject: return "Organization"
        case .scriptureReference: return "Scripture"
        }
    }
}

// MARK: - ComposerSource

/// The complete description of where a composer session originated from.
/// Pass `existingRef = nil` for brand-new, standalone objects.
struct ComposerSource {
    /// What kind of object is being used as the source.
    let type: ComposerSourceType
    /// Firestore document path of the source object (e.g. "/posts/abc123").
    /// `nil` = new standalone object with no parent.
    let existingRef: String?
    /// Firebase Auth UID of the source object's owner. `nil` for standalone.
    let existingOwnerId: String?
    /// Pre-filled body text — e.g. snippet from a Berean chat, share-extension draft.
    let prefillText: String?
    /// Pre-filled title — e.g. sermon title from a church note.
    let prefillTitle: String?

    /// Convenience initialiser for brand-new, standalone creation (no source object).
    static var standalone: ComposerSource {
        ComposerSource(
            type: .newPost,
            existingRef: nil,
            existingOwnerId: nil,
            prefillText: nil,
            prefillTitle: nil
        )
    }
}

// MARK: - ComposerConfig

/// Resolved configuration for one composer session, derived from a
/// `ComposerSource` and the C2 transform matrix.
struct ComposerConfig {

    // MARK: Core intent routing

    /// The intent currently selected in this composer session.
    let intent: AmenIntent
    /// The source that seeded this session.
    let source: ComposerSource
    /// The subset of the 11 canonical intents that are valid for this source type,
    /// based on the C2 transform matrix (blocked cells are excluded).
    let allowedIntents: [AmenIntent]

    // MARK: Privacy & audience

    /// The default audience raw value per C2 §2.3 for the (sourceType × intent) cell.
    let defaultAudience: String

    // MARK: Contextual field toggles

    /// Show the prayer privacy level picker + anonymous toggle.
    let showPrayerPrivacyPicker: Bool
    /// Show job title + organization fields.
    let showJobFields: Bool
    /// Show the event date/time picker.
    let showEventFields: Bool
    /// Show the scripture reference field.
    let showStudyFields: Bool
    /// Show the title field (jobs, events, announcements require a title).
    let showTitleField: Bool

    // MARK: Safety & moderation

    /// True when the output object must carry a provenance back-link.
    let requiresProvenance: Bool
    /// Moderation tier raw value for this (sourceType × intent) cell.
    let moderationTier: String

    // MARK: - Factory

    /// Builds the complete `ComposerConfig` for a given source + optional intent.
    ///
    /// - If `intent` is nil, defaults to the first allowed intent for the source type.
    /// - Blocked matrix cells are excluded from `allowedIntents`.
    static func config(for source: ComposerSource, intent: AmenIntent? = nil) -> ComposerConfig {
        let engine = AmenTransformEngine()
        let sourceObjectType = AmenObjectType(rawValue: source.type.amenObjectTypeRaw)

        // Resolve allowed intents by querying the matrix for every candidate.
        let allowed: [AmenIntent] = AmenIntent.allCases.filter { candidate in
            guard let ot = sourceObjectType else { return true }
            return engine.isSupported(sourceType: ot, intent: candidate)
        }

        let resolvedAllowed = allowed.isEmpty ? AmenIntent.allCases : allowed
        let resolvedIntent = intent ?? resolvedAllowed.first ?? .discuss

        // Determine the transform config for the resolved (source x intent) pair.
        let transformConfig: TransformConfig? = {
            guard let ot = sourceObjectType else { return nil }
            return engine.config(for: ot, intent: resolvedIntent)
        }()

        let defaultAudience = transformConfig?.defaultAudience ?? "private"
        let moderationTier  = transformConfig?.moderationTier.rawValue ?? ModerationTier.medium.rawValue

        let showPrayer = resolvedIntent == .pray
        let showJob    = resolvedIntent == .hire || source.type == .job
        let showEvent  = resolvedIntent == .invite || source.type == .event
        let showStudy  = resolvedIntent == .study
        let showTitle  = resolvedIntent == .hire
                      || resolvedIntent == .announce
                      || resolvedIntent == .invite
                      || source.type == .event
                      || source.type == .job

        return ComposerConfig(
            intent: resolvedIntent,
            source: source,
            allowedIntents: resolvedAllowed,
            defaultAudience: defaultAudience,
            showPrayerPrivacyPicker: showPrayer,
            showJobFields: showJob,
            showEventFields: showEvent,
            showStudyFields: showStudy,
            showTitleField: showTitle,
            requiresProvenance: source.existingRef != nil,
            moderationTier: moderationTier
        )
    }
}

// MARK: - ComposerDraft

/// Mutable working copy of the content being composed.
/// Owned by `AmenComposerViewModel`; passed to the repository on submit.
struct ComposerDraft {

    // MARK: Core content

    /// Title — required for jobs, events, and announcements.
    var title: String = ""
    /// Body / main text of the post or prayer.
    var body: String = ""
    /// Intent selected by the user in this session.
    var selectedIntent: AmenIntent = .discuss

    // MARK: Audience

    /// Audience raw value. Default comes from the ComposerConfig.
    var audience: String = "private"

    // MARK: Prayer-specific

    /// Privacy level for prayer-type posts.
    /// Values: "private" | "trusted_circle" | "members_only" | "anonymous" | "public"
    var prayerPrivacyLevel: String = "private"
    /// True when the prayer should be posted anonymously.
    var isAnonymous: Bool = false

    // MARK: Job-specific

    /// Job title — used when intent is `.hire`.
    var jobTitle: String = ""
    /// Organization name — used when intent is `.hire`.
    var jobOrganization: String = ""

    // MARK: Event-specific

    /// Event date/time — used when intent is `.invite` from an event source.
    var eventDate: Date? = nil

    // MARK: Study-specific

    /// Scripture reference string — used when intent is `.study`.
    var scriptureReference: String = ""

    // MARK: Scheduling & location

    /// Optional future publish date.
    var scheduledDate: Date? = nil
    /// True when the user has granted location for this post.
    var locationEnabled: Bool = false

    // MARK: Media

    /// Local file URLs of picked media attachments.
    var attachments: [URL] = []

    // MARK: Provenance

    /// Firestore path of the source object (copied from ComposerSource on init).
    var sourceRef: String? = nil
    /// AmenObjectType raw value of the source (copied from ComposerSource on init).
    var sourceType: String? = nil
}
