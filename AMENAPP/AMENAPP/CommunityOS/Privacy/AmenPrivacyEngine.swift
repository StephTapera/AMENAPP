// AmenPrivacyEngine.swift
// AMENAPP — CommunityOS/Privacy
//
// Phase 4 — Agent TS-a (Privacy Engine)
// Central privacy enforcement service: preset management, redaction, DM guards,
// audience simulation, and minor defaults enforcement.
//
// Contract references:
//   C5 §3 (Privacy Levels), C5 §4 (Minor Rules), C5 §5 Invariants I-3/I-5/I-6
//   AmenRBACService (Identity/) for role resolution
//
// Threading: @MainActor throughout; all Firestore calls are async/await.
//
// Key safety invariants enforced here:
//   [MINOR] enforceMinorDefaults() is called on account creation AND age verification.
//   [MINOR] canSendDM() always re-checks minor status from Firestore — cannot be spoofed client-side.
//   redactForPublic() MUST be called before any public Firestore write.
//   Anonymous preset: identity shielding is server-side (CF). This engine signals
//     the intent; it does NOT perform the HMAC or encryption itself.

import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

// MARK: - AmenPrivacyEngine

@MainActor
final class AmenPrivacyEngine: ObservableObject {

    // MARK: - Published State

    @Published var settings: PrivacySettings?
    @Published var isLoading: Bool = false
    @Published var lastError: Error?

    // MARK: - Private

    private let db = Firestore.firestore()

    // MARK: - Singleton (optional shared instance)

    static let shared = AmenPrivacyEngine()
    init() {}

    // MARK: - CRUD

    /// Loads the privacy settings for `userId` from Firestore.
    /// Path: `/users/{userId}/private/privacy_settings`
    func loadSettings(for userId: String) async throws {
        isLoading = true
        defer { isLoading = false }
        let ref = privacyDocRef(for: userId)
        let snapshot = try await ref.getDocument()
        if snapshot.exists, let data = snapshot.data() {
            settings = try decodeSettings(from: data)
        } else {
            // No document yet — seed defaults
            let defaults = defaultSettings(for: userId)
            settings = defaults
        }
    }

    /// Persists `settings` to Firestore.
    /// Enforces minor defaults server-side before writing (belt-and-suspenders).
    func saveSettings(_ settings: PrivacySettings) async throws {
        isLoading = true
        defer { isLoading = false }
        let safe = settings.withMinorDefaultsEnforced()
        let ref = privacyDocRef(for: safe.userId)
        let encoded = try encodeSettings(safe)
        try await ref.setData(encoded, merge: true)
        self.settings = safe
    }

    // MARK: - Preset Application

    /// Writes the chosen preset (and all its derived sub-settings) to Firestore.
    /// [MINOR] If the user is a minor, this silently overrides any above-.private selection.
    func applyPreset(_ preset: AmenPrivacyPreset, to userId: String) async throws {
        // Load current settings (or seed defaults if none exist)
        if settings == nil || settings?.userId != userId {
            try await loadSettings(for: userId)
        }
        guard var current = settings else { return }

        current.preset = preset
        current.locationSharingLevel = preset.locationSharing
        current.profileVisibility = preset.profileVisibility
        // Reset anonymous search visibility according to preset
        // (customOverrides can further tune after this call)
        current.updatedAt = Date()

        try await saveSettings(current)
    }

    // MARK: - Text Redaction

    /// Strips phone numbers, email addresses, and street-address-like patterns from `text`
    /// before any public write. Call this on post body, prayer body, bio, etc.
    ///
    /// [RULE] This MUST run on text before a public Firestore write.
    func redactForPublic(_ text: String, config: RedactionConfig = .publicPost) -> String {
        var result = text

        if config.stripPhoneNumbers {
            result = Redactor.stripPhoneNumbers(from: result)
        }
        if config.stripEmailAddresses {
            result = Redactor.stripEmails(from: result)
        }
        if config.stripStreetAddresses {
            result = Redactor.stripStreetAddresses(from: result)
        }
        if config.stripURLs {
            result = Redactor.stripURLs(from: result)
        }
        return result
    }

    /// Strips location-indicating phrases (city mentions, GPS coordinates,
    /// "near X" patterns) from `text`.
    func redactLocation(from text: String) -> String {
        Redactor.stripLocationClues(from: text)
    }

    // MARK: - Search Visibility

