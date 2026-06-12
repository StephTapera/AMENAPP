// LowDataModeManager.swift
// AMEN — Global Resilience System
// Observes CapabilityMonitor and surfaces an effective low-data flag with optional
// user override. All state lives on @MainActor. No UI, no business logic beyond
// deriving isEffectiveLowData and writing/reading the UserDefaults override.

import Foundation
import Combine
import SwiftUI

// MARK: - LowDataModeManager

@MainActor
final class LowDataModeManager: ObservableObject {

    // MARK: Singleton

    static let shared = LowDataModeManager()

    // MARK: Published State

    /// True when the device is operating in low-data mode, accounting for any
    /// user override stored in UserDefaults.
    @Published private(set) var isEffectiveLowData: Bool = false

    /// True when the banner should be visible (low-data active and not dismissed
    /// by the user in this session). Resets automatically when low-data ends.
    @Published private(set) var showBanner: Bool = false

    // MARK: User Override

    /// Stored in UserDefaults under key "gr_dataMode_override".
    /// `.automatic` means no user override; hardware/network-derived mode is used.
    /// Non-optional so SwiftUI Picker bindings work directly.
    @Published var userOverride: DataMode = .automatic {
        didSet {
            persistOverride(userOverride)
            reconcile()
        }
    }

    // MARK: Private State

    private let overrideKey = "gr_dataMode_override"
    private var cancellables = Set<AnyCancellable>()

    // MARK: Init

    private init() {
        userOverride = loadPersistedOverride()
        // Seed synchronously before subscribing so isEffectiveLowData is correct
        // even if CapabilityMonitor.shared hasn't fired its first update yet.
        reconcile()
        startObserving()
    }

    // MARK: Public API

    /// Reverts to automatic (hardware/network derived) mode.
    func clearOverride() {
        userOverride = .automatic
    }

    // MARK: Observation

    private func startObserving() {
        // Observe every change to CapabilityMonitor's profile via Combine.
        CapabilityMonitor.shared
            .$profile
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.reconcile()
            }
            .store(in: &cancellables)
    }

    // MARK: State Reconciliation

    /// Derives isEffectiveLowData from the current override (if any) or the live
    /// hardware profile, then updates showBanner accordingly.
    private func reconcile() {
        let effective: Bool
        if userOverride != .automatic {
            effective = (userOverride == .lowData)
        } else {
            effective = (CapabilityMonitor.shared.profile.dataMode == .lowData)
        }

        isEffectiveLowData = effective

        if !effective {
            // Auto-hide the banner when the condition clears.
            showBanner = false
        } else if !showBanner {
            // Show the banner whenever low-data becomes active (unless already shown).
            showBanner = true
        }
    }

    // MARK: UserDefaults Persistence

    private func loadPersistedOverride() -> DataMode {
        guard let raw = UserDefaults.standard.string(forKey: overrideKey),
              let mode = DataMode(rawValue: raw) else {
            return .automatic
        }
        return mode
    }

    private func persistOverride(_ mode: DataMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: overrideKey)
    }
}
