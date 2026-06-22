// RelationshipTierService.swift
// AMENAPP — Trust OS
//
// Provides relationship-tier defaults and prayer-privacy helpers.
// Pure logic — no UI, no Firestore, no external dependencies.

import Foundation

@MainActor
final class RelationshipTierService: ObservableObject {
    static let shared = RelationshipTierService()

    private init() {}

    // MARK: - Default Tier

    /// Returns the least-surprise RelationshipTier for a given ShareContext.
    /// Single source of truth lives in ShareContext.defaultTier (TrustOSContracts).
    func defaultTier(for context: ShareContext) -> RelationshipTier {
        context.defaultTier
    }

    // MARK: - Prayer Privacy

    /// The safe default for first-time prayer request visibility.
    func prayerPrivacyDefault() -> PrayerPrivacyScope.Level {
        .churchOnly
    }

    /// Human-readable description of a PrayerPrivacyScope.Level for display in UI.
    func prayerPrivacySafetyContentContext(for level: PrayerPrivacyScope.Level) -> String {
        switch level {
        case .anonymous:
            return "Your name will not appear with this prayer request."
        case .churchOnly:
            return "Only church members can see this prayer request."
        case .leaderOnly:
            return "Only your church leaders can see this prayer request."
        case .trustedCircle:
            return "Only people in your trusted circle can see this prayer request."
        case .public:
            return "Everyone on AMEN, including people outside your church, can see this prayer request."
        }
    }

    // MARK: - Audience Width Guard

    /// Returns true when the user's selected tier is broader than the context's safe default.
    /// Used by ContextBeforeShareService to decide whether to show a consent prompt.
    func isBroaderthanExpected(selected: RelationshipTier, context: ShareContext) -> Bool {
        selected.audienceBreadth > context.defaultTier.audienceBreadth
    }
}
