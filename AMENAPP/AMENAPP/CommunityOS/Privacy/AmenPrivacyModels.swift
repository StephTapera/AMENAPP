// AmenPrivacyModels.swift
// AMENAPP — CommunityOS/Privacy
//
// Phase 4 — Agent TS-a (Privacy Engine)
// Privacy preset system: presets, settings struct, redaction config, and DM policy.
//
// Contract references:
//   C5 §3 (Privacy Level Rules), C5 §4 (Minor-Specific Rules),
//   C5 §5 Invariants I-3, I-5, I-6
//
// Rules:
//   • Minors always enforce .private preset + .mutualFollows DM policy. NO client override.
//   • Anonymous preset: identity shielded server-side (C5 §3b). Client never writes ownerUidEncrypted.
//   • delayMinutes: client records intent only; actual scheduling is CF-side.
//   • No raw location ever stored without explicit opt-in (locationSharingLevel).

import Foundation

// MARK: - AmenPrivacyPreset

/// Four named privacy presets that users can select.
/// Each preset derives sensible defaults for post audience, search visibility,
/// location sharing, and profile visibility. Fine-grained overrides live in
/// `PrivacySettings.customOverrides`.
///
/// Contract alignment: C5 §3a (Defined Privacy Levels).
enum AmenPrivacyPreset: String, Codable, CaseIterable {
    /// Posts public, profile fully visible, location may be shared.
    case open
    /// Posts visible to followers only, partial profile, no location.
    case balanced
    /// Posts visible to trusted circle only, minimal profile, no location.
    case `private`
    /// Content publicly accessible but identity is shielded (C5 §3b Anonymous).
    case anonymous

    // MARK: Display

    var displayName: String {
        switch self {
        case .open:       return "Open"
        case .balanced:   return "Balanced"
        case .private:    return "Private"
        case .anonymous:  return "Anonymous"
        }
    }

    var systemImage: String {
        switch self {
        case .open:       return "globe"
        case .balanced:   return "person.2.fill"
        case .private:    return "lock.fill"
        case .anonymous:  return "person.fill.questionmark"
        }
    }

    var description: String {
        switch self {
        case .open:
            return "Your posts and profile are visible to everyone. Location may be shared with your explicit opt-in."
        case .balanced:
            return "Your posts reach followers only. Your profile shows limited information. Location is not shared."
        case .private:
            return "Posts are visible only to your trusted circle. Profile is minimal. Location is never shared."
        case .anonymous:
            return "Your content is publicly visible but your identity is hidden. Your name is not shown. Content is still subject to moderation."
        }
    }

    // MARK: Derived Defaults

    /// Firestore audience value used when creating a new post under this preset.
    /// Matches C5 §3a audience expectations.
    var defaultPostAudience: String {
        switch self {
        case .open:       return "public"
        case .balanced:   return "followers"
        case .private:    return "trustedCircle"
        case .anonymous:  return "anonymous"
        }
    }

    /// Whether the user appears in platform search results.
    var showInSearch: Bool {
        switch self {
        case .open:       return true
        case .balanced:   return true
        case .private:    return false
        case .anonymous:  return false
        }
    }

    /// Default location sharing level for this preset.
    var locationSharing: LocationSharingLevel {
        switch self {
        case .open:       return .city
        case .balanced:   return .none
        case .private:    return .none
        case .anonymous:  return .none
        }
    }

    /// Default profile visibility for this preset.
    var profileVisibility: ProfileVisibilityLevel {
        switch self {
        case .open:       return .full
        case .balanced:   return .partial
        case .private:    return .minimal
        case .anonymous:  return .hidden
        }
    }
}

// MARK: - LocationSharingLevel

/// Granularity at which the user's location may be surfaced.
/// No precise coordinates are ever stored in user-visible posts without `.precise` opt-in.
/// Contract: C5 §5 I-5 (no raw PII in listings).
enum LocationSharingLevel: String, Codable, CaseIterable {
    /// Exact coordinates — requires explicit in-app prompt approval.
    case precise
    /// City-level text only (e.g. "Austin, TX").
    case city
    /// Location sharing disabled entirely.
    case none
}

// MARK: - ProfileVisibilityLevel

