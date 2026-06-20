import Foundation
import SwiftUI

// MARK: - Selah Contextual User Preferences (persisted)
// The user-owned half of the settings: which features they want, what they've granted,
// and how interruptible they are. Flags decide *capability*; preferences decide *consent
// and taste*. Both must agree before the evaluator ever sees a feature.

struct SelahContextualPreferences: Codable, Equatable {
    var enabledFeatures: Set<SelahContextualFeature>
    var grantedPermissions: Set<SelahContextualPermission>
    var interruptTolerance: Double
    var chosenSabbathWeekday: Int?
    var quietStartHour: Int
    var quietEndHour: Int
    var minimumMinutesBetweenSurfaces: Int

    static let `default` = SelahContextualPreferences(
        enabledFeatures: Set(SelahContextualFeature.allCases),
        grantedPermissions: [],
        interruptTolerance: 0.5,
        chosenSabbathWeekday: nil,
        quietStartHour: 22,
        quietEndHour: 23,
        minimumMinutesBetweenSurfaces: 240
    )
}

// MARK: - Selah Contextual Controller
// The runtime spine. Singleton + observed-directly, matching SabbathRhythmController.shared
// and SelahMomentService conventions. Entirely inert unless `selah_contextual_enabled` is ON.
//
// Responsibilities:
//   1. Persist user preferences (UserDefaults JSON) and per-feature cooldown timestamps.
//   2. On `refresh`, build a `SelahContextualInput` from the signal provider, fold flags +
//      preferences + Sabbath + cooldowns into `SelahContextualSettings`, and run the
//      deterministic evaluator. Detected clipboard references are grafted onto the
//      copied-verse suggestion so its "Read" action is real.
//   3. Fail-closed Berean gate: any surfaced suggestion carrying scripture references is
//      run through BereanConstitutionalReviewGate before it can reach the UI (feature 17).
//   4. Honor app-wide Sabbath: when Sabbath is active, force the evaluator's Sabbath-silence
//      path so only the rest surface can appear.
//   5. Route primary actions (open passage, open bulletin capture) and record cooldowns.

@MainActor
final class SelahContextualController: ObservableObject {

    static let shared = SelahContextualController()

    // MARK: Published state

    /// The suggestions cleared to surface this evaluation (never `.silent`), Berean-gated.
    @Published private(set) var surfacedSuggestions: [SelahContextualSuggestion] = []
    /// The single highest-confidence suggestion to present, or nil when Selah stays quiet.
    @Published private(set) var currentSuggestion: SelahContextualSuggestion?
    /// User preferences (persisted). Mutating via the provided setters re-persists + re-evaluates.
    @Published private(set) var preferences: SelahContextualPreferences
    /// Drives the reader sheet when a scripture-bearing suggestion's primary action fires.
    @Published var presentedReader: SelahContextualReaderRequest?

    // MARK: Private state

    private let provider = SelahContextualSignalProvider()
    private let service = SelahContextualIntelligenceService.shared
    private let defaults = UserDefaults.standard
    private let prefsKey = "selah_contextual_preferences_v1"
    private let cooldownKey = "selah_contextual_cooldowns_v1"
    /// Per-feature last-surfaced timestamps (cooldown source of truth).
    private var cooldowns: [SelahContextualFeature: Date]
    /// IDs the user dismissed this session — never re-surface within the session.
    private var dismissedIds: Set<UUID> = []

    private init() {
        self.preferences = SelahContextualController.loadPreferences(defaults: UserDefaults.standard, key: "selah_contextual_preferences_v1")
        self.cooldowns = SelahContextualController.loadCooldowns(defaults: UserDefaults.standard, key: "selah_contextual_cooldowns_v1")
    }

    // MARK: - Evaluation

