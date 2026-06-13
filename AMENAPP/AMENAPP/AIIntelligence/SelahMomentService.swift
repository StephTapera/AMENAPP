// SelahMomentService.swift
// AMEN — Selah Moment invocation service
//
// SelahMomentService manages the canonical brief Selah pause triggered at
// intentional formation moments. It dispatches a haptic pulse and sets
// `isActive` for 1.2 seconds before returning to false.
//
// Canonical invocation sites (document here so callsites can be audited):
//   1. Commitment completion — when a user marks a witnessed commitment done.
//   2. Vulnerable content publish — when a user publishes a prayer request,
//      personal testimony, or sensitive reflection.
//
// Flag-gated: AMENFeatureFlags.shared.selahMoments.
// When the flag is OFF, trigger() is a no-op and isActive never becomes true.
//
// Usage:
//   @StateObject private var selahService = SelahMomentService()
//   Button("Complete") {
//       selahService.trigger()
//   }
//   .selahMoment(trigger: selahService.isActive)

import SwiftUI
import UIKit

@MainActor
final class SelahMomentService: ObservableObject {

    // MARK: - Published State

    /// True for exactly SelahMomentConfig.duration seconds after trigger() fires.
    /// Consumers can bind `.selahMoment(trigger:)` or any overlay directly to this.
    @Published private(set) var isActive: Bool = false

    // MARK: - Private

    private var deactivationTask: Task<Void, Never>?

    // MARK: - Trigger

    /// Fires a haptic pulse and sets `isActive = true` for `SelahMomentConfig.duration`
    /// seconds, then resets to false.
    ///
    /// Calling trigger() while already active re-arms the timer — the active window
    /// extends from the most-recent call.
    ///
    /// No-op when `AMENFeatureFlags.shared.selahMoments` is false.
    func trigger() {
        guard AMENFeatureFlags.shared.selahMoments else { return }

        // Haptic is a separate accessibility axis from visual motion — always fires.
        let generator = UIImpactFeedbackGenerator(style: SelahMomentConfig.haptic)
        generator.prepare()
        generator.impactOccurred()

        isActive = true

        // Cancel any in-flight deactivation before starting a new one.
        deactivationTask?.cancel()
        deactivationTask = Task { [weak self] in
            do {
                // Wait exactly the configured duration.
                try await Task.sleep(
                    nanoseconds: UInt64(SelahMomentConfig.duration * 1_000_000_000)
                )
                self?.isActive = false
            } catch {
                // Task was cancelled (re-arm scenario) — leave isActive as-is.
            }
        }
    }
}
