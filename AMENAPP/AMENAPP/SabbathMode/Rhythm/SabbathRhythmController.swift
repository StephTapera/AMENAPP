// SabbathRhythmController.swift
// AMENAPP — SabbathMode / Rhythm (Sabbath Mode v2, Wave 0)
//
// The observable engine that drives the v2 subtraction model. It owns the active
// SabbathRhythmState, resolves it from triggers, exposes the active
// SabbathSubtractionPolicy (the only thing that hides UI — I3), and records a
// private, local-only SabbathRestSignal at the gentle return.
//
// Singleton + observed-directly, matching SabbathModeService.shared.
// Entirely inert unless `sabbath_mode_enabled` is ON. Uses async/await, never Combine.

import Foundation
import SwiftUI

// MARK: - Presentation routing

/// What the Sabbath rhythm UI should present, driven by controller state.
enum SabbathRhythmPresentation: Identifiable, Equatable {
    /// The deliberate entry ritual (candle-lighting equivalent).
    case beginThreshold
    /// The gentle, private return shown *after* exiting rest. Carries the rest signal.
    case gentleReturn(SabbathRestSignal)

    var id: String {
        switch self {
        case .beginThreshold:  return "begin"
        case .gentleReturn:    return "return"
        }
    }
}

// MARK: - Controller

@MainActor
final class SabbathRhythmController: ObservableObject {

    static let shared = SabbathRhythmController()

    // MARK: Published state

    /// The active rhythm state. `.normal` unless a trigger proposes otherwise.
    @Published private(set) var state: SabbathRhythmState = .normal
    /// The removal policy for the active state — the single source of truth for hiding (I3).
    @Published private(set) var activePolicy: SabbathSubtractionPolicy = .none
    /// Drives the threshold begin / gentle-return surfaces.
    @Published var presentation: SabbathRhythmPresentation?
    /// The burden the user named at entry (Sabbath Intention), reflected back at close.
    @Published private(set) var currentIntention: String?

    // MARK: Private state

    /// User's manual override (ManualTrigger source of truth): the state they deliberately
    /// chose (`.rest`, or `.holyGround` when deepened), or nil if not manually resting.
    private var manualRestState: SabbathRhythmState?
    /// When the current rest period began, for computing `timeInState`.
    private var restEnteredAt: Date?
    /// True after a one-tap exit, forcing `.normal` until triggers naturally fall idle.
    private var exitOverrideActive = false
    /// The user's persisted config (weekly schedule + Wave 1 trigger opt-ins). Loaded at
    /// init so a scheduled Sabbath fires across launches; replaced via `applyConfig`.
    private var config: SabbathRhythmConfig = .disabled
    /// Latest injected ambient context (doomscroll / location / motion). Neutral by default,
    /// so an absent sensor layer can never trigger a Sabbath state.
    private var ambientSignals: SabbathAmbientSignals = .none

    private let resolver = SabbathTriggerResolver()
    private let flags = AMENFeatureFlags.shared
    private let defaults = UserDefaults.standard
    private let configStore = SabbathRhythmConfigStore()
    private let lastSignalKey = "sabbath_rhythm_last_rest_signal"
    private var minuteTimer: Timer?

    private init() {
        config = configStore.load()
        recompute(now: Date())
        startMinuteTicker()
        #if DEBUG
        SabbathRhythmInvariants.runDebugChecks()
        #endif
    }