/// How much of a user's profile is exposed to non-followers.
enum ProfileVisibilityLevel: String, Codable, CaseIterable {
    /// All fields visible: display name, bio, avatar, church, stats.
    case full
    /// Display name + bio visible; no avatar, no church affiliation, no stats.
    case partial
    /// Display name only.
    case minimal
    /// Profile not directly accessible. Used by .anonymous preset.
    case hidden
}

// MARK: - DMSenderPolicy

/// Who is permitted to initiate a direct message conversation with the user.
///
/// [MINOR] Contract C5 §4b: Minors are always capped at `.mutualFollows`.
/// No client-side code may set a Minor's policy higher than `.mutualFollows`.
enum DMSenderPolicy: String, Codable, CaseIterable {
    /// No one may initiate DMs. The user can still reply to existing threads.
    case nobody
    /// Only mutual follows (both parties follow each other) may send a DM.
    /// This is the maximum allowed for Minors — C5 §4b.
    case mutualFollows
    /// Verified church members in a shared church may send DMs.
    case churchMembers
    /// Any authenticated user may send a DM (subject to block list).
    case everyone

    var displayName: String {
        switch self {
        case .nobody:        return "Nobody"
        case .mutualFollows: return "Mutual Follows"
        case .churchMembers: return "Church Members"
        case .everyone:      return "Everyone"
        }
    }
}

// MARK: - PrivacySettings

/// Full privacy configuration for a single user.
/// Stored at `/users/{uid}/private/privacy_settings` in Firestore.
/// Only the user or a Cloud Function (Admin SDK) may write this document.
///
/// [MINOR] If `isMinor == true`, the engine enforces overrides at write time and
/// rejects any preset above `.private` or any DMSenderPolicy above `.mutualFollows`.
struct PrivacySettings: Codable {
    // MARK: Identity

    var userId: String

    // MARK: Preset

    /// Active preset. See `AmenPrivacyPreset` for derived defaults.
    var preset: AmenPrivacyPreset

    /// Fine-grained per-feature boolean overrides.
    /// Key examples: "allow_tagging", "show_prayer_count", "show_join_date".
    /// `nil` key = uses preset default; `true`/`false` = explicit override.
    var customOverrides: [String: Bool]

    // MARK: Location & Profile

    var locationSharingLevel: LocationSharingLevel
    var profileVisibility: ProfileVisibilityLevel

    // MARK: Minor Flag [MINOR]

    /// Set by the CF age-assurance pipeline. Never written by the client.
    /// When `true`, the engine enforces C5 §4 minor defaults on every write.
    var isMinor: Bool

    // MARK: DMs

    /// Who may start a new DM conversation with this user.
    /// [MINOR] Capped at `.mutualFollows` when `isMinor == true`.
    var allowedDMSenders: DMSenderPolicy

    // MARK: Delayed Posting

    /// Whether the user has enabled the posting delay feature.
    /// When `true`, new posts are held for `delayMinutes` before publishing.
    /// Actual scheduling is performed by the Cloud Function; the client only records this intent.
    var delayedPostingEnabled: Bool

    /// How many minutes to delay a post before it is published. Range: 0–60.
    var delayMinutes: Int

    // MARK: Discoverability

    /// Allow other users to find this account via their contacts list.
    var contactsDiscoveryEnabled: Bool

    /// Allow discovery via email address lookup.
    var searchableByEmail: Bool

    /// Allow discovery via phone number lookup.
    var searchableByPhone: Bool

    // MARK: Timestamps

    var updatedAt: Date

    // MARK: - Init (safe defaults)

    init(
        userId: String,
        preset: AmenPrivacyPreset = .balanced,
        customOverrides: [String: Bool] = [:],
        locationSharingLevel: LocationSharingLevel = .none,
        profileVisibility: ProfileVisibilityLevel = .partial,
        isMinor: Bool = false,
        allowedDMSenders: DMSenderPolicy = .mutualFollows,
        delayedPostingEnabled: Bool = false,
        delayMinutes: Int = 10,
        contactsDiscoveryEnabled: Bool = false,
        searchableByEmail: Bool = false,
        searchableByPhone: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.userId = userId
        self.preset = preset
        self.customOverrides = customOverrides
        self.locationSharingLevel = locationSharingLevel
        self.profileVisibility = profileVisibility
        self.isMinor = isMinor
        self.allowedDMSenders = allowedDMSenders
        self.delayedPostingEnabled = delayedPostingEnabled
        self.delayMinutes = max(0, min(60, delayMinutes))
        self.contactsDiscoveryEnabled = contactsDiscoveryEnabled
        self.searchableByEmail = searchableByEmail
        self.searchableByPhone = searchableByPhone
        self.updatedAt = updatedAt
    }
}

