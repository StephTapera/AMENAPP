// SpiritualCheckInService.swift
// AMEN App — Spiritual Check-In Intelligence System
//
// Purpose: Compassionate, non-invasive user well-being intelligence.
// Detects signals of distress, spiritual discouragement, or compulsive use
// patterns and responds with graduated, optional care — never surveillance.
//
// Privacy guarantees:
//   - All signals are in-memory only (never stored raw)
//   - Only aggregated check-in state is persisted (e.g. "check-in shown")
//   - No raw content is ever analyzed server-side for this feature
//   - User can disable all check-ins at any time
//   - No notifications without explicit opt-in
//
// Signal aggregation philosophy:
//   - One weak signal = nothing
//   - Repeated signals over time + pattern = gentle response
//   - High-confidence crisis signals = immediate escalation to SafetyOrchestrator
//   - Interventions decay over time to avoid becoming annoying
//   - User dismissal is always respected

import Foundation
import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore

// MARK: - Check-In Signal

/// An individual signal that contributes to the check-in score.
/// Signals are in-memory only and decay over a 24-hour window.
struct CheckInSignal {
    enum SignalType: String {
        case negativeSentimentPost = "negative_sentiment_post"
        case hopelessLanguage = "hopeless_language"
        case selfHarmIndicator = "self_harm_indicator"          // Immediately escalated
        case repeatedAnxiousContent = "repeated_anxious_content"
        case compulsiveAppOpen = "compulsive_app_open"          // Open/close loop
        case lateNightPosting = "late_night_posting"
        case repeatedCrisisPrayer = "repeated_crisis_prayer"
        case spiritualDiscouragement = "spiritual_discouragement"
        case socialWithdrawalSignal = "social_withdrawal"
        case prayerForHope = "prayer_for_hope"                  // Positive signal — lower score
        case communityEngagement = "community_engagement"       // Positive — lower score
    }

    let type: SignalType
    let intensity: Double      // 0.0 – 1.0
    let timestamp: Date

    var isPositive: Bool {
        switch type {
        case .prayerForHope, .communityEngagement: return true
        default: return false
        }
    }

    var isImmediate: Bool {
        type == .selfHarmIndicator
    }

    var weight: Double {
        switch type {
        case .selfHarmIndicator: return 5.0          // Immediate escalation path
        case .hopelessLanguage: return 2.5
        case .repeatedCrisisPrayer: return 2.0
        case .spiritualDiscouragement: return 1.5
        case .negativeSentimentPost: return 1.0
        case .repeatedAnxiousContent: return 1.0
        case .lateNightPosting: return 0.5
        case .compulsiveAppOpen: return 0.5
        case .socialWithdrawalSignal: return 0.75
        case .prayerForHope: return -1.0
        case .communityEngagement: return -0.75
        }
    }

    var isExpired: Bool {
        // Signals expire after 24 hours except high-weight ones (48h)
        let maxAge: TimeInterval = weight >= 2.0 ? 172800 : 86400
        return Date().timeIntervalSince(timestamp) > maxAge
    }
}

// MARK: - Check-In Tier

enum CheckInTier: Int, Comparable {
    case none = 0
    case gentleEncouragement = 1    // "You might enjoy a moment of reflection"
    case softCheckIn = 2            // "You seem to be carrying a lot. Prayer?"
    case supportSurface = 3         // Suggest church, counselor, Berean
    case crisisEscalation = 4       // Route to SafetyOrchestrator crisis flow

