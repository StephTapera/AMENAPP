import Foundation
import UIKit

// MARK: - Selah Contextual Signal Provider
// Assembles a `SelahContextualInput` from on-device, mic-free signals. The provider
// never decides whether to surface — it only reports confidence. The evaluator's
// permission / Sabbath / cooldown / confidence gates make the final call.
//
// The genuinely mic-free signals are wired live here: liturgical season, reflection
// follow-up, rest/session load, and intentional clipboard scripture catch. Heavier
// signals (calendar, location, motion, photos, health, screen-time, social graph)
// require their own consented detectors; this provider exposes an injection point
// (`externalConfidences`) so those detectors can push confidence without this type
// reaching into every framework. Until they do, those features report 0 → the
// evaluator silently suppresses them (`.noRelevantSignal`).

@MainActor
struct SelahContextualSignalProvider {

    /// A lightweight, reusable scripture-reference detector (regex, 66 book aliases).
    private let scriptureDetector = ChurchNotesScriptureDetector.shared

    /// Build the evaluator input from currently-readable signals.
    ///
    /// - Parameters:
    ///   - now: evaluation timestamp.
    ///   - calendar: calendar used for season / quiet-hours math.
    ///   - sessionDurationSeconds: foreground session length (for rest / doomscroll cues).
    ///   - mediaViewedCount: items viewed this session (rest cue).
    ///   - highLoadContentFraction: fraction of heavy content this session (rest cue).
    ///   - recentReflectionText: the user's most recent reflection (reflection-to-action loop).
    ///   - recentScriptureRefs: refs tied to that reflection, if any.
    ///   - clipboardScriptureRefs: refs detected from an *intentional* clipboard scan (see `scanClipboardForScripture`).
    ///   - externalConfidences: confidences pushed by consented heavier detectors (calendar/location/etc).
    func buildInput(
        now: Date,
        calendar: Calendar = .current,
        sessionDurationSeconds: TimeInterval = 0,
        mediaViewedCount: Int = 0,
        highLoadContentFraction: Double = 0,
        recentReflectionText: String? = nil,
        recentScriptureRefs: [String] = [],
        clipboardScriptureRefs: [String] = [],
        externalConfidences: [SelahContextualFeature: Double] = [:]
    ) -> SelahContextualInput {

        var confidences: [SelahContextualFeature: Double] = externalConfidences

        // Liturgical season (date-only, no permission). The evaluator recomputes the
        // season itself; seeding a confidence lets tolerance gating apply uniformly.
        let season = SelahContextualIntelligenceService.shared.liturgicalSeason(for: now, calendar: calendar)
        if season != .ordinaryTime {
            confidences[.liturgicalLayer] = max(confidences[.liturgicalLayer] ?? 0, 0.82)
        }

        // Intentional clipboard scripture catch (Cluster 3, feature 9). Confidence only
        // when an actual reference was found by the caller's explicit scan.
        if !clipboardScriptureRefs.isEmpty {
            confidences[.copiedVerseCatch] = max(confidences[.copiedVerseCatch] ?? 0, 0.9)
        }

        return SelahContextualInput(
            now: now,
            calendar: calendar,
            signalConfidenceByFeature: confidences,
            recentReflectionText: recentReflectionText,
            recentScriptureRefs: recentScriptureRefs,
            sessionDurationSeconds: sessionDurationSeconds,
            mediaViewedCount: mediaViewedCount,
            highLoadContentFraction: highLoadContentFraction
        )
    }

    /// Intentional, foreground, ephemeral clipboard scan for scripture references.
    ///
    /// Reading the pasteboard string surfaces iOS's transient paste banner — that banner
    /// IS the intentionality signal, so this must only be called in direct response to a
    /// foreground transition or user gesture, and only when the `copiedVerseCatch` feature
    /// and its permission are granted. Returns the detected reference strings (never the
    /// raw clipboard text), deduplicated.
    func scanClipboardForScripture() -> [String] {
        guard UIPasteboard.general.hasStrings, let text = UIPasteboard.general.string else { return [] }
        // Cap the scanned length so a giant clipboard can't stall the regex.
        let bounded = String(text.prefix(2000))
        return scriptureDetector.detectReferenceStrings(in: bounded)
    }
}