    /// Re-evaluate the contextual signals and publish surfaced suggestions.
    /// No-op (and clears any surface) when the master flag is OFF.
    func refresh(
        now: Date = Date(),
        sessionDurationSeconds: TimeInterval = 0,
        mediaViewedCount: Int = 0,
        highLoadContentFraction: Double = 0,
        recentReflectionText: String? = nil,
        recentScriptureRefs: [String] = [],
        clipboardScriptureRefs: [String] = [],
        externalConfidences: [SelahContextualFeature: Double] = [:]
    ) async {
        guard SelahContextualFlags.isMasterEnabled() else {
            if currentSuggestion != nil || !surfacedSuggestions.isEmpty {
                surfacedSuggestions = []
                currentSuggestion = nil
            }
            return
        }

        let input = provider.buildInput(
            now: now,
            sessionDurationSeconds: sessionDurationSeconds,
            mediaViewedCount: mediaViewedCount,
            highLoadContentFraction: highLoadContentFraction,
            recentReflectionText: recentReflectionText,
            recentScriptureRefs: recentScriptureRefs,
            clipboardScriptureRefs: clipboardScriptureRefs,
            externalConfidences: externalConfidences
        )

        let settings = effectiveSettings(now: now)
        let evaluation = service.evaluate(input: input, settings: settings)

        // Graft detected clipboard references onto the copied-verse suggestion so its
        // "Read" action opens the actual passage (and the Berean gate verifies the ref).
        let prepared = evaluation.surfacedSuggestions.map { suggestion -> SelahContextualSuggestion in
            guard suggestion.feature == .copiedVerseCatch, !clipboardScriptureRefs.isEmpty else { return suggestion }
            return SelahContextualSuggestion(
                id: suggestion.id,
                feature: suggestion.feature,
                surface: suggestion.surface,
                title: "Open the verse you copied",
                message: "You copied a reference. Open it in context with cross-references?",
                scriptureRefs: clipboardScriptureRefs,
                confidence: suggestion.confidence,
                createdAt: suggestion.createdAt
            )
        }

        // Berean fail-closed gate: any surfaced suggestion carrying scripture refs must pass.
        var cleared: [SelahContextualSuggestion] = []
        for suggestion in prepared where !dismissedIds.contains(suggestion.id) {
            if suggestion.scriptureRefs.isEmpty {
                cleared.append(suggestion)
            } else if await passesBereanGate(suggestion) {
                cleared.append(suggestion)
            }
            // else: withheld — the trust layer made visible.
        }

        let ranked = cleared.sorted { $0.confidence > $1.confidence }
        surfacedSuggestions = ranked
        currentSuggestion = ranked.first
    }

    /// Fold flags + preferences + Sabbath + cooldowns into the evaluator's settings.
    private func effectiveSettings(now: Date) -> SelahContextualSettings {
        var settings = SelahContextualSettings()
        // Capability ∩ taste: only features the flags AND the user both allow.
        settings.enabledFeatures = SelahContextualFlags.flagEnabledFeatures()
            .intersection(preferences.enabledFeatures)
        settings.grantedPermissions = preferences.grantedPermissions
        settings.interruptTolerance = preferences.interruptTolerance
        settings.quietHours = quietRange()
        settings.minimumMinutesBetweenSurfaces = preferences.minimumMinutesBetweenSurfaces
        settings.lastSurfaceAtByFeature = cooldowns

        // App-wide Sabbath wins: force the evaluator's Sabbath-silence path so only the
        // rest surface can appear, regardless of the user's chosen weekday.
        if SabbathModeService.shared.currentState == .active {
            settings.chosenSabbathWeekday = Calendar.current.component(.weekday, from: now)
        } else {
            settings.chosenSabbathWeekday = preferences.chosenSabbathWeekday
        }
        return settings
    }

    private func quietRange() -> ClosedRange<Int> {
        let lo = min(max(preferences.quietStartHour, 0), 23)
        let hi = min(max(preferences.quietEndHour, 0), 23)
        return lo <= hi ? lo...hi : hi...lo
    }

    // MARK: - Berean Verification Gate (feature 17, fail-closed)

