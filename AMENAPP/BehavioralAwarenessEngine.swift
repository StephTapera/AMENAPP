// BehavioralAwarenessEngine.swift
// AMENAPP
//
// Tracks behavioral signals during a session to detect patterns
// that may indicate distress, crisis-content over-exposure, or
// compulsive/dissociative scrolling.
//
// Architecture:
//   - Entirely local and in-memory — no behavioral data ever leaves the device
//   - Publishes a `SessionSignal` via Combine for SafetyOrchestrator to consume
//   - Resets on each new session (app foreground) to avoid stale signals
//   - All thresholds are conservative by design (many false negatives preferred
//     over false positives that intrude on normal use)
//
// Signals tracked:
//   1. Session duration (prolonged sessions with heavy content)
//   2. Scroll velocity (rapid/frantic scrolling)
//   3. Content exposure (dwell time on distress/crisis content)
//   4. Interaction pattern (no engagement for extended period despite presence)
//   5. Repeated crisis-content return (user keeps scrolling back)

import Foundation
import Combine

// MARK: - Session Signal

/// Aggregated behavioral signal emitted to SafetyOrchestrator.
/// Represents the highest-urgency concern observed so far this session.
enum SessionSignal: CustomStringConvertible {
    case normal                // no concerning pattern detected
    case mildDistress          // mild indicators — awareness only, nothing surfaced
    case repeatedHeavyContent  // user has read multiple high-distress posts
    case distressedScrolling   // rapid/frantic scrolling pattern after heavy content
    case crisisContentDwell    // user dwelled on confirmed crisis-level content
    case elevatedConcern       // multiple concurrent signals at high intensity

    var description: String {
        switch self {
        case .normal:                return "normal"
        case .mildDistress:          return "mild_distress"
        case .repeatedHeavyContent:  return "repeated_heavy_content"
        case .distressedScrolling:   return "distressed_scrolling"
        case .crisisContentDwell:    return "crisis_content_dwell"
        case .elevatedConcern:       return "elevated_concern"
        }
    }

    var urgency: Int {
        switch self {
        case .normal:                return 0
        case .mildDistress:          return 1
        case .repeatedHeavyContent:  return 2
        case .distressedScrolling:   return 2
        case .crisisContentDwell:    return 3
        case .elevatedConcern:       return 4
        }
    }
}

// MARK: - Content Exposure Record

private struct ContentExposureRecord {
    let category: ContentRiskCategory
    let intensity: Double   // 0.0 – 1.0 (actual risk score from ContentRiskAnalyzer)
    let timestamp: Date
    var dwellSeconds: TimeInterval
}

// MARK: - Scroll Sample

private struct ScrollSample {
    let velocity: CGFloat   // points/second (positive = downward)
    let timestamp: Date
}

// MARK: - Engine

/// Behavioral awareness engine — observes session-level signals and
/// publishes an aggregate `SessionSignal` when patterns warrant attention.
@MainActor
final class BehavioralAwarenessEngine: ObservableObject {
    static let shared = BehavioralAwarenessEngine()

    // MARK: - Published

    /// The current aggregate behavioral session signal.
    /// SafetyOrchestrator subscribes to this via Combine.
    @Published private(set) var sessionSignal: SessionSignal = .normal

    // MARK: - Session State

    private var sessionStartTime = Date()
    private var exposureHistory: [ContentExposureRecord] = []
    private var scrollSamples: [ScrollSample] = []
    private var activeContentStart: Date?
    private var activeCategory: ContentRiskCategory = .none
    private var activeContentIntensity: Double = 0.0  // actual score from ContentRiskAnalyzer

    // MARK: - Thresholds (safety-first — tuned to catch genuine distress)

    /// Minimum distress content intensity to record as exposure
    private let minimumRecordableIntensity: Double = 0.25

    /// Number of medium-intensity exposures before "repeatedHeavyContent"
    private let heavyContentRepeatThreshold = 3

    /// Seconds dwelling on crisis-level content before flagging (was 12s)
    private let crisisDwellThreshold: TimeInterval = 7.0

    /// Seconds dwelling on distress content before flagging (was 25s)
    private let distressDwellThreshold: TimeInterval = 15.0

    /// Scroll velocity (pts/sec) considered frantic (was 2800)
    private let franticScrollVelocityThreshold: CGFloat = 2_000

    /// Number of frantic scroll samples (out of last 10) before considering pattern
    private let franticScrollSampleCount = 3

    /// How far back to look for recent exposures (20 minutes)
    private let exposureWindowSeconds: TimeInterval = 1_200

    // MARK: - Init

    private init() {
        beginSession()
    }

    // MARK: - Session Lifecycle

    /// Call when the app enters the foreground.
    func beginSession() {
        sessionStartTime = Date()
        exposureHistory.removeAll()
        scrollSamples.removeAll()
        activeContentStart = nil
        activeCategory = .none
        activeContentIntensity = 0.0
        sessionSignal = .normal
    }

    /// Call when the app enters the background.
    func endSession() {
        flushActiveDwell()
        pruneOldExposures()
    }

    // MARK: - Content Exposure Tracking

    /// Call when a feed item or message with risk content becomes visible.
    /// - Parameters:
    ///   - category: The primary risk category from ContentRiskAnalyzer.quickScan
    ///   - intensity: The risk score (0.0 – 1.0) — stored and used in dwell records
    func noteContentExposure(category: ContentRiskCategory, intensity: Double) {
        guard category != .none, intensity >= minimumRecordableIntensity else { return }

        // Flush any previously active dwell first
        flushActiveDwell()

        // Begin tracking dwell for this new item, preserving the actual intensity
        activeContentStart = Date()
        activeCategory = category
        activeContentIntensity = intensity
    }

