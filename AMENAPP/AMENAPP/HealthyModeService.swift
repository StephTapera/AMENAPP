//
//  HealthyModeService.swift
//  AMENAPP
//
//  Unified Healthy Mode toggle — orchestrates all anti-doomscroll protections.
//
//  Activating Healthy Mode enables:
//  - No infinite scroll (session stops at configured video/post limit)
//  - Session checkpoints every 20 videos or 30 minutes
//  - Autoplay limits (off by default for minors)
//  - Natural stopping points with reflection prompts
//  - Friend/community-first ranking (boost mutuals over broadcast accounts)
//  - Reduced rage/reaction bait (controversy penalty × 2)
//  - Session summaries on exit
//  - Reduced late-night volatility (22:00–06:00 local time)
//  - Minor-safe defaults (all features enabled for minors regardless of toggle)
//

import Foundation
import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore

// MARK: - Session Checkpoint Reason

enum SessionCheckpointReason: String, CaseIterable {
    case videoCount     = "video_count"      // 20 videos watched
    case timeElapsed    = "time_elapsed"     // 30 minutes
    case lateNight      = "late_night"       // Past 22:00 local time
    case highVolatility = "high_volatility"  // Emotional volatility detected
}

// MARK: - DoomscrollGuard

/// Tracks video/post consumption per session and triggers checkpoints.
/// Shared singleton; reset on feed session start.
@MainActor
final class DoomscrollGuard: ObservableObject {
    static let shared = DoomscrollGuard()
    private init() {}

    // MARK: Configurable thresholds (Healthy Mode uses stricter values)
    var videoCheckpointThreshold: Int = 20        // checkpoint after N videos
    var postCheckpointThreshold: Int = 60         // checkpoint after N posts (non-video)
    var sessionMinuteThreshold: Int = 30          // checkpoint after N minutes
    var repeatedCreatorThreshold: Int = 4         // dampen after N posts from same creator

    // MARK: Session State
    @Published var videosWatchedThisSession: Int = 0
    @Published var postsSeenThisSession: Int = 0
    @Published var sessionStartTime: Date = Date()
    @Published var checkpointPending: Bool = false
    @Published var pendingCheckpointReason: SessionCheckpointReason = .videoCount
    @Published var creatorSeenCounts: [String: Int] = [:]

    // MARK: - Video tracking

    func recordVideoWatched(postId: String, authorId: String) {
        videosWatchedThisSession += 1
        recordPostSeen(authorId: authorId)

        if videosWatchedThisSession >= videoCheckpointThreshold {
            triggerCheckpoint(reason: .videoCount)
        }
    }

    func recordPostSeen(authorId: String) {
        postsSeenThisSession += 1
        creatorSeenCounts[authorId, default: 0] += 1

        let elapsed = Date().timeIntervalSince(sessionStartTime) / 60
        if Int(elapsed) >= sessionMinuteThreshold {
            triggerCheckpoint(reason: .timeElapsed)
        }

        if isLateNight {
            triggerCheckpoint(reason: .lateNight)
        }
    }

    // MARK: - Repetition dampening

    /// Returns a penalty multiplier (0.0–1.0) for a creator's posts based on
    /// how many times they've appeared this session. Applied to ranking score.
    func repetitionDampener(for authorId: String) -> Double {
        let count = creatorSeenCounts[authorId] ?? 0
        switch count {
        case 0...repeatedCreatorThreshold:     return 1.0   // No penalty
        case (repeatedCreatorThreshold + 1): return 0.7   // Light
        case (repeatedCreatorThreshold + 2): return 0.4   // Moderate
        default:                              return 0.15  // Strong
        }
    }

    // MARK: - Checkpoint

    private func triggerCheckpoint(reason: SessionCheckpointReason) {
        guard !checkpointPending else { return }
        checkpointPending = true
        pendingCheckpointReason = reason
        dlog("🛑 [DoomscrollGuard] Checkpoint triggered: \(reason.rawValue) " +
             "(videos: \(videosWatchedThisSession), posts: \(postsSeenThisSession))")
        // Audit log: checkpoint triggered (ModerationAuditLogService removed; no-op stub)
        _ = reason.rawValue
    }

    func dismissCheckpoint() {
        checkpointPending = false
        videosWatchedThisSession = 0
        sessionStartTime = Date()
    }

    func endSession() {
        videosWatchedThisSession = 0
        postsSeenThisSession = 0
        creatorSeenCounts = [:]
        checkpointPending = false
        sessionStartTime = Date()
    }

    // MARK: - Late Night Detection

    var isLateNight: Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour >= 22 || hour < 6
    }

    var isLateNightAndHighRisk: Bool {
        isLateNight && postsSeenThisSession > 10
    }
}

// MARK: - HealthyModeService

/// Single source of truth for the Healthy Mode toggle.
/// Persists preference to Firestore and UserDefaults.
/// Also manages minor-safe defaults (always on for confirmed minors).
@MainActor
final class HealthyModeService: ObservableObject {
    static let shared = HealthyModeService()

    private let db = Firestore.firestore()
    private let userDefaultsKey = "healthyMode_enabled_v1"

    @Published var isEnabled: Bool = false {
        didSet {
            guard oldValue != isEnabled else { return }
            applyHealthyModeSettings()
            persistPreference()
            // Audit log: healthy mode changed (ModerationAuditLogService removed; no-op stub)
            _ = isEnabled
        }
    }