    /// Re-evaluate triggers each minute so a scheduled rest window flips state on its
    /// boundary without any user action. Cheap and inert while Sabbath Mode is OFF.
    private func startMinuteTicker() {
        minuteTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.recompute(now: Date()) }
        }
    }

    // MARK: Trigger configuration

    /// The user's current persisted configuration (read-only snapshot for the settings UI).
    var currentConfig: SabbathRhythmConfig { config }

    /// Replace the persisted config (schedule + Wave 1 trigger opt-ins), save it locally,
    /// and recompute. This is how the settings surface drives the engine.
    func applyConfig(_ newConfig: SabbathRhythmConfig) {
        config = newConfig
        configStore.save(newConfig)
        recompute(now: Date())
    }

    /// Set or clear just the weekly rest window, persisting it through the config.
    func configureSchedule(_ schedule: SabbathSchedule?) {
        var updated = config
        updated.schedule = schedule
        applyConfig(updated)
    }

    /// Inject the latest ambient context (feed dwell / at-worship / walking). The future
    /// sensor layer calls this; it is a no-op for behaviour unless the matching ambient
    /// trigger is enabled in config and `sabbath_mode_enabled` is ON.
    func updateAmbientSignals(_ signals: SabbathAmbientSignals) {
        guard signals != ambientSignals else { return }
        ambientSignals = signals
        recompute(now: Date())
    }

    // MARK: Threshold — begin

    /// Ask to begin rest. Presents the entry ritual; rest is not committed until confirmed.
    func requestBeginRest() {
        guard isEnabled else { return }
        presentation = .beginThreshold
    }

    /// Commit rest after the entry ritual. Optionally names the burden being laid down.
    func confirmBeginRest(intention: String?) {
        guard isEnabled else { return }
        currentIntention = intention?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        manualRestState = .rest
        exitOverrideActive = false
        presentation = nil
        recompute(now: Date())
    }

    /// Deepen an in-progress manual rest into prayer / silence (`.holyGround`) — the
    /// single-surface state. No-op unless Sabbath Mode is ON and a manual rest is active.
    func deepenToHolyGround() {
        guard isEnabled, manualRestState != nil else { return }
        manualRestState = .holyGround
        exitOverrideActive = false
        recompute(now: Date())
    }

    /// Ease a deepened rest back from `.holyGround` to ordinary `.rest` without leaving rest.
    func returnToRest() {
        guard isEnabled, manualRestState == .holyGround else { return }
        manualRestState = .rest
        recompute(now: Date())
    }

    // MARK: Threshold — exit (Invariant I1)

    /// One-tap, guilt-free exit. Always available in any Sabbath state. Records a
    /// private rest signal and surfaces the non-blocking gentle return afterward.
    func leaveRest() {
        let signal = makeRestSignal(now: Date())
        manualRestState = nil
        exitOverrideActive = true
        recompute(now: Date())
        if let signal {
            persist(signal)
            presentation = .gentleReturn(signal)
        }
        currentIntention = nil
    }

    /// Attach an optional private reflection to the just-closed rest signal. Local only.
    func recordReturnReflection(_ text: String, for signal: SabbathRestSignal) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let updated = SabbathRestSignal(
            timeInState: signal.timeInState,
            reflection: trimmed.isEmpty ? nil : trimmed,
            closedAt: signal.closedAt
        )
        persist(updated)
    }

    /// Dismiss the gentle return surface.
    func dismissReturn() {
        if case .gentleReturn = presentation { presentation = nil }
    }

    // MARK: State resolution

    /// Recompute the active state from triggers and publish the matching policy.
    func recompute(now: Date) {
        guard isEnabled else {
            apply(.normal)
            return
        }

        let triggers: [SabbathTriggerSource] = [
            SabbathManualTrigger(
                isEnabled: flags.sabbathTriggerManualEnabled,
                manualState: manualRestState
            ),
            SabbathScheduleTrigger(
                isEnabled: flags.sabbathTriggerScheduleEnabled,
                schedule: config.schedule
            ),
            // Wave 1 ambient triggers — each opt-in via config, fed by injected signals.
            SabbathUsageTrigger(
                isEnabled: config.usageTriggerEnabled,
                dwellSeconds: ambientSignals.feedDwellSeconds
            ),
            SabbathLocationTrigger(
                isEnabled: config.locationTriggerEnabled,
                isAtPlaceOfWorship: ambientSignals.isAtPlaceOfWorship
            ),
            SabbathMotionTrigger(
                isEnabled: config.motionTriggerEnabled,
                isWalking: ambientSignals.isWalking
            ),
        ]

        let proposed = resolver.resolve(triggers: triggers, now: now)

        if proposed == .normal {
            // Triggers fell idle — a previous exit override has run its course.
            exitOverrideActive = false
            apply(.normal)
            return
        }

        // A trigger proposes rest. Honor a one-tap exit until the window ends.
        apply(exitOverrideActive ? .normal : proposed)
    }

    /// Whether an in-app notification for `route` may be suppressed right now.
    /// Emergency / safety routes are never suppressed (Guardrail 2 / I1).
    func maySuppressInAppNotification(route: String) -> Bool {
        SabbathSafetyInvariant.maySuppressNotification(route: route, policy: activePolicy)
    }

    // MARK: Private helpers

    private var isEnabled: Bool { flags.sabbathModeEnabled }

    private func apply(_ newState: SabbathRhythmState) {
        if newState != .normal, restEnteredAt == nil {
            restEnteredAt = Date()
        } else if newState == .normal {
            restEnteredAt = nil
        }
        state = newState
        activePolicy = SabbathSubtractionPolicy.policy(for: newState)
    }

    private func makeRestSignal(now: Date) -> SabbathRestSignal? {
        guard let enteredAt = restEnteredAt else { return nil }
        return SabbathRestSignal(
            timeInState: max(0, now.timeIntervalSince(enteredAt)),
            reflection: nil,
            closedAt: now
        )
    }

    private func persist(_ signal: SabbathRestSignal) {
        // Local-only. No upload, no streak, no count (I2 / Guardrail 1).
        guard let data = try? JSONEncoder().encode(signal) else { return }
        defaults.set(data, forKey: lastSignalKey)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
