// ONECallableService.swift
// ONE — Cloud Functions Callable Client Stubs
// P0-H | Skeleton only. No logic dispatched yet. Logic added per phase.
//
// SAFETY RULES:
//   • All callables require Firebase Auth + App Check (enforced server-side).
//   • NEVER write reach budget, evidence, or entitlement from client.
//   • Deploy checklist in PLAN.md §8 — do not auto-deploy.
//
// Deploy prerequisite: Switch Firebase console (amen-5e359) App Check
// from "debug" to "enforce" mode before any callable reaches external users.

import Foundation
import FirebaseFunctions

// MARK: - ONECallableService

@MainActor
final class ONECallableService {

    static let shared = ONECallableService()
    private let functions = Functions.functions()

    private init() {}

    // MARK: - P0 Stubs (callable exists; logic is server-side no-op until phase ships)

    /// Validates a privacy contract and records a Moment.
    /// Server enforces audience scope, lifetime scheduling, and ConsentDNA attachment.
    func sendMoment(momentID: String, privacyContractJSON: [String: Any]) async throws -> String {
        let callable = functions.httpsCallable("one_sendMoment")
        let result = try await callable.call(["momentID": momentID, "privacyContract": privacyContractJSON])
        guard let data = result.data as? [String: Any],
              let id = data["momentID"] as? String else {
            throw ONECallableError.invalidResponse("one_sendMoment")
        }
        return id
    }

    /// Server-side decay trigger. Also invoked by Cloud Scheduler.
    /// Skips decay if moment has been reported (evidence path takes precedence).
    func expireMoment(momentID: String) async throws {
        let callable = functions.httpsCallable("one_expireMoment")
        _ = try await callable.call(["momentID": momentID])
    }

    /// Locks a server-side evidence copy BEFORE any decay can run.
    /// Returns evidence ID for reference.
    func reportMoment(momentID: String, reason: String) async throws -> String {
        let callable = functions.httpsCallable("one_reportMoment")
        let result = try await callable.call(["momentID": momentID, "reason": reason])
        guard let data = result.data as? [String: Any],
              let evidenceID = data["evidenceID"] as? String else {
            throw ONECallableError.invalidResponse("one_reportMoment")
        }
        return evidenceID
    }

    /// Sends a witness request. Season is optional (defaults to .indefinite on server).
    func requestWitness(targetUID: String, seasonLabel: String?) async throws -> String {
        var params: [String: Any] = ["targetUID": targetUID]
        if let label = seasonLabel { params["seasonLabel"] = label }
        let callable = functions.httpsCallable("one_requestWitness")
        let result = try await callable.call(params)
        guard let data = result.data as? [String: Any],
              let requestID = data["requestID"] as? String else {
            throw ONECallableError.invalidResponse("one_requestWitness")
        }
        return requestID
    }

    /// Relays a Moment. Decrements reach budget server-side.
    /// Client CANNOT write to /one_reach/ — server enforces the cap.
    func relayMoment(momentID: String, toUIDs: [String]) async throws -> Int {
        let callable = functions.httpsCallable("one_relayMoment")
        let result = try await callable.call(["momentID": momentID, "toUIDs": toUIDs])
        guard let data = result.data as? [String: Any],
              let remaining = data["sharesRemaining"] as? Int else {
            throw ONECallableError.invalidResponse("one_relayMoment")
        }
        return remaining
    }

    /// Initiates repair flow. Other party must call acceptRepairFlow to proceed.
    func activateRepairFlow(otherUID: String) async throws -> String {
        let callable = functions.httpsCallable("one_activateRepairFlow")
        let result = try await callable.call(["otherUID": otherUID])
        guard let data = result.data as? [String: Any],
              let flowID = data["flowID"] as? String else {
            throw ONECallableError.invalidResponse("one_activateRepairFlow")
        }
        return flowID
    }

    /// Accepts a repair flow. Both parties must call this before phase transitions to .active.
    func acceptRepairFlow(flowID: String) async throws {
        let callable = functions.httpsCallable("one_acceptRepairFlow")
        _ = try await callable.call(["flowID": flowID])
    }

    /// Verifies StoreKit entitlement server-side (checks App Store receipt).
    /// Client entitlement display is informational only — gating enforced server-side.
    func verifyEntitlement() async throws -> ONEEntitlement {
        let callable = functions.httpsCallable("one_verifyEntitlement")
        let result = try await callable.call([:])
        guard let data = result.data as? [String: Any] else {
            throw ONECallableError.invalidResponse("one_verifyEntitlement")
        }
        let tierString = data["tier"] as? String ?? "free"
        let tier = ONEEntitlementTier(rawValue: tierString) ?? .free
        let validUntilInterval = data["validUntilTimestamp"] as? Double
        let validUntil = validUntilInterval.map { Date(timeIntervalSince1970: $0) }
        return ONEEntitlement(tier: tier, storeKitTransactionID: nil, validUntil: validUntil, trialUsed: false)
    }

    /// Activates a legacy directive. Trustee-only — server validates trustee UID.
    func activateLegacy(directiveID: String) async throws {
        let callable = functions.httpsCallable("one_activateLegacy")
        _ = try await callable.call(["directiveID": directiveID])
    }
}

// MARK: - ONECallableError

enum ONECallableError: LocalizedError {
    case invalidResponse(String)
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .invalidResponse(let fn): return "Unexpected response from \(fn)."
        case .unauthorized:            return "You are not authorized to perform this action."
        }
    }
}