// MARK: - PrivacySettings Minor Enforcement Extension

extension PrivacySettings {
    /// Returns a copy of these settings with all minor-mandated overrides applied.
    /// [MINOR] C5 §4a: Minors default to .private; DM capped at .mutualFollows.
    func withMinorDefaultsEnforced() -> PrivacySettings {
        guard isMinor else { return self }
        var copy = self
        // Force preset to .private if currently more permissive
        if copy.preset == .open || copy.preset == .balanced {
            copy.preset = .private
        }
        // Derive private preset defaults
        copy.locationSharingLevel = .none
        copy.profileVisibility = .minimal
        // Cap DM policy — mutualFollows is the maximum for minors
        if copy.allowedDMSenders == .churchMembers || copy.allowedDMSenders == .everyone {
            copy.allowedDMSenders = .mutualFollows
        }
        // No discoverability for minors
        copy.contactsDiscoveryEnabled = false
        copy.searchableByEmail = false
        copy.searchableByPhone = false
        return copy
    }
}

// MARK: - ProfileContactField (per-field profile visibility)

/// A sensitive contact field that the user can individually choose to show or hide
/// on their profile. Backed by `PrivacySettings.customOverrides` keys, so adding
/// these introduces NO Codable schema migration (existing privacy_settings docs
/// decode unchanged; a missing key simply means "hidden", the safe default).
///
/// Trust & Safety Remediation item 21 follow-on (per-field profile hide).
enum ProfileContactField: String, CaseIterable, Identifiable {
    case email
    case phone
    case birthday

    var id: String { rawValue }

    /// The `customOverrides` key that stores this field's visibility preference.
    var overrideKey: String {
        switch self {
        case .email:    return "show_email"
        case .phone:    return "show_phone"
        case .birthday: return "show_birthday"
        }
    }

    var displayName: String {
        switch self {
        case .email:    return "Email address"
        case .phone:    return "Phone number"
        case .birthday: return "Birthday"
        }
    }

    var systemImage: String {
        switch self {
        case .email:    return "envelope.fill"
        case .phone:    return "phone.fill"
        case .birthday: return "gift.fill"
        }
    }

    /// Subtitle shown under the toggle in settings.
    var privacyHint: String {
        switch self {
        case .email:    return "Hidden by default. Turn on to show your email on your profile."
        case .phone:    return "Hidden by default. Turn on to show your phone number on your profile."
        case .birthday: return "Hidden by default. Turn on to show your birthday on your profile."
        }
    }
}

// MARK: - PrivacySettings Per-Field Visibility Extension

extension PrivacySettings {
    /// Whether the user has opted to show `field` on their profile.
    /// Sensitive contact fields default to HIDDEN (false) until explicitly enabled.
    /// [MINOR] Always hidden for minors — contact PII is never exposed.
    func showsProfileField(_ field: ProfileContactField) -> Bool {
        if isMinor { return false }
        return customOverrides[field.overrideKey] ?? false
    }

    /// Returns a copy with `field` visibility set. [MINOR] No-op for minors.
    func settingProfileField(_ field: ProfileContactField, visible: Bool) -> PrivacySettings {
        guard !isMinor else { return self }
        var copy = self
        copy.customOverrides[field.overrideKey] = visible
        copy.updatedAt = Date()
        return copy
    }

    /// Whether `field` is visible to a viewer of `audience`. The owner always sees
    /// their own fields; everyone else requires the opt-in AND an audience that the
    /// active preset would expose the profile to.
    func isProfileField(_ field: ProfileContactField, visibleTo audience: AudienceType) -> Bool {
        if audience == .selfViewer { return true }
        guard showsProfileField(field) else { return false }
        switch preset {
        case .anonymous:
            return false
        case .private:
            return audience == .trustedContact
        case .balanced:
            return audience == .mutualFollow
                || audience == .churchMember
                || audience == .trustedContact
        case .open:
            return audience != .anonymous
        }
    }
}

