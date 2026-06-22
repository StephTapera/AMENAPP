// BereanIslandStateMachine.swift
// AMEN — Berean Island Wave 1
//
// @Observable @MainActor state machine for the Berean Island in-app pill.
//
// Gate invariants (all must pass before fire() changes state):
//   1. Consumed-ID dedup   — each trigger ID fires at most once ever.
//   2. Daily promo cap     — ≤3 proactive suggestions per calendar day (local timezone).
//                           Counter persisted in UserDefaults; resets at local midnight.
//   3. Quiet hours         — blocked 22:00–07:00 local time (hour >= 22 || hour < 7).
//   4. Sabbath mode        — delegates to SabbathModeService.shared.currentState.
//                           Sabbath window = Sunday 00:00–24:00, user's local timezone.
//                           User can change the Sabbath day in Settings (SabbathModeService
//                           stores the preference). Sundown convention is NOT used unless the
//                           existing SabbathModeService adopts it — we delegate entirely.
//
// Live session staleness: sessions older than maxLiveSessionAge (30 min) are discarded
// on restore. Dead sessions are never resurrected.
//
// Feature flag: AMENFeatureFlags.bereanIslandEnabled

import Foundation
import Observation
import SwiftUI

@Observable @MainActor
final class IslandStateMachine {

    // MARK: - State

    private(set) var state: IslandState = .hidden

    // MARK: - UserDefaults keys

    private enum Key {
        static let consumed      = "berean.island.consumedIDs"
        static let promoCount    = "berean.island.promoCount"
        static let promoDate     = "berean.island.promoDate"
        static let liveSession   = "berean.island.liveSession"
    }

    // MARK: - Constants

    private static let dailyPromoLimit      = 3
    private static let quietStart           = 22
    private static let quietEnd             = 7
    private static let maxLiveSessionAge    = TimeInterval(30 * 60)

    // MARK: - Init

    init() {
        restoreLiveSession()
    }

    // MARK: - Public API

    func fire(trigger: IslandSuggestion) {
        guard canFire(id: trigger.id) else { return }
        markConsumed(id: trigger.id)
        incrementDailyPromo()
        state = .actionReady(suggestion: trigger)
    }

    func startSession(_ kind: LiveSessionKind) {
        let session = IslandLiveSession(
            id: UUID().uuidString,
            kind: kind,
            startedAt: Date(),
            statusLine: kind.defaultStatusLine,
            progress: nil
        )
        state = .live(session: session)
        persistLiveSession(session)
    }

    func updateSessionProgress(_ progress: Double) {
        guard case .live(var session) = state else { return }
        session.progress = max(0, min(1, progress))
        state = .live(session: session)
        persistLiveSession(session)
    }

    func endSession() {
        clearPersistedLiveSession()
        withAnimation { state = .hidden }
    }

    func expand(context: IslandContext) {
        state = .expanded(context: context)
    }

    func compact(whisper: String? = nil) {
        state = .compact(whisper: whisper)
    }

    func hide() {
        state = .hidden
    }

    // MARK: - Gate checks

    private func canFire(id: String) -> Bool {
        guard !isConsumed(id: id)      else { return false }
        guard !isQuietHours()          else { return false }
        guard !isSabbath()             else { return false }
        guard dailyPromoCount() < Self.dailyPromoLimit else { return false }
        return true
    }

    private func isQuietHours() -> Bool {
        let h = Calendar.current.component(.hour, from: Date())
        return h >= Self.quietStart || h < Self.quietEnd
    }

    private func isSabbath() -> Bool {
        SabbathModeService.shared.currentState == .active
    }

    // MARK: - Consumed ID management

    private func isConsumed(id: String) -> Bool {
        consumedIDs.contains(id)
    }

    private func markConsumed(id: String) {
        var ids = consumedIDs
        ids.insert(id)
        UserDefaults.standard.set(Array(ids), forKey: Key.consumed)
    }

    private var consumedIDs: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: Key.consumed) ?? [])
    }

    // MARK: - Daily promo counter

    private func dailyPromoCount() -> Int {
        let today = Self.todayKey
        guard UserDefaults.standard.string(forKey: Key.promoDate) == today else { return 0 }
        return UserDefaults.standard.integer(forKey: Key.promoCount)
    }

    private func incrementDailyPromo() {
        let today = Self.todayKey
        let existing = (UserDefaults.standard.string(forKey: Key.promoDate) == today)
            ? UserDefaults.standard.integer(forKey: Key.promoCount) : 0
        UserDefaults.standard.set(today, forKey: Key.promoDate)
        UserDefaults.standard.set(existing + 1, forKey: Key.promoCount)
    }

    private static var todayKey: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    // MARK: - Live session persistence

    private func persistLiveSession(_ session: IslandLiveSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        UserDefaults.standard.set(data, forKey: Key.liveSession)
    }

    private func clearPersistedLiveSession() {
        UserDefaults.standard.removeObject(forKey: Key.liveSession)
    }

    private func restoreLiveSession() {
        guard
            let data = UserDefaults.standard.data(forKey: Key.liveSession),
            let session = try? JSONDecoder().decode(IslandLiveSession.self, from: data)
        else { return }

        guard Date().timeIntervalSince(session.startedAt) < Self.maxLiveSessionAge else {
            UserDefaults.standard.removeObject(forKey: Key.liveSession)
            return
        }

        state = .live(session: session)
    }
}

// MARK: - LiveSessionKind display helpers

extension LiveSessionKind {
    var defaultStatusLine: String {
        switch self {
        case .sermonCompanion: return "Sermon Companion"
        case .guidedStudy:     return "Guided Study"
        case .prayerTimer:     return "Prayer Timer"
        case .eventInProgress: return "Event in Progress"
        }
    }
}