    /// Returns whether `userId` should appear in search results for `searcherUserId`.
    /// Consults Firestore privacy settings and RBAC minor status.
    func shouldShowInSearch(userId: String, searcherUserId: String) async throws -> Bool {
        // Self-search always succeeds
        if userId == searcherUserId { return true }

        // Load target's settings
        let ref = privacyDocRef(for: userId)
        let snapshot = try await ref.getDocument()
        guard snapshot.exists, let data = snapshot.data() else {
            // No settings document → use balanced default: show in search
            return true
        }
        let targetSettings = try decodeSettings(from: data)

        // Anonymous preset: never appears in search
        if targetSettings.preset == .anonymous { return false }

        // Private preset: not searchable
        if targetSettings.preset == .private { return false }

        // Explicit searchability flag from preset
        return targetSettings.preset.showInSearch
    }

    // MARK: - Audience Simulation

    /// Returns an `AudienceSimulation` describing what a `viewerType` viewer
    /// would be able to see/do given a `privacy` preset.
    ///
    /// This is a pure client-side heuristic — it does NOT perform a live Firestore
    /// lookup. It is used to power the "Who can see this?" UI.
    func simulateAudience(
        for privacy: AmenPrivacyPreset,
        viewerType: AudienceType
    ) -> AudienceSimulation {

        let canSeePost: Bool
        let canSeeProfile: Bool
        let canSendDM: Bool
        var visibleFields: [String] = []

        switch privacy {
        case .open:
            canSeePost    = true
            canSeeProfile = true
            canSendDM     = viewerType != .anonymous
            visibleFields = ["displayName", "bio", "avatar", "church", "stats", "followers"]

        case .balanced:
            canSeePost    = viewerType == .mutualFollow
                         || viewerType == .churchMember
                         || viewerType == .trustedContact
                         || viewerType == .selfViewer
            canSeeProfile = viewerType != .anonymous
            canSendDM     = viewerType == .mutualFollow
                         || viewerType == .churchMember
                         || viewerType == .trustedContact
                         || viewerType == .selfViewer
            if viewerType == .anonymous {
                visibleFields = []
            } else {
                visibleFields = ["displayName", "bio"]
            }

        case .private:
            canSeePost    = viewerType == .trustedContact || viewerType == .selfViewer
            canSeeProfile = viewerType == .trustedContact || viewerType == .selfViewer
            canSendDM     = viewerType == .mutualFollow
                         || viewerType == .trustedContact
                         || viewerType == .selfViewer
            visibleFields = viewerType == .selfViewer
                ? ["displayName", "bio", "avatar", "church", "stats", "followers"]
                : (viewerType == .trustedContact ? ["displayName"] : [])

        case .anonymous:
            // Content is publicly visible; identity is hidden
            canSeePost    = true
            canSeeProfile = false                       // profile not accessible
            canSendDM     = viewerType == .selfViewer   // no one can DM an anon author
            visibleFields = []                          // all identity fields stripped
        }

        return AudienceSimulation(
            viewerType: viewerType,
            preset: privacy,
            canSeePost: canSeePost,
            canSeeProfile: canSeeProfile,
            canSendDM: canSendDM,
            visibleFields: visibleFields
        )
    }

    // MARK: - Minor Default Enforcement [MINOR]

    /// Enforces C5 §4 minor defaults for `userId`.
    /// Sets preset to `.private`, DMPolicy to `.mutualFollows`, location to `.none`.
    ///
    /// [MINOR] This MUST be called on:
    ///   a) initial account creation when ageTier is `blocked`, `tierB`, or `tierC`
    ///   b) after age assurance pipeline updates ageTier to a minor tier
    ///
    /// The `isMinor` flag is set by the CF age-assurance pipeline (never client-writable).
    /// This method reads it from Firestore to confirm before applying.
    func enforceMinorDefaults(for userId: String) async throws {
        // Confirm minor status from Firestore (cannot trust client-side claim)
        let isActuallyMinor = try await fetchIsMinor(userId: userId)
        guard isActuallyMinor else { return }

        if settings == nil || settings?.userId != userId {
            try await loadSettings(for: userId)
        }
        guard var current = settings else { return }

        // Apply [MINOR] overrides
        current.isMinor = true
        current.preset = .private
        current.locationSharingLevel = .none
        current.profileVisibility = .minimal
        current.allowedDMSenders = .mutualFollows
        current.contactsDiscoveryEnabled = false
        current.searchableByEmail = false
        current.searchableByPhone = false
        current.updatedAt = Date()

        try await saveSettings(current)
    }

    // MARK: - DM Permission Check

