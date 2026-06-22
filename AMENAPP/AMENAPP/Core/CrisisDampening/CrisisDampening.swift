import Foundation
import Combine

// MARK: - CrisisDampening

/// GUARDIAN C59 — Crisis Dampening Engine
///
/// Activated by `crisisSurfaceOpened` signal (Tier S, device-only).
/// Sets `isActive = true` for a 72-hour cooling window (Remote Config tunable).
///
/// Persisted on-device only — NEVER synced to server.
/// Tier-S invariant: the activating signal's `tierCeiling == .s`; it must not reach the network.
///
/// Consumed by:
///   - `EntitlementGate.canAccess` — returns `.crisisSuppressed` for all upsellable capabilities
///   - Feed ranking — suppresses engagement-optimised ranking
///   - Verse pool — surfaces comfort/lament corpus instead of growth corpus
@MainActor
final class CrisisDampening: ObservableObject {
    static let shared = CrisisDampening()

    @Published private(set) var isActive: Bool = false

    private let windowKey = "crisis_dampening_active_until"

    /// Default cooling window in hours. Override via Remote Config key
    /// `ctx_crisis_dampening_window_hours` before calling `activate()`.
    var cooldownWindowHours: Double = 72

    private init() {
        restorePersistedState()
    }

    // MARK: - Public API

    /// Call when `crisisSurfaceOpened` signal is received (device-only, Tier S).
    func activate() {
        let activeUntil = Date().addingTimeInterval(cooldownWindowHours * 3600)
        UserDefaults.standard.set(activeUntil, forKey: windowKey)
        isActive = true
        scheduleExpiry(at: activeUntil)
    }

    /// Manually cancel dampening (e.g. user taps "I'm doing better").
    func deactivate() {
        UserDefaults.standard.removeObject(forKey: windowKey)
        isActive = false
    }

    /// The timestamp at which dampening will expire, if active.
    var activeUntil: Date? {
        UserDefaults.standard.object(forKey: windowKey) as? Date
    }

    // MARK: - Internal

    private func restorePersistedState() {
        guard let activeUntil = UserDefaults.standard.object(forKey: windowKey) as? Date else {
            return
        }
        if Date() < activeUntil {
            isActive = true
            scheduleExpiry(at: activeUntil)
        } else {
            // Stale entry — clean up
            UserDefaults.standard.removeObject(forKey: windowKey)
        }
    }

    private func scheduleExpiry(at date: Date) {
        let delay = date.timeIntervalSinceNow
        guard delay > 0 else {
            deactivate()
            return
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            // Re-check: another call to activate() may have extended the window
            guard let current = self.activeUntil, Date() >= current else { return }
            deactivate()
        }
    }
}

// MARK: - ContextBus Observer

extension CrisisDampening {
    /// Install on app launch to listen for Tier-S crisis signals on the local bus.
    /// Safe to call multiple times (subsequent calls create redundant streams, prefer
    /// calling once from AppDelegate/App init).
    func installSignalObserver() {
        Task {
            let stream = await ContextBus.shared.subscribe(to: [.crisisSurfaceOpened])
            for await _ in stream {
                await MainActor.run { self.activate() }
            }
        }
    }
}