// MARK: - RedactionConfig

/// Configuration for the text/media redaction pipeline.
/// Used by `AmenPrivacyEngine.redactForPublic(_:)` and related methods.
struct RedactionConfig {
    /// Strip any phone numbers found in text.
    var stripPhoneNumbers: Bool = true
    /// Strip any email addresses found in text.
    var stripEmailAddresses: Bool = true
    /// Strip any physical street addresses detected by the regex heuristic.
    var stripStreetAddresses: Bool = true
    /// Strip location-indicating phrases (city names, coordinates, "near X").
    var stripLocation: Bool = true
    /// Strip any web URLs.
    var stripURLs: Bool = false
    /// Replace the user's real full name with their display name alias.
    var stripFullName: Bool = true
    /// Replace the authorId with a one-way hash (used for anonymous content).
    var maskUserId: Bool = false
    /// Strip EXIF metadata from images before upload (intent flag; actual stripping is CF-side).
    var stripExifFromImages: Bool = true

    /// Preset for public-post text sanitation.
    static var publicPost: RedactionConfig {
        RedactionConfig(
            stripPhoneNumbers: true,
            stripEmailAddresses: true,
            stripStreetAddresses: true,
            stripLocation: false,
            stripURLs: false,
            stripFullName: false,
            maskUserId: false,
            stripExifFromImages: true
        )
    }

    /// Preset for anonymous content — maximal identity removal.
    static var anonymous: RedactionConfig {
        RedactionConfig(
            stripPhoneNumbers: true,
            stripEmailAddresses: true,
            stripStreetAddresses: true,
            stripLocation: true,
            stripURLs: false,
            stripFullName: true,
            maskUserId: true,
            stripExifFromImages: true
        )
    }
}

// MARK: - AudienceType

/// The relationship category of a viewer relative to the content owner.
/// Used by `AmenPrivacyEngine.simulateAudience(for:viewerType:)`.
enum AudienceType: String, CaseIterable {
    case anonymous           // unauthenticated or sealed mirror
    case authenticatedStranger // signed in; no prior relationship
    case mutualFollow        // both parties follow each other
    case churchMember        // verified member of the same church
    case trustedContact      // in the owner's explicit trusted circle
    case selfViewer          // the content owner themselves

    var displayName: String {
        switch self {
        case .anonymous:             return "Anonymous Visitor"
        case .authenticatedStranger: return "Signed-In Stranger"
        case .mutualFollow:          return "Mutual Follow"
        case .churchMember:          return "Church Member"
        case .trustedContact:        return "Trusted Contact"
        case .selfViewer:            return "You"
        }
    }

    var systemImage: String {
        switch self {
        case .anonymous:             return "person.fill.questionmark"
        case .authenticatedStranger: return "person.badge.clock"
        case .mutualFollow:          return "person.2.fill"
        case .churchMember:          return "building.columns.fill"
        case .trustedContact:        return "person.badge.shield.checkmark"
        case .selfViewer:            return "person.fill"
        }
    }
}

// MARK: - AudienceSimulation

/// Describes what a viewer of a given `AudienceType` would be able to see/do,
/// given a particular `AmenPrivacyPreset`.
struct AudienceSimulation {
    let viewerType: AudienceType
    let preset: AmenPrivacyPreset
    let canSeePost: Bool
    let canSeeProfile: Bool
    let canSendDM: Bool
    /// The profile fields that are visible to this viewer.
    let visibleFields: [String]

    /// A short human-readable summary for display in `AmenAudienceSimulatorView`.
    var summary: String {
        var parts: [String] = []
        parts.append(canSeePost    ? "Can see posts"    : "Cannot see posts")
        parts.append(canSeeProfile ? "Can see profile"  : "Cannot see profile")
        parts.append(canSendDM     ? "Can send a DM"    : "Cannot send a DM")
        return parts.joined(separator: " · ")
    }
}