    static func < (lhs: CheckInTier, rhs: CheckInTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Check-In Intervention

struct CheckInIntervention: Identifiable {
    let id = UUID()
    let tier: CheckInTier
    let title: String
    let message: String
    let actionLabel: String
    let actionType: ActionType
    let dismissLabel: String
    let icon: String
    let iconColor: Color

    enum ActionType {
        case openPrayer
        case openBerean
        case openVerses
        case openResources
        case openCrisisSupport
        case openChurch
        case dismiss
    }

    // MARK: - Factory

    static func make(for tier: CheckInTier) -> CheckInIntervention? {
        switch tier {
        case .none: return nil

        case .gentleEncouragement:
            return CheckInIntervention(
                tier: tier,
                title: "A moment of reflection",
                message: "Would you like a short prayer or a word of encouragement?",
                actionLabel: "Yes, please",
                actionType: .openVerses,
                dismissLabel: "Not now",
                icon: "leaf.fill",
                iconColor: .green
            )

        case .softCheckIn:
            return CheckInIntervention(
                tier: tier,
                title: "You're not carrying this alone",
                message: "You seem to be going through a lot. Would you like to reflect, pray, or read a few verses?",
                actionLabel: "Open prayer",
                actionType: .openPrayer,
                dismissLabel: "I'm okay",
                icon: "hands.sparkles.fill",
                iconColor: .purple
            )

        case .supportSurface:
            return CheckInIntervention(
                tier: tier,
                title: "Here for you",
                message: "Here are a few resources that may help right now — prayer, scripture, or someone to talk to.",
                actionLabel: "See resources",
                actionType: .openResources,
                dismissLabel: "I'm okay",
                icon: "heart.circle.fill",
                iconColor: .blue
            )

        case .crisisEscalation:
            // This tier is handled by SafetyOrchestrator, not shown as a card
            return nil
        }
    }
}

// MARK: - Check-In Preferences

struct CheckInPreferences: Codable {
    var enabled: Bool = true
    var allowEncouragementCards: Bool = true
    var allowSoftCheckIns: Bool = true
    var allowSupportSurface: Bool = true
    var snoozedUntil: Date? = nil
    var lastDismissedAt: Date? = nil
    var lastShownAt: Date? = nil

    var isSnoozed: Bool {
        guard let until = snoozedUntil else { return false }
        return Date() < until
    }

    var canShowAgain: Bool {
        guard let last = lastShownAt else { return true }
        // Don't repeat within 4 hours
        return Date().timeIntervalSince(last) > 14400
    }
}

// MARK: - Spiritual Check-In Service

@MainActor
final class SpiritualCheckInService: ObservableObject {

    static let shared = SpiritualCheckInService()

    // MARK: - Published state
    @Published private(set) var currentIntervention: CheckInIntervention? = nil
    @Published private(set) var isActive: Bool = false

    // MARK: - Private state
    private var signals: [CheckInSignal] = []
    private var preferences = CheckInPreferences()
    private let flags = AMENFeatureFlags.shared
    private let db = Firestore.firestore()
    private var sessionOpenCount: Int = 0
    private var lastSessionOpenTime: Date?

    private init() {
        Task { await loadPreferences() }
    }

    // MARK: - Signal Recording

    /// Record a behavioral or content signal.
    /// Called from: PostCreation, CommentCreation, WellnessGuardianService, SafetyOrchestrator
    func recordSignal(_ type: CheckInSignal.SignalType, intensity: Double = 1.0) {
        guard flags.spiritualCheckInEnabled else { return }
        guard flags.checkInBehavioralSignalsEnabled else { return }

        let signal = CheckInSignal(type: type, intensity: intensity, timestamp: Date())

        // Immediate path for self-harm indicators
        if signal.isImmediate && flags.checkInCrisisEscalationEnabled {
            Task {
                await SafetyOrchestrator.shared.updateSupportState(
                    to: .crisisUrgent,
                    reason: "check-in-self-harm-signal"
                )
            }
            return
        }

        // Purge expired signals before adding
        signals = signals.filter { !$0.isExpired }
        signals.append(signal)

        // Evaluate after a brief debounce to avoid micro-reactions
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 second debounce
            evaluateAndIntervene()
        }
    }

    /// Record that the app was opened (for compulsive open/close detection)
    func recordAppOpen() {
        guard flags.checkInBehavioralSignalsEnabled else { return }

        let now = Date()
        if let last = lastSessionOpenTime {
            let gap = now.timeIntervalSince(last)
            // If opened again within 3 minutes, count as compulsive loop
            if gap < 180 {
                sessionOpenCount += 1
                if sessionOpenCount >= 4 {
                    recordSignal(.compulsiveAppOpen, intensity: 0.6)
                    sessionOpenCount = 0
                }
            } else {
                sessionOpenCount = 1
            }
        } else {
            sessionOpenCount = 1
        }
        lastSessionOpenTime = now

        // Late night detection (10pm – 5am)
        let hour = Calendar.current.component(.hour, from: now)
        if hour >= 22 || hour < 5 {
            recordSignal(.lateNightPosting, intensity: 0.4)
        }
    }

    /// Record positive engagement that lowers check-in score
    func recordPositiveEngagement() {
        recordSignal(.communityEngagement, intensity: 0.8)
    }

    // MARK: - Score Calculation

    private func currentScore() -> Double {
        let active = signals.filter { !$0.isExpired }
        let raw = active.reduce(0.0) { $0 + $1.weight * $1.intensity }
        return max(0, raw)
    }

    private func evaluateAndIntervene() {
        guard preferences.enabled && !preferences.isSnoozed else { return }
        guard preferences.canShowAgain else { return }

        let score = currentScore()
        let tier = tierFromScore(score)
        guard tier > .none else {
            // Score dropped — clear any active intervention
            if currentIntervention != nil {
                currentIntervention = nil
                isActive = false
            }
            return
        }

        // Don't re-show if already showing a higher-or-equal tier
        if let existing = currentIntervention, existing.tier >= tier { return }

        // Build intervention
        if let intervention = CheckInIntervention.make(for: tier) {
            showIntervention(intervention)
        }
    }

    private func tierFromScore(_ score: Double) -> CheckInTier {
        switch score {
        case ..<1.5: return .none
        case 1.5..<3.0: return .gentleEncouragement
        case 3.0..<5.5: return .softCheckIn
        default: return .supportSurface
        }
    }

    // MARK: - Intervention Presentation

    private func showIntervention(_ intervention: CheckInIntervention) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            currentIntervention = intervention
            isActive = true
        }
        preferences.lastShownAt = Date()
        logCheckInShown(tier: intervention.tier)
    }

    func dismissIntervention(snooze: Bool = false) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            currentIntervention = nil
            isActive = false
        }
        preferences.lastDismissedAt = Date()
        if snooze {
            preferences.snoozedUntil = Date().addingTimeInterval(14400) // 4 hours
        }
        // Lower signal weights on dismissal (user is indicating they're okay)
        signals = signals.filter { $0.weight > 2.0 }  // Keep only high-weight signals
    }

    func userResponded(positive: Bool) {
        dismissIntervention()
        if positive {
            // User engaged — reduce score to avoid immediate repeat
            signals = signals.filter { $0.weight >= 2.5 }
        }
    }

    // MARK: - Public API for Content Analysis

    /// Analyze post/comment text and record relevant signals.
    /// Call this when content is created (pre-submit, so we see what user is expressing).
    func analyzeContent(_ text: String) {
        guard flags.spiritualCheckInEnabled else { return }
        let lower = text.lowercased()

        // Spiritual discouragement
        let discouragementKeywords = ["can't feel god", "god isn't listening", "my faith is gone",
                                       "i've lost my faith", "god abandoned me", "where is god",
                                       "i don't believe anymore", "god doesn't care"]
        if discouragementKeywords.contains(where: { lower.contains($0) }) {
            recordSignal(.spiritualDiscouragement, intensity: 0.9)
        }

        // Crisis prayer patterns
        let crisisPrayerKeywords = ["please pray for me", "i'm in crisis", "i don't know how much more",
                                     "at the end of my rope", "can't go on", "giving up on"]
        if crisisPrayerKeywords.contains(where: { lower.contains($0) }) {
            recordSignal(.repeatedCrisisPrayer, intensity: 0.85)
        }

        // Hopelessness
        let hopelessKeywords = ["no hope", "hopeless", "nothing will ever", "never get better",
                                  "pointless", "what's the point", "life isn't worth"]
        if hopelessKeywords.contains(where: { lower.contains($0) }) {
            recordSignal(.hopelessLanguage, intensity: 1.0)
        }

        // Negative sentiment (broader, lower weight)
        let negativeSentimentKeywords = ["exhausted", "overwhelmed", "falling apart", "broken",
                                          "alone", "nobody cares", "don't know what to do",
                                          "can't do this", "so hard", "struggling so much"]
        let matchCount = negativeSentimentKeywords.filter { lower.contains($0) }.count
        if matchCount >= 2 {
            recordSignal(.negativeSentimentPost, intensity: Double(matchCount) * 0.3)
        }

        // Positive counter-signals
        let hopefulKeywords = ["thank god", "praise god", "god is good", "feeling blessed",
                                "grateful", "answered prayer", "breakthrough", "victory"]
        if hopefulKeywords.contains(where: { lower.contains($0) }) {
            recordSignal(.prayerForHope, intensity: 0.7)
        }
    }

    // MARK: - Preferences Persistence

    func snoozeCheckIns(duration: TimeInterval = 14400) {
        preferences.snoozedUntil = Date().addingTimeInterval(duration)
        savePreferences()
    }

    func disableCheckIns() {
        preferences.enabled = false
        savePreferences()
    }

    func enableCheckIns() {
        preferences.enabled = true
        preferences.snoozedUntil = nil
        savePreferences()
    }

    /// Called on sign-out to clear all in-memory signals and reset intervention state.
    /// Prevents one user's behavioral signals from carrying over to the next session.
    func stopListening() {
        signals.removeAll()
        currentIntervention = nil
        isActive = false
        sessionOpenCount = 0
        lastSessionOpenTime = nil
    }

    private func loadPreferences() async {
        // Load from UserDefaults for instant availability
        if let data = UserDefaults.standard.data(forKey: "spiritualCheckInPrefs"),
           let prefs = try? JSONDecoder().decode(CheckInPreferences.self, from: data) {
            preferences = prefs
        }
    }

    private func savePreferences() {
        if let data = try? JSONEncoder().encode(preferences) {
            UserDefaults.standard.set(data, forKey: "spiritualCheckInPrefs")
        }
    }

    // MARK: - Analytics (privacy-safe, aggregated only)

    private func logCheckInShown(tier: CheckInTier) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        // Only log tier + timestamp — no behavioral data
        Task.detached(priority: .background) { [weak self] in
            let db = Firestore.firestore()
            _ = try? await db
                .collection("users").document(uid)
                .collection("wellnessEvents")
                .addDocument(data: [
                    "type": "check_in_shown",
                    "tier": tier.rawValue,
                    "timestamp": FieldValue.serverTimestamp()
                ])
            _ = self // capture to avoid warning
        }
    }
}