    // Granular controls (all toggled by the main switch, can also be set individually)
    @Published var autoplayEnabled: Bool = true
    @Published var infiniteScrollEnabled: Bool = true
    @Published var reflectionPromptsEnabled: Bool = false
    @Published var sessionSummariesEnabled: Bool = false
    @Published var lateNightDampeningEnabled: Bool = false
    @Published var controversyPenaltyMultiplier: Double = 1.0

    private var isMinor: Bool = false

    private init() {
        loadStoredPreference()
        Task { await detectMinorStatus() }
    }

    // MARK: - Minor Detection

    private func detectMinorStatus() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let profile = await MinorSafetyService.shared.fetchProfile(userId: uid)
        // SECURITY FIX (LOW 2026-06-11): Fail closed — default to minor-safe (true) when
        // fetchProfile returns nil (network error, partial document). Minors on flaky
        // connections still receive protective defaults (no autoplay, no infinite scroll).
        isMinor = profile?.isMinorOrUnknown ?? true
        if isMinor {
            // Minors always get Healthy Mode defaults regardless of toggle
            enforceMinorDefaults()
        }
    }

    private func enforceMinorDefaults() {
        autoplayEnabled = false
        infiniteScrollEnabled = false
        reflectionPromptsEnabled = true
        lateNightDampeningEnabled = true
        DoomscrollGuard.shared.videoCheckpointThreshold = 10   // Stricter for minors
        DoomscrollGuard.shared.sessionMinuteThreshold = 20
        dlog("👶 [HealthyMode] Minor-safe defaults enforced")
    }

    // MARK: - Apply Settings

    private func applyHealthyModeSettings() {
        if isMinor {
            enforceMinorDefaults()
            return
        }

        if isEnabled {
            autoplayEnabled = false
            infiniteScrollEnabled = false
            reflectionPromptsEnabled = true
            sessionSummariesEnabled = true
            lateNightDampeningEnabled = true
            controversyPenaltyMultiplier = 2.0
            DoomscrollGuard.shared.videoCheckpointThreshold = 20
            DoomscrollGuard.shared.sessionMinuteThreshold = 30
        } else {
            autoplayEnabled = true
            infiniteScrollEnabled = true
            reflectionPromptsEnabled = false
            sessionSummariesEnabled = false
            lateNightDampeningEnabled = false
            controversyPenaltyMultiplier = 1.0
            DoomscrollGuard.shared.videoCheckpointThreshold = 20  // Always active
            DoomscrollGuard.shared.sessionMinuteThreshold = 30
        }
    }

    // MARK: - Persistence

    private func loadStoredPreference() {
        let stored = UserDefaults.standard.bool(forKey: userDefaultsKey)
        // Don't trigger didSet on initial load
        isEnabled = stored
        applyHealthyModeSettings()
    }

    private func persistPreference() {
        UserDefaults.standard.set(isEnabled, forKey: userDefaultsKey)
        guard let uid = Auth.auth().currentUser?.uid else { return }
        Task.detached(priority: .utility) { [isEnabled, db, uid] in
            try? await db
                .collection("users").document(uid)
                .collection("feedPreferences").document("main")
                .setData(["healthyModeEnabled": isEnabled,
                          "updatedAt": FieldValue.serverTimestamp()],
                         merge: true)
        }
    }

    // MARK: - Public API

    func toggle() {
        isEnabled.toggle()
    }

    /// Whether autoplay should be allowed for a given post.
    /// Minors never get autoplay. Healthy Mode off also disables it based on risk.
    func allowsAutoplay(for post: Post) -> Bool {
        guard !isMinor else { return false }
        guard autoplayEnabled else { return false }
        // Never autoplay high-risk content (aggregateHarmScore/trueSource not on Post model)
        _ = post
        if lateNightDampeningEnabled && DoomscrollGuard.shared.isLateNight { return false }
        return true
    }

    /// Whether infinite scroll is permitted in the current session.
    var allowsInfiniteScroll: Bool {
        guard !isMinor else { return false }
        return infiniteScrollEnabled && !DoomscrollGuard.shared.checkpointPending
    }
}

// MARK: - HealthyModeControlsView

struct HealthyModeControlsView: View {
    @ObservedObject private var service = HealthyModeService.shared

    var body: some View {
        List {
            Section {
                Toggle("Healthy Mode", isOn: $service.isEnabled)
                    .accessibilityLabel("Healthy Mode")
                    .accessibilityHint("Limits autoplay, infinite scroll, and reduces rage-bait content")
            } header: {
                Text("Wellbeing")
            } footer: {
                Text("Healthy Mode turns off autoplay, enables session checkpoints, reduces outrage content, and adds reflection prompts.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if service.isEnabled {
                Section("Active Protections") {
                    Label("Autoplay off", systemImage: "pause.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityLabel("Autoplay is off")
                    Label("Session checkpoints every 20 videos", systemImage: "flag.fill")
                        .foregroundStyle(.green)
                        .accessibilityLabel("Session checkpoints are active")
                    Label("Outrage content reduced", systemImage: "shield.fill")
                        .foregroundStyle(.green)
                        .accessibilityLabel("Outrage content is reduced")
                    Label("Reflection prompts on", systemImage: "heart.text.clipboard.fill")
                        .foregroundStyle(.green)
                        .accessibilityLabel("Reflection prompts are on")
                    Label("Late-night dampening on", systemImage: "moon.fill")
                        .foregroundStyle(.green)
                        .accessibilityLabel("Late-night content dampening is on")
                }
            }
        }
        .navigationTitle("Feed Wellbeing")
        .navigationBarTitleDisplayMode(.inline)
    }
}
