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

// MARK: - ONEStickyConsentService

actor ONEStickyConsentService {

    static let shared = ONEStickyConsentService()
    private init() {}

    // MARK: - Validation

    /// Whether the action is permitted by the moment's ConsentDNA.
    func isPermitted(_ action: ONEConsentAction, for moment: ONEMoment) -> Bool {
        let p = moment.consentDNA.permissions
        switch action {
        case .forward:   return p.forwardAllowed
        case .save:      return p.saveAllowed
        case .quote:     return p.quoteAllowed
        case .react:     return p.reactAllowed
        case .translate: return p.translateAllowed
        case .summarize: return p.summarizeAllowed
        case .aiTrain:   return p.aiTrainingAllowed
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

    /// Attaches the source's ConsentDNA to a relay copy, taking the stricter of the two.
    /// Call before `one_relayMoment` — server will also validate on ingest (P5).
    func attachConsentDNA(from source: ONEMoment, onto relay: inout ONEMoment) {
        let s = source.consentDNA.permissions
        let r = relay.consentDNA.permissions
        relay.consentDNA.permissions = ONEMomentPermissions(
            forwardAllowed:    s.forwardAllowed    && r.forwardAllowed,
            saveAllowed:       s.saveAllowed       && r.saveAllowed,
            quoteAllowed:      s.quoteAllowed      && r.quoteAllowed,
            reactAllowed:      s.reactAllowed      && r.reactAllowed,
            translateAllowed:  s.translateAllowed  && r.translateAllowed,
            summarizeAllowed:  s.summarizeAllowed  && r.summarizeAllowed,
            aiTrainingAllowed: s.aiTrainingAllowed && r.aiTrainingAllowed
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