    /// Call when a feed item leaves visibility (scroll away, navigation, etc.)
    func noteContentDismissed() {
        flushActiveDwell()
    }

    /// Flush the currently-tracked dwell into the exposure history
    private func flushActiveDwell() {
        guard let start = activeContentStart, activeCategory != .none else { return }
        let dwell = Date().timeIntervalSince(start)
        guard dwell > 1.0 else {
            activeContentStart = nil
            activeCategory = .none
            return
        }

        let record = ContentExposureRecord(
            category: activeCategory,
            intensity: activeContentIntensity,  // use actual score from ContentRiskAnalyzer
            timestamp: start,
            dwellSeconds: dwell
        )
        exposureHistory.append(record)
        activeContentStart = nil
        activeCategory = .none
        activeContentIntensity = 0.0

        pruneOldExposures()
        recomputeSignal()
    }

    // MARK: - Scroll Velocity Tracking

    /// Call from a ScrollView or UIScrollView delegate with the current velocity.
    /// - Parameter velocity: Points per second (positive = scrolling down)
    func noteScrollVelocity(_ velocity: CGFloat) {
        let sample = ScrollSample(velocity: abs(velocity), timestamp: Date())
        scrollSamples.append(sample)

        // Keep only the last 12 samples
        if scrollSamples.count > 12 {
            scrollSamples.removeFirst(scrollSamples.count - 12)
        }

        // Only recompute if scroll pattern is fast (avoid constant recompute on normal scroll)
        if abs(velocity) > franticScrollVelocityThreshold * 0.6 {
            recomputeSignal()
        }
    }

    // MARK: - Manual Signal Elevation

    /// Call when a confirmed crisis keyword is detected in content being read
    /// (e.g. from a prayer request detail view with a known high-risk post).
    func noteDirectCrisisExposure() {
        let record = ContentExposureRecord(
            category: .selfHarmCrisis,
            intensity: 0.85,
            timestamp: Date(),
            dwellSeconds: crisisDwellThreshold + 1 // treat as fully dwelled
        )
        exposureHistory.append(record)
        recomputeSignal()
    }

    // MARK: - Signal Computation

    private func recomputeSignal() {
        pruneOldExposures()

        let recentExposures = exposureHistory.filter {
            Date().timeIntervalSince($0.timestamp) < exposureWindowSeconds
        }

        // ── Crisis content dwell ───────────────────────────────────────────────
        let crisisDwell = recentExposures
            .filter { $0.category == .selfHarmCrisis }
            .map { $0.dwellSeconds }
            .reduce(0, +)

        if crisisDwell >= crisisDwellThreshold {
            elevateSignal(.crisisContentDwell)
            return
        }

        // ── Multiple concurrent signals (elevated concern) ────────────────────
        let hasMultipleCrisis = recentExposures.filter { $0.category == .selfHarmCrisis }.count >= 2
        let hasViolence = recentExposures.filter { $0.category == .violenceThreat }.count >= 2
        let hasDistress = recentExposures.filter { $0.category == .emotionalDistress }.count >= 3

        if (hasMultipleCrisis && hasDistress) || (hasViolence && hasDistress && hasMultipleCrisis) {
            elevateSignal(.elevatedConcern)
            return
        }

        // ── Frantic scrolling after heavy content ─────────────────────────────
        if hasFranticScrollingPattern() && !recentExposures.isEmpty {
            elevateSignal(.distressedScrolling)
            return
        }

        // ── Repeated heavy content exposure ───────────────────────────────────
        let heavyExposureCount = recentExposures.filter {
            ($0.category == .selfHarmCrisis || $0.category == .emotionalDistress)
        }.count

        if heavyExposureCount >= heavyContentRepeatThreshold {
            elevateSignal(.repeatedHeavyContent)
            return
        }

        // ── Mild signals ──────────────────────────────────────────────────────
        let distressDwell = recentExposures
            .filter { $0.category == .emotionalDistress }
            .map { $0.dwellSeconds }
            .reduce(0, +)

        if distressDwell >= distressDwellThreshold || heavyExposureCount >= 2 {
            elevateSignal(.mildDistress)
            return
        }

        // All clear — only downgrade if we haven't already gone higher
        if sessionSignal == .normal || sessionSignal == .mildDistress {
            sessionSignal = .normal
        }
    }

    /// Elevates the signal (never lowers within a session — use beginSession() to reset)
    private func elevateSignal(_ signal: SessionSignal) {
        if signal.urgency > sessionSignal.urgency {
            sessionSignal = signal
        }
    }

    private func hasFranticScrollingPattern() -> Bool {
        let recent = scrollSamples.filter {
            Date().timeIntervalSince($0.timestamp) < 8.0
        }
        guard recent.count >= franticScrollSampleCount else { return false }
        let franticCount = recent.filter { $0.velocity > franticScrollVelocityThreshold }.count
        return franticCount >= franticScrollSampleCount
    }

    private func pruneOldExposures() {
        let cutoff = Date().addingTimeInterval(-exposureWindowSeconds)
        exposureHistory.removeAll { $0.timestamp < cutoff }
    }

    // MARK: - Session Stats (for debug / moderator context)

    var sessionDuration: TimeInterval {
        Date().timeIntervalSince(sessionStartTime)
    }

    var recentExposureCount: Int {
        exposureHistory.filter {
            Date().timeIntervalSince($0.timestamp) < exposureWindowSeconds
        }.count
    }

    var crisisExposureCount: Int {
        exposureHistory.filter {
            $0.category == .selfHarmCrisis &&
            Date().timeIntervalSince($0.timestamp) < exposureWindowSeconds
        }.count
    }
}
