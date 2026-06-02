// ONEPrivacyModels.swift
// ONE — Privacy Contract (first-class object, shown before every send)
// P0-F | FROZEN contracts. See CONTRACTS.md §2.

import Foundation

// MARK: - ONEPrivacyContract

struct ONEPrivacyContract: Codable, Sendable {
    let audience: ONEAudienceScope
    let lifetime: ONELifetimePolicy
    var permissions: ONEMomentPermissions
    var safety: ONESafetySettings
    var metricsPrivate: Bool    // default true; no public likes/views
    var reshareAllowed: Bool    // default false for DMs/snaps
}

extension ONEPrivacyContract {
    static var privateDefault: ONEPrivacyContract {
        ONEPrivacyContract(
            audience: .closeFriends,
            lifetime: .decayUnlessRemembered(days: 30),
            permissions: .init(),
            safety: .init(),
            metricsPrivate: true,
            reshareAllowed: false
        )
    }

    static var dmDefault: ONEPrivacyContract {
        ONEPrivacyContract(
            audience: .selfOnly,
            lifetime: .days(7),
            permissions: ONEMomentPermissions(
                forwardAllowed: false, saveAllowed: false, quoteAllowed: false,
                reactAllowed: true, translateAllowed: true, summarizeAllowed: false,
                aiTrainingAllowed: false
            ),
            safety: .init(),
            metricsPrivate: true,
            reshareAllowed: false
        )
    }
}

// MARK: - ONEAudienceScope

struct ONEAudienceScope: Codable, Sendable, Equatable {
    enum Kind: String, Codable, Sendable {
        case selfOnly, closeFriends, witnesses, world, custom, group
    }
    let kind: Kind
    var customUIDs: [String]?   // populated when kind == .custom
    var groupID: String?         // populated when kind == .group

    static let selfOnly      = ONEAudienceScope(kind: .selfOnly)
    static let closeFriends  = ONEAudienceScope(kind: .closeFriends)
    static let witnesses     = ONEAudienceScope(kind: .witnesses)
    static let world         = ONEAudienceScope(kind: .world)

    static func custom(uids: [String]) -> ONEAudienceScope {
        ONEAudienceScope(kind: .custom, customUIDs: uids)
    }
    static func group(_ id: String) -> ONEAudienceScope {
        ONEAudienceScope(kind: .group, groupID: id)
    }

    var displayLabel: String {
        switch kind {
        case .selfOnly:     return "Only Me"
        case .closeFriends: return "Close Friends"
        case .witnesses:    return "Witnesses"
        case .world:        return "Everyone"
        case .custom:       return "\(customUIDs?.count ?? 0) people"
        case .group:        return "Group"
        }
    }
}

// MARK: - ONELifetimePolicy

struct ONELifetimePolicy: Codable, Sendable, Equatable {
    enum Kind: String, Codable, Sendable {
        case afterView, hours, days, permanent, decayUnlessRemembered
    }
    let kind: Kind
    var hours: Int?
    var days: Int?

    static let afterView  = ONELifetimePolicy(kind: .afterView)
    static let permanent  = ONELifetimePolicy(kind: .permanent)

    static func hours(_ n: Int) -> ONELifetimePolicy {
        ONELifetimePolicy(kind: .hours, hours: n)
    }
    static func days(_ n: Int) -> ONELifetimePolicy {
        ONELifetimePolicy(kind: .days, days: n)
    }
    static func decayUnlessRemembered(days n: Int) -> ONELifetimePolicy {
        ONELifetimePolicy(kind: .decayUnlessRemembered, days: n)
    }

    var displayLabel: String {
        switch kind {
        case .afterView:             return "After Viewed"
        case .hours:                 return "\(hours ?? 24)h"
        case .days:                  return "\(days ?? 7)d"
        case .permanent:             return "Permanent"
        case .decayUnlessRemembered: return "Fades in \(days ?? 30)d"
        }
    }

    /// Computes the absolute expiry Date from a creation Date.
    func expiryDate(from creation: Date) -> Date? {
        switch kind {
        case .afterView:             return creation.addingTimeInterval(60 * 60)  // 1h grace
        case .hours(let h):          return creation.addingTimeInterval(Double(h) * 3_600)
        case .days(let d):           return creation.addingTimeInterval(Double(d) * 86_400)
        case .permanent:             return nil
        case .decayUnlessRemembered: return creation.addingTimeInterval(Double(days ?? 30) * 86_400)
        }
    }
}

// MARK: - ONEMomentPermissions

struct ONEMomentPermissions: Codable, Sendable {
    var forwardAllowed:    Bool = false
    var saveAllowed:       Bool = false
    var quoteAllowed:      Bool = false
    var reactAllowed:      Bool = true
    var translateAllowed:  Bool = true   // on-device translation OK
    var summarizeAllowed:  Bool = false  // requires explicit opt-in
    var aiTrainingAllowed: Bool = false  // always off by default
}

// MARK: - ONESafetySettings

struct ONESafetySettings: Codable, Sendable {
    var locationStripped:       Bool                  = true
    var faceBlurEnabled:        Bool                  = false
    var childDetectionEnabled:  Bool                  = true  // always on for public content
    var screenshotBehavior:     ONEScreenshotBehavior = .notify
}

// MARK: - ONEScreenshotBehavior

enum ONEScreenshotBehavior: String, Codable, Sendable {
    case notify      // detect + notify sender (best effort; iOS limitation)
    case bestEffort  // attempt obscure; labeled as best-effort in UX
    case none        // user accepts no protection
    // "block" intentionally absent — iOS cannot block screenshots without Apple entitlement
}

// MARK: - ONEConsentDNA

struct ONEConsentDNA: Codable, Sendable {
    let momentID: String
    let authorUID: String
    var permissions: ONEMomentPermissions
    let issuedAt: Date
    let consentVersion: String   // bump on schema change; current = "1.0"
}