    private func passesBereanGate(_ suggestion: SelahContextualSuggestion) async -> Bool {
        let payload = BereanContextPayload(
            selectedText: [suggestion.title, suggestion.message].joined(separator: "\n"),
            sourceSurface: "selahContextual",
            sourceId: suggestion.feature.rawValue,
            contentType: .scripture,
            scriptureReference: suggestion.scriptureRefs.first,
            metadata: ["selahFeature": suggestion.feature.rawValue]
        )
        let result = await BereanConstitutionalReviewGate.shared.review(
            action: .reflect,
            payload: payload,
            mode: .reflect
        )
        return result.passed
    }

    // MARK: - User actions

    /// Handle the primary ("Read" / "Open" / "Rest") action: route by feature, then dismiss.
    func handlePrimary(_ suggestion: SelahContextualSuggestion) {
        recordSurfaced(suggestion.feature)
        switch suggestion.feature {
        case .bulletinSlideCapture:
            NotificationCenter.default.post(name: .selahOpenBulletinCapture, object: nil)
        default:
            if !suggestion.scriptureRefs.isEmpty {
                presentedReader = SelahContextualReaderRequest(
                    references: suggestion.scriptureRefs,
                    sourceFeature: suggestion.feature
                )
            }
        }
        dismiss(suggestion)
    }

    /// User dismissed a suggestion — hide it for the session and start its cooldown.
    func dismiss(_ suggestion: SelahContextualSuggestion) {
        dismissedIds.insert(suggestion.id)
        recordSurfaced(suggestion.feature)
        surfacedSuggestions.removeAll { $0.id == suggestion.id }
        if currentSuggestion?.id == suggestion.id {
            currentSuggestion = surfacedSuggestions.first
        }
    }

    /// Record that a feature was acted on / shown, beginning its cooldown window.
    func recordSurfaced(_ feature: SelahContextualFeature) {
        cooldowns[feature] = Date()
        persistCooldowns()
    }

    // MARK: - Preference setters (persist + re-evaluate is the caller's job via refresh)

    func setFeatureEnabled(_ feature: SelahContextualFeature, _ enabled: Bool) {
        if enabled { preferences.enabledFeatures.insert(feature) }
        else { preferences.enabledFeatures.remove(feature) }
        persistPreferences()
    }

    func setPermissionGranted(_ permission: SelahContextualPermission, _ granted: Bool) {
        if granted { preferences.grantedPermissions.insert(permission) }
        else { preferences.grantedPermissions.remove(permission) }
        persistPreferences()
    }

    func setInterruptTolerance(_ value: Double) {
        preferences.interruptTolerance = min(max(value, 0), 1)
        persistPreferences()
    }

    func setSabbathWeekday(_ weekday: Int?) {
        preferences.chosenSabbathWeekday = weekday
        persistPreferences()
    }

    func setMinimumMinutesBetweenSurfaces(_ minutes: Int) {
        preferences.minimumMinutesBetweenSurfaces = max(0, minutes)
        persistPreferences()
    }

    // MARK: - Persistence

    private func persistPreferences() {
        if let data = try? JSONEncoder().encode(preferences) {
            defaults.set(data, forKey: prefsKey)
        }
    }

    private func persistCooldowns() {
        let raw = Dictionary(uniqueKeysWithValues: cooldowns.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(raw) {
            defaults.set(data, forKey: cooldownKey)
        }
    }

    private static func loadPreferences(defaults: UserDefaults, key: String) -> SelahContextualPreferences {
        guard let data = defaults.data(forKey: key),
              let prefs = try? JSONDecoder().decode(SelahContextualPreferences.self, from: data) else {
            return .default
        }
        return prefs
    }

    private static func loadCooldowns(defaults: UserDefaults, key: String) -> [SelahContextualFeature: Date] {
        guard let data = defaults.data(forKey: key),
              let raw = try? JSONDecoder().decode([String: Date].self, from: data) else {
            return [:]
        }
        var result: [SelahContextualFeature: Date] = [:]
        for (k, v) in raw {
            if let feature = SelahContextualFeature(rawValue: k) { result[feature] = v }
        }
        return result
    }
}
