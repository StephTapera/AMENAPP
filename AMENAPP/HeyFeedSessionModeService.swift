//
//  HeyFeedSessionModeService.swift
//  AMENAPP
//
//  Manages Hey Feed session modes — temporary contextual feed shaping.
//  Integrates with HeyFeedNLPreferencesService ranking modulation.
//

import Foundation
import SwiftUI
import FirebaseAuth

@MainActor
final class HeyFeedSessionModeService: ObservableObject {

    static let shared = HeyFeedSessionModeService()
    private init() { loadPersistedMode() }

    // MARK: - State

    @Published private(set) var activeMode: HeyFeedSessionMode = .none
    @Published private(set) var modeExpiresAt: Date?
    @Published private(set) var modeLabel: String = ""

    // MARK: - Public API

    func setMode(_ mode: HeyFeedSessionMode, duration: HeyFeedDuration? = nil) {
        let effectiveDuration = duration ?? mode.defaultDuration
        activeMode = mode
        modeExpiresAt = effectiveDuration.expiryDate
        modeLabel = mode.label
        persistMode()
        scheduleExpiry(duration: effectiveDuration)
    }

    func clearMode() {
        activeMode = .none
        modeExpiresAt = nil
        modeLabel = ""
        persistMode()
    }

    var isActive: Bool { activeMode != .none }

    var timeRemainingLabel: String {
        guard let exp = modeExpiresAt else { return "" }
        let remaining = exp.timeIntervalSinceNow
        if remaining <= 0 { return "" }
        if remaining < 3600  { return "· \(Int(remaining/60))m left" }
        if remaining < 86400 { return "· \(Int(remaining/3600))h left" }
        return "· \(Int(remaining/86400))d left"
    }

    /// Returns the ranking delta for a given taxonomy key under active session mode.
    /// Used by HomeFeedAlgorithm / HeyFeedNLRankingModulator.
    func rankingDelta(for key: String) -> Double {
        guard activeMode != .none else { return 0 }
        guard let exp = modeExpiresAt, Date() < exp else {
            // Expired — clear silently
            Task { @MainActor in clearMode() }
            return 0
        }
        return activeMode.rankingAdjustments[key] ?? 0
    }

    // MARK: - Persistence (UserDefaults for session speed)

    private let modeKey    = "heyFeed.sessionMode"
    private let expiryKey  = "heyFeed.sessionModeExpiry"

    private func persistMode() {
        UserDefaults.standard.set(activeMode.rawValue, forKey: modeKey)
        if let exp = modeExpiresAt {
            UserDefaults.standard.set(exp.timeIntervalSince1970, forKey: expiryKey)
        } else {
            UserDefaults.standard.removeObject(forKey: expiryKey)
        }
    }

    private func loadPersistedMode() {
        guard let raw = UserDefaults.standard.string(forKey: modeKey),
              let mode = HeyFeedSessionMode(rawValue: raw) else { return }

        if let expTs = UserDefaults.standard.object(forKey: expiryKey) as? Double {
            let exp = Date(timeIntervalSince1970: expTs)
            if Date() > exp {
                // Already expired
                activeMode = .none
                return
            }
            modeExpiresAt = exp
        }

        activeMode = mode
        modeLabel = mode.label
    }

    private var expiryTask: Task<Void, Never>?

    private func scheduleExpiry(duration: HeyFeedDuration) {
        expiryTask?.cancel()
        guard let exp = duration.expiryDate else { return }
        let delay = exp.timeIntervalSinceNow
        guard delay > 0 else { return }
        expiryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.clearMode()
        }
    }
}
