//
//  ProfileIdentityService.swift
//  AMENAPP
//
//  Reads and writes UserProfileIdentity to users/{uid} in Firestore.
//  Uses "identity_" field prefix for backward-compatible coexistence with
//  existing profile fields.
//
//  Call startListening() on sign-in, stopListening() on sign-out.
//  Use ProfileIdentityService.shared from any view via @ObservedObject.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class ProfileIdentityService: ObservableObject {
    static let shared = ProfileIdentityService()

    @Published private(set) var identity = UserProfileIdentity()
    @Published private(set) var isLoading = false

    private lazy var db = Firestore.firestore()
    private var listenerHandle: ListenerRegistration?

    private init() {}

    // MARK: - Lifecycle

    func startListening() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        guard listenerHandle == nil else { return }
        dlog("[ProfileIdentity] startListening uid=\(uid.prefix(8))…")

        listenerHandle = db.collection("users").document(uid)
            .addSnapshotListener { [weak self] snap, error in
                guard let self else { return }
                if let error {
                    dlog("[ProfileIdentity] listener error: \(error.localizedDescription)")
                    return
                }
                guard let data = snap?.data() else { return }
                Task { @MainActor in
                    self.identity = Self.decode(from: data)
                }
            }
    }

    func stopListening() {
        listenerHandle?.remove()
        listenerHandle = nil
        dlog("[ProfileIdentity] stopListening")
    }

    /// One-shot fetch — use for initial load before the real-time listener fires.
    func load() async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isLoading = true
        defer { isLoading = false }
        let snap = try await db.collection("users").document(uid).getDocument()
        guard let data = snap.data() else { return }
        identity = Self.decode(from: data)
        dlog("[ProfileIdentity] loaded persona=\(identity.persona?.rawValue ?? "nil")")
    }

    // MARK: - Save

    func save(_ identity: UserProfileIdentity) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let payload = Self.encode(identity)
        try await db.collection("users").document(uid).updateData(payload)
        self.identity = identity
        dlog("[ProfileIdentity] saved persona=\(identity.persona?.rawValue ?? "nil") openTo=\(identity.openToSignalIds)")
    }

    // MARK: - Convenience Updaters

    func setPersona(_ persona: UserPersona?) async throws {
        var updated = identity
        updated.persona = persona
        try await save(updated)
    }

    func setFaithStage(_ stage: FaithJourneyStage?) async throws {
        var updated = identity
        updated.faithJourneyStage = stage
        try await save(updated)
    }

    func setDenomination(_ denom: ProfileDenomination?) async throws {
        var updated = identity
        updated.denomination = denom
        try await save(updated)
    }

    func setCityRegion(_ city: String?) async throws {
        var updated = identity
        updated.cityRegion = city?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        try await save(updated)
    }

    func setOpenToSignals(_ ids: [String]) async throws {
        var updated = identity
        updated.openToSignalIds = ids
        try await save(updated)
    }

    func addBurden(_ burden: ProfileBurden) async throws {
        var updated = identity
        // Cap at 5 burdens
        guard updated.burdens.count < 5 else { return }
        updated.burdens.append(burden)
        try await save(updated)
    }

    func removeBurden(id: String) async throws {
        var updated = identity
        updated.burdens.removeAll { $0.id == id }
        try await save(updated)
    }

    func setPinnedCards(_ cards: [PinnedProfileCard]) async throws {
        var updated = identity
        updated.pinnedCards = cards
        try await save(updated)
    }

    func setAskMeAbout(_ prompts: [AskMeAboutPrompt]) async throws {
        var updated = identity
        // Cap at 5 prompts
        updated.askMeAbout = Array(prompts.prefix(5))
        try await save(updated)
    }

    func updatePrivacy(_ privacy: ProfilePrivacySettings) async throws {
        var updated = identity
        updated.privacy = privacy
        try await save(updated)
    }

    // MARK: - Firestore Encoding

    static func encode(_ identity: UserProfileIdentity) -> [String: Any] {
        var d: [String: Any] = [:]
        d["identity_persona"]           = identity.persona?.rawValue           ?? FieldValue.delete()
        d["identity_cityRegion"]        = identity.cityRegion                  ?? FieldValue.delete()
        d["identity_faithJourneyStage"] = identity.faithJourneyStage?.rawValue ?? FieldValue.delete()
        d["identity_denomination"]      = identity.denomination?.rawValue      ?? FieldValue.delete()
        d["identity_openToSignalIds"]   = identity.openToSignalIds
        d["identity_burdens"] = identity.burdens.map { b -> [String: Any] in
            ["id": b.id, "text": b.text, "isPublic": b.isPublic]
        }
        d["identity_pinnedCards"] = identity.pinnedCards.map { c -> [String: Any] in
            var m: [String: Any] = [
                "id": c.id, "kind": c.kind.rawValue,
                "content": c.content, "isVisible": c.isVisible, "sortOrder": c.sortOrder
            ]
            if let ref = c.reference { m["reference"] = ref }
            return m
        }
        d["identity_askMeAbout"] = identity.askMeAbout.map { a -> [String: Any] in
            ["id": a.id, "topic": a.topic]
        }
        let priv = identity.privacy
        d["identity_privacy"] = [
            "bio":         priv.bioVisibility.rawValue,
            "website":     priv.websiteVisibility.rawValue,
            "socialLinks": priv.socialLinksVisibility.rawValue,
            "topics":      priv.topicsVisibility.rawValue,
            "church":      priv.churchVisibility.rawValue,
            "interests":   priv.interestsVisibility.rawValue,
            "location":    priv.locationVisibility.rawValue,
            "denom":       priv.denomVisibility.rawValue,
            "faithStage":  priv.faithStageVisibility.rawValue,
            "openTo":      priv.openToVisibility.rawValue,
            "burdens":     priv.burdensVisibility.rawValue,
        ]
        d["identity_updatedAt"] = FieldValue.serverTimestamp()
        return d
    }

    // MARK: - Firestore Decoding

    static func decode(from data: [String: Any]) -> UserProfileIdentity {
        var id = UserProfileIdentity()

        id.persona = (data["identity_persona"] as? String)
            .flatMap { UserPersona(rawValue: $0) }
        id.cityRegion = data["identity_cityRegion"] as? String
        id.faithJourneyStage = (data["identity_faithJourneyStage"] as? String)
            .flatMap { FaithJourneyStage(rawValue: $0) }
        id.denomination = (data["identity_denomination"] as? String)
            .flatMap { ProfileDenomination(rawValue: $0) }
        id.openToSignalIds = data["identity_openToSignalIds"] as? [String] ?? []

        if let burdens = data["identity_burdens"] as? [[String: Any]] {
            id.burdens = burdens.compactMap { d -> ProfileBurden? in
                guard let text = d["text"] as? String else { return nil }
                return ProfileBurden(
                    id: d["id"] as? String ?? UUID().uuidString,
                    text: text,
                    isPublic: d["isPublic"] as? Bool ?? true
                )
            }
        }

        if let cards = data["identity_pinnedCards"] as? [[String: Any]] {
            id.pinnedCards = cards.compactMap { d -> PinnedProfileCard? in
                guard let kindRaw = d["kind"] as? String,
                      let kind    = PinnedCardKind(rawValue: kindRaw),
                      let content = d["content"] as? String else { return nil }
                return PinnedProfileCard(
                    id: d["id"] as? String ?? UUID().uuidString,
                    kind: kind, content: content,
                    reference:  d["reference"]  as? String,
                    isVisible:  d["isVisible"]  as? Bool ?? true,
                    sortOrder:  d["sortOrder"]  as? Int  ?? 0
                )
            }
        }

        if let asks = data["identity_askMeAbout"] as? [[String: Any]] {
            id.askMeAbout = asks.compactMap { d -> AskMeAboutPrompt? in
                guard let topic = d["topic"] as? String else { return nil }
                return AskMeAboutPrompt(
                    id: d["id"] as? String ?? UUID().uuidString,
                    topic: topic
                )
            }
        }

        if let priv = data["identity_privacy"] as? [String: String] {
            func v(_ key: String, default def: VisibilityLevel) -> VisibilityLevel {
                priv[key].flatMap { VisibilityLevel(rawValue: $0) } ?? def
            }
            id.privacy.bioVisibility         = v("bio",         default: .publicVisible)
            id.privacy.websiteVisibility      = v("website",     default: .publicVisible)
            id.privacy.socialLinksVisibility  = v("socialLinks", default: .publicVisible)
            id.privacy.topicsVisibility       = v("topics",      default: .publicVisible)
            id.privacy.churchVisibility       = v("church",      default: .followersOnly)
            id.privacy.interestsVisibility    = v("interests",   default: .publicVisible)
            id.privacy.locationVisibility     = v("location",    default: .followersOnly)
            id.privacy.denomVisibility        = v("denom",       default: .followersOnly)
            id.privacy.faithStageVisibility   = v("faithStage",  default: .followersOnly)
            id.privacy.openToVisibility       = v("openTo",      default: .followersOnly)
            id.privacy.burdensVisibility      = v("burdens",     default: .followersOnly)
        }

        return id
    }
}

// MARK: - String Helper

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