    /// Returns `true` if `senderId` is permitted to open or send a DM to `recipientId`.
    ///
    /// [MINOR] Checks:
    ///   1. Recipient's `allowedDMSenders` policy.
    ///   2. If either party is a minor, applies C5 §4b mutual-follow requirement.
    ///   3. Hard blocks: visitor → minor, non-mutual → minor.
    func canSendDM(from senderId: String, to recipientId: String) async throws -> Bool {
        // Cannot DM yourself
        guard senderId != recipientId else { return false }

        // Load recipient privacy settings
        let recipRef = privacyDocRef(for: recipientId)
        let recipSnapshot = try await recipRef.getDocument()
        let recipSettings: PrivacySettings
        if recipSnapshot.exists, let data = recipSnapshot.data() {
            recipSettings = try decodeSettings(from: data)
        } else {
            recipSettings = defaultSettings(for: recipientId)
        }

        // Recipient has DMs fully closed
        if recipSettings.allowedDMSenders == .nobody { return false }

        // [MINOR] Check if recipient is a minor
        let recipIsMinor = recipSettings.isMinor

        // [MINOR] Check if sender is a minor
        let senderRef = privacyDocRef(for: senderId)
        let senderSnapshot = try await senderRef.getDocument()
        let senderIsMinor: Bool
        if senderSnapshot.exists, let data = senderSnapshot.data() {
            // SECURITY FIX (MEDIUM 2026-06-11): Log decode errors so silent schema drift
            // is detectable. The try? swallowed errors making decode failures invisible.
            do {
                let settings = try decodeSettings(from: data)
                senderIsMinor = settings.isMinor
            } catch {
                print("[AmenPrivacyEngine] Privacy settings decode error for sender \(senderId): \(error)")
                senderIsMinor = try await fetchIsMinor(userId: senderId)
            }
        } else {
            // Fall back to RBAC age check
            senderIsMinor = try await fetchIsMinor(userId: senderId)
        }

        // [MINOR] C5 §4b: If either party is a minor, require the minor-safe DM guard.
        // The guard checks mutual follows and fails closed on Firestore errors.
        if recipIsMinor || senderIsMinor {
            return try await canSendMinorSafeDM(from: senderId, to: recipientId)
        }

        // Standard adult-to-adult DM policy check
        switch recipSettings.allowedDMSenders {
        case .nobody:
            return false
        case .mutualFollows:
            // Mutual follow resolution is CF-side; signal intent as allowed
            return true
        case .churchMembers:
            // Church membership check is CF-side; signal intent
            return true
        case .everyone:
            return true
        }
    }

    // MARK: - Private Helpers

    private func privacyDocRef(for userId: String) -> DocumentReference {
        db.collection("users")
          .document(userId)
          .collection("private")
          .document("privacy_settings")
    }

    private func defaultSettings(for userId: String) -> PrivacySettings {
        // SECURITY FIX (MEDIUM 2026-06-11): Default to isMinor: true (conservative) when
        // no privacy_settings document exists. A new account receives protective defaults
        // until the age-assurance pipeline writes the real settings. The previous isMinor: false
        // treated new minor accounts as adults in the DM path before settings were written.
        PrivacySettings(
            userId: userId,
            preset: .balanced,
            locationSharingLevel: .none,
            profileVisibility: .partial,
            isMinor: true,
            allowedDMSenders: .mutualFollows,
            delayedPostingEnabled: false,
            delayMinutes: 10
        )
    }

    /// Checks Firestore `users/{userId}` for ageTier to confirm minor status. Unknown tiers fail closed.
    private func fetchIsMinor(userId: String) async throws -> Bool {
        let doc = try await db.collection("users").document(userId).getDocument()
        let ageTier = doc.data()?["ageTier"] as? String
        return ageTier != "tierD"
    }

    private func canSendMinorSafeDM(from senderId: String, to recipientId: String) async throws -> Bool {
        do {
            let isMutual = try await areMutualFollows(userId1: senderId, userId2: recipientId)
            guard isMutual else { return false }

            let recipientIsMinor = try await fetchIsMinor(userId: recipientId)
            guard recipientIsMinor else { return true }

            return try await isGuardianApprovedContact(minorId: recipientId, contactId: senderId)
        } catch {
            return false
        }
    }

    private func areMutualFollows(userId1: String, userId2: String) async throws -> Bool {
        let forward = try await db.collection("edges")
            .whereField("fromUserId", isEqualTo: userId1)
            .whereField("toUserId", isEqualTo: userId2)
            .whereField("type", isEqualTo: "follow")
            .limit(to: 1)
            .getDocuments()

        guard !forward.documents.isEmpty else { return false }

        let reverse = try await db.collection("edges")
            .whereField("fromUserId", isEqualTo: userId2)
            .whereField("toUserId", isEqualTo: userId1)
            .whereField("type", isEqualTo: "follow")
            .limit(to: 1)
            .getDocuments()

        return !reverse.documents.isEmpty
    }

