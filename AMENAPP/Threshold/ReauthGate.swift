// ReauthGate.swift
// AMEN — THRESHOLD Smart Profile / Identity Switcher
//
// W3: Step-up authentication policy + gate actor.
//
// Spec §6 capability→requirement matrix implemented in DefaultReauthPolicy.
// ReauthGate.evaluate() is fail-closed: any thrown error or cancelled auth → .denied.
//
// INVARIANT (caller's responsibility): a cancelled or denied step-up MUST NOT change
// which profile is active. ReauthGate only returns an outcome; switching is the caller's job.

import Foundation
import LocalAuthentication

// MARK: - Outcome

enum ReauthOutcome: Sendable, Equatable {
    case allowed
    case requiresAuthentication(ReauthRequirement)
    case denied
}

// MARK: - Default Policy

/// Pure, stateless implementation of the spec §6 capability→requirement matrix.
/// Ordering (most restrictive first):
///   keyManagement (maxAge 120s) > guardianTools (maxAge 300s)
///   > orgAdmin/moderate (biometricOrPasscode) > post/dm-only (none)
struct DefaultReauthPolicy: ReauthPolicy {

    nonisolated init() {}

    nonisolated func requirement(switchingTo profile: ProfileDescriptor) -> ReauthRequirement {
        let caps = profile.capabilities

        // Tier 1 — strictest: keyManagement demands recent auth within 120 s.
        if caps.contains(.keyManagement) {
            return .biometricOrPasscodeAndRecentAuth(maxAge: 120)
        }

        // Tier 2 — guardianTools demands recent auth within 300 s.
        if caps.contains(.guardianTools) {
            return .biometricOrPasscodeAndRecentAuth(maxAge: 300)
        }

        // Tier 3 — elevated but no recency window required.
        if caps.contains(.moderate) || caps.contains(.orgAdmin) {
            return .biometricOrPasscode
        }

        // Tier 4 — standard capabilities only (.post, .dm, or empty).
        return .none
    }
}

// MARK: - Gate Actor

/// Evaluates whether the user may switch into a profile and, if step-up auth is needed,
/// performs the LocalAuthentication prompt.
///
/// Fail-closed contract: any error thrown by LAContext — including cancellation —
/// results in `.denied`. The active profile is NEVER changed by this actor.
actor ReauthGate {

    // MARK: - Public API

    /// Evaluate whether `profile` may be entered.
    ///
    /// - Parameters:
    ///   - profile: The destination profile descriptor.
    ///   - policy: The requirement policy to apply (default: `DefaultReauthPolicy`).
    ///   - lastAuthAt: The timestamp of the user's most recent successful authentication,
    ///     if known. Pass `nil` to treat recency as unmet.
    /// - Returns: A `ReauthOutcome` indicating whether the switch is allowed.
    func evaluate(
        profile: ProfileDescriptor,
        policy: ReauthPolicy? = nil,
        lastAuthAt: Date?
    ) async -> ReauthOutcome {
        let policy = policy ?? DefaultReauthPolicy()
        let req = policy.requirement(switchingTo: profile)

        switch req {
        case .none:
            return .allowed

        case .biometricOrPasscode:
            let outcome = await performBiometricOrPasscode()
            if case .allowed = outcome {
                await loadKeyContext(for: profile.e2eeKeyRef)
            }
            return outcome

        case .biometricOrPasscodeAndRecentAuth(let maxAge):
            // If the user authenticated recently enough, no re-prompt needed.
            if let last = lastAuthAt, Date().timeIntervalSince(last) <= maxAge {
                await loadKeyContext(for: profile.e2eeKeyRef)
                return .allowed
            }
            // Recency window missed or unknown — require explicit step-up.
            let outcome = await performBiometricOrPasscode()
            if case .allowed = outcome {
                await loadKeyContext(for: profile.e2eeKeyRef)
            }
            return outcome
        }
    }

    // MARK: - Private Helpers

    /// Runs `LAContext.evaluatePolicy` and returns `.allowed` on success, `.denied` on any
    /// failure, error, or cancellation. Fail-closed by design.
    private func performBiometricOrPasscode() async -> ReauthOutcome {
        let context = LAContext()
        var canEvalError: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &canEvalError) else {
            // Device has no passcode configured — cannot satisfy requirement.
            return .denied
        }

        do {
            // evaluatePolicy is a completion-handler API; bridge to async with continuation.
            let success = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
                context.evaluatePolicy(
                    .deviceOwnerAuthentication,
                    localizedReason: "Authenticate to access this profile"
                ) { granted, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: granted)
                    }
                }
            }
            return success ? .allowed : .denied
        } catch {
            // Any error — including LAError.userCancel — maps to .denied (fail-closed).
            return .denied
        }
    }

    /// Placeholder for W5 E2EE key context loading.
    /// Called only after a successful step-up so that keys are available for the new profile.
    private func loadKeyContext(for keyRef: KeyRef?) async {
        // W5: wire E2EE key load here
    }
}
