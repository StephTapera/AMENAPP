//
//  InboundBlockSignalService.swift
//  AMENAPP
//
//  Trust & Safety Remediation (item 21 follow-on) — client for the advisory
//  "this account has been blocked by several people" signal.
//
//  The backend (getInboundBlockSignal) returns ONLY a coarse bucket — never the
//  raw block count or any blocker identities. This client mirrors that: callers
//  learn one bit ("should I caution the user?") and nothing more.
//
//  POSTURE:
//    - Flag-gated by AMENFeatureFlags.inboundBlockWarningEnabled; the backend is
//      independently gated by INBOUND_BLOCK_WARNING_ENABLED. Both default OFF.
//    - FAIL-OPEN: any error → no warning. This is advisory only and never blocks
//      messaging (real block enforcement lives in antiHarassmentEnforcement).
//

import Foundation
import FirebaseFunctions

@MainActor
final class InboundBlockSignalService {
    static let shared = InboundBlockSignalService()
    private init() {}

    /// Coarse, privacy-preserving advisory result.
    struct Signal: Equatable {
        let enabled: Bool
        let shouldWarn: Bool
        /// Display-only threshold (e.g. "blocked by several people"); never the real count.
        let threshold: Int

        static let none = Signal(enabled: false, shouldWarn: false, threshold: 0)
    }

    /// Whether to surface a caution before DMing `userId`.
    /// Returns `.none` when the flag is off, the id is empty, or on any error.
    func warning(for userId: String) async -> Signal {
        guard AMENFeatureFlags.shared.inboundBlockWarningEnabled else { return .none }
        let target = userId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return .none }

        do {
            let result = try await Functions.functions()
                .httpsCallable("getInboundBlockSignal")
                .call(["targetUid": target])
            guard let dict = result.data as? [String: Any] else { return .none }
            return Signal(
                enabled: dict["enabled"] as? Bool ?? false,
                shouldWarn: dict["shouldWarn"] as? Bool ?? false,
                threshold: dict["threshold"] as? Int ?? 0
            )
        } catch {
            // Advisory only — fail open (no warning).
            return .none
        }
    }
}