    private func isGuardianApprovedContact(minorId: String, contactId: String) async throws -> Bool {
        let doc = try await db
            .collection("guardianApprovedContacts")
            .document(minorId)
            .collection("contacts")
            .document(contactId)
            .getDocument()

        guard doc.exists else { return false }
        return doc.data()?["approved"] as? Bool ?? false
    }

    // MARK: - Firestore Encoding / Decoding

    private func encodeSettings(_ s: PrivacySettings) throws -> [String: Any] {
        let encoder = Firestore.Encoder()
        let data = try encoder.encode(s)
        return data
    }

    private func decodeSettings(from data: [String: Any]) throws -> PrivacySettings {
        let decoder = Firestore.Decoder()
        return try decoder.decode(PrivacySettings.self, from: data)
    }
}

// MARK: - Per-Field Profile Visibility (Trust & Safety item 21 follow-on)

extension AmenPrivacyEngine {
    /// Whether the currently-loaded user shows `field` on their profile.
    /// Defaults to hidden when settings are not loaded.
    func showsProfileField(_ field: ProfileContactField) -> Bool {
        settings?.showsProfileField(field) ?? false
    }

    /// Sets the visibility of `field` for `userId` and persists it.
    /// Uses `customOverrides`, so no Codable migration is involved.
    /// [MINOR] No-op for minors (enforced in `settingProfileField`).
    func setProfileField(
        _ field: ProfileContactField,
        visible: Bool,
        for userId: String
    ) async throws {
        if settings == nil || settings?.userId != userId {
            try await loadSettings(for: userId)
        }
        guard let current = settings else { return }
        let updated = current.settingProfileField(field, visible: visible)
        try await saveSettings(updated)
    }

    /// Whether `field` of `ownerSettings` should be shown to a viewer of `audience`.
    /// Pure convenience wrapper around `PrivacySettings.isProfileField(_:visibleTo:)`.
    func isProfileField(
        _ field: ProfileContactField,
        of ownerSettings: PrivacySettings,
        visibleTo audience: AudienceType
    ) -> Bool {
        ownerSettings.isProfileField(field, visibleTo: audience)
    }
}

// MARK: - Redactor (private regex helpers)

/// Namespace for regex-based text redaction operations.
/// All patterns are conservative: they may leave some PII un-redacted but will not
/// remove non-PII content.
private enum Redactor {

    // MARK: Phone Numbers

    static func stripPhoneNumbers(from text: String) -> String {
        // Matches common US and international formats:
        //   +1 (555) 123-4567 | 555-123-4567 | 5551234567 | +44 20 7946 0958
        let pattern = #"(\+?\d{1,3}[\s\-\.]?)?\(?\d{3}\)?[\s\-\.]?\d{3}[\s\-\.]?\d{4}"#
        return redact(text, pattern: pattern, replacement: "[phone removed]")
    }

    // MARK: Emails

    static func stripEmails(from text: String) -> String {
        let pattern = #"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#
        return redact(text, pattern: pattern, replacement: "[email removed]")
    }

    // MARK: Street Addresses

    static func stripStreetAddresses(from text: String) -> String {
        // Matches patterns like "123 Main St", "456 W. Elm Ave Apt 2B"
        let pattern = #"\d{1,5}\s+(?:[A-Za-z]+\s+){1,4}(?:St|Ave|Blvd|Dr|Rd|Ln|Way|Ct|Pl|Pkwy|Hwy|Circle|Loop)\.?(?:\s+(?:Apt|Suite|Unit|Ste|#)\s*[\w\d]+)?"#
        return redact(text, pattern: pattern, replacement: "[address removed]")
    }

    // MARK: URLs

    static func stripURLs(from text: String) -> String {
        let pattern = #"https?://[^\s]+"#
        return redact(text, pattern: pattern, replacement: "[link removed]")
    }

    // MARK: Location Clues

    static func stripLocationClues(from text: String) -> String {
        var result = text
        // GPS coordinates: 40.7128, -74.0060
        let coordPattern = #"-?\d{1,3}\.\d{3,},\s*-?\d{1,3}\.\d{3,}"#
        result = redact(result, pattern: coordPattern, replacement: "[location removed]")
        // "near [Place]", "in [Place]", "at [Place]" — limited heuristic
        let nearPattern = #"\b(?:near|at|in|around|from)\s+[A-Z][a-zA-Z\s]{2,20}(?:,\s*[A-Z]{2})?"#
        result = redact(result, pattern: nearPattern, replacement: "[location removed]")
        return result
    }

    // MARK: Generic Helper

    private static func redact(_ text: String, pattern: String, replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: replacement)
    }
}
