// ONEStickyConsentService.swift
// ONE — Sticky consent: ConsentDNA travels with moments through relay chains.
// P4-E | Client-side validation. Server-side reject added in P5 CF hardening.
//
// Design rule: consent cannot be loosened during relay.
// A forwardAllowed=false moment cannot be relayed even if the relayer would grant it.
// The original author's consent is sovereign and travels with every hop.

import Foundation

// MARK: - ONEConsentAction

enum ONEConsentAction: Sendable {
    case forward
    case save
    case quote
    case react
    case translate
    case summarize
    case aiTrain
}

// MARK: - ONEConsentError

/// Client-side consent failures. Surfaced fail-closed at action sites (e.g. relay)
/// so a permission-denied action never reaches the network.
enum ONEConsentError: LocalizedError, Equatable {
    case forwardNotPermitted
    case momentNotFound

    var errorDescription: String? {
        switch self {
        case .forwardNotPermitted:
            return "The author disabled forwarding for this moment."
        case .momentNotFound:
            return "This moment is no longer available."
        }
    }
}

// MARK: - ONEStickyConsentService

actor ONEStickyConsentService {

    static let shared = ONEStickyConsentService()
    private init() {}

    // MARK: - Validation

    /// Whether the action is permitted by the moment's ConsentDNA.
    func isPermitted(_ action: ONEConsentAction, for moment: ONEMoment) -> Bool {
        isPermitted(action, in: moment.consentDNA.permissions)
    }

    /// Pure, synchronous permission check on a permission set. `nonisolated` so UI
    /// layers (which only carry `ONEMomentPermissions`, not a full `ONEMoment`) can
    /// gate controls without awaiting the actor. Single source of truth for consent.
    nonisolated func isPermitted(_ action: ONEConsentAction, in permissions: ONEMomentPermissions) -> Bool {
        switch action {
        case .forward:   return permissions.forwardAllowed
        case .save:      return permissions.saveAllowed
        case .quote:     return permissions.quoteAllowed
        case .react:     return permissions.reactAllowed
        case .translate: return permissions.translateAllowed
        case .summarize: return permissions.summarizeAllowed
        case .aiTrain:   return permissions.aiTrainingAllowed
        }
    }

    /// Returns all actions denied by the moment's ConsentDNA.
    /// Used to configure UI at ingest (hide or disable restricted actions).
    func deniedActions(for moment: ONEMoment) -> [ONEConsentAction] {
        let p = moment.consentDNA.permissions
        var denied: [ONEConsentAction] = []
        if !p.forwardAllowed    { denied.append(.forward) }
        if !p.saveAllowed       { denied.append(.save) }
        if !p.quoteAllowed      { denied.append(.quote) }
        if !p.summarizeAllowed  { denied.append(.summarize) }
        if !p.aiTrainingAllowed { denied.append(.aiTrain) }
        return denied
    }

    // MARK: - Relay attachment

    /// Returns the merged ConsentDNA for a relay hop, taking the stricter of the two.
    /// ONEMoment.consentDNA is `let`, so callers must construct a new ONEMoment.
    /// Call before `one_relayMoment` — server also validates on ingest (P5).
    func mergedConsentDNA(from source: ONEMoment, relayContext relay: ONEMoment) -> ONEConsentDNA {
        let s = source.consentDNA.permissions
        let r = relay.consentDNA.permissions
        return ONEConsentDNA(
            momentID: relay.consentDNA.momentID,
            authorUID: relay.consentDNA.authorUID,
            permissions: ONEMomentPermissions(
                forwardAllowed:    s.forwardAllowed    && r.forwardAllowed,
                saveAllowed:       s.saveAllowed       && r.saveAllowed,
                quoteAllowed:      s.quoteAllowed      && r.quoteAllowed,
                reactAllowed:      s.reactAllowed      && r.reactAllowed,
                translateAllowed:  s.translateAllowed  && r.translateAllowed,
                summarizeAllowed:  s.summarizeAllowed  && r.summarizeAllowed,
                aiTrainingAllowed: s.aiTrainingAllowed && r.aiTrainingAllowed
            ),
            issuedAt: relay.consentDNA.issuedAt,
            consentVersion: relay.consentDNA.consentVersion
        )
    }

    // MARK: - Consent summary

    /// Human-readable summary of active restrictions, for display in UI.
    func restrictionSummary(for moment: ONEMoment) -> String {
        let denied = deniedActions(for: moment)
        if denied.isEmpty { return "No restrictions" }
        let labels = denied.map { action -> String in
            switch action {
            case .forward:  return "No forward"
            case .save:     return "No save"
            case .quote:    return "No quote"
            case .summarize: return "No AI summary"
            case .aiTrain:  return "No AI training"
            default:        return ""
            }
        }.filter { !$0.isEmpty }
        return labels.joined(separator: " · ")
    }
}
