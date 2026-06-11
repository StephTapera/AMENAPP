// AegisEnforcementService.swift
// AMEN Universal Migration & Context System — Aegis capability contracts (Wave 0, FROZEN)
//
// Registers two new GUARDIAN capabilities for the Context System. The deep logic
// (injection neutralization, server-side minor enforcement) lands in Wave 3
// (aegis-engineer); this file freezes the CONTRACT and the receipt shapes every
// other wave depends on.
//
//  C59 — Context Import Injection Defense
//    All pasted/uploaded import material is wrapped as inert data before extraction.
//    (a) the model is told document content is never instructions,
//    (b) known injection patterns are neutralized pre-LLM,
//    (c) extraction output is capped to the facet schema (free-text length-capped),
//    (d) a sanitizationPassId receipt is emitted and stored in Provenance.
//
//  C60 — Minor Context Constraints (enforced SERVER-SIDE, §1.12)
//    Under-18 accounts: Context QR disabled; faith "areas needing support" forced to
//    Tier P; matching queries filtered to youth-safe community indexes.

import Foundation

/// Receipt proving a body of imported text passed C59 sanitization. Its id is stored
/// in `Provenance.sanitizationPassId`; a facet whose receipt id is empty/unverified
/// must never be persisted.
struct SanitizationReceipt: Codable, Equatable {
    let passId: String                 // unique id; "" means "not sanitized"
    let neutralizedPatternCount: Int   // how many injection patterns were stripped
    let originalLength: Int
    let cappedLength: Int
    let createdAt: Date

    var isVerified: Bool { !passId.isEmpty }
    static let unverified = SanitizationReceipt(passId: "", neutralizedPatternCount: 0,
                                                originalLength: 0, cappedLength: 0, createdAt: .distantPast)
}

/// Outcome of a C60 minor-constraint check for a given capability request.
enum MinorConstraintDecision: Equatable {
    case allowed
    case denied(reason: String)
}

/// Client-side façade over the Aegis capability contracts. Wave 3 supplies the real
/// implementations; these defaults FAIL CLOSED so a half-wired build never leaks.
protocol ContextAegisEnforcing {
    /// C59: verify a facet carries a valid sanitization receipt before persistence.
    func verifySanitization(_ provenance: Provenance) -> Bool
    /// C60: may this minor-or-unknown-age user use the given context capability?
    func minorConstraint(for capability: ContextCapability, isMinor: Bool) -> MinorConstraintDecision
}

/// The Context-System capabilities subject to C60 gating.
enum ContextCapability: String, CaseIterable {
    case contextQR
    case faithAreasNeedingSupportServerWrite
    case communityMatching
}

final class AegisEnforcementService: ContextAegisEnforcing {

    static let shared = AegisEnforcementService()

    // C59 — sanitization receipt verification.
    func verifySanitization(_ provenance: Provenance) -> Bool {
        // A facet may only be persisted if it carries a non-empty sanitization receipt.
        // (Manual entry still gets a receipt issued by the entry path; see Wave 1.)
        !provenance.sanitizationPassId.isEmpty
    }

    // C60 — minor constraint checks. FAIL CLOSED: unknown age is treated as minor.
    func minorConstraint(for capability: ContextCapability, isMinor: Bool) -> MinorConstraintDecision {
        guard isMinor else { return .allowed }
        switch capability {
        case .contextQR:
            return .denied(reason: "Context QR is unavailable for accounts under 18.")
        case .faithAreasNeedingSupportServerWrite:
            return .denied(reason: "Sensitive faith support stays private on this device for minors.")
        case .communityMatching:
            // Allowed, but the caller MUST route to youth-safe indexes (enforced server-side).
            return .allowed
        }
    }
}