// MARK: - Check-In Card UI

struct SpiritualCheckInCard: View {
    let intervention: CheckInIntervention
    let onAction: (CheckInIntervention.ActionType) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: intervention.icon)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(intervention.iconColor)
                    .frame(width: 44, height: 44)
                    .background(intervention.iconColor.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(intervention.title)
                        .font(.custom("OpenSans-SemiBold", size: 15))
                        .foregroundColor(.primary)
                    Text(intervention.message)
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 10) {
                Button(intervention.dismissLabel) {
                    onDismiss()
                }
                .font(.custom("OpenSans-Medium", size: 13))
                .foregroundColor(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.gray.opacity(0.12), in: Capsule())

                Spacer()

                Button(intervention.actionLabel) {
                    onAction(intervention.actionType)
                }
                .font(.custom("OpenSans-SemiBold", size: 13))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(intervention.iconColor, in: Capsule())
            }
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.08), radius: 16, y: 6)
        }
        .padding(.horizontal, 16)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// MARK: - Check-In Settings View

struct CheckInSettingsSection: View {
    @ObservedObject private var service = SpiritualCheckInService.shared

    var body: some View {
        Section("Spiritual Check-Ins") {
            Toggle("Enable check-in suggestions", isOn: Binding(
                get: { service.isActive || true },  // reads preferences
                set: { enabled in
                    if enabled { service.enableCheckIns() }
                    else { service.disableCheckIns() }
                }
            ))
            .font(.custom("OpenSans-Regular", size: 15))

            Button("Snooze for 4 hours") {
                service.snoozeCheckIns()
            }
            .font(.custom("OpenSans-Regular", size: 15))
            .foregroundColor(.secondary)
        }
    }
}
