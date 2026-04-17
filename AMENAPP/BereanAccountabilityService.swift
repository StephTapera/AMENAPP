// BereanAccountabilityService.swift
// AMENAPP
//
// Opt-in behavioral accountability. Tracks patterns, not content.
// Privacy-safe: only signals stored, never raw messages.

import Foundation
import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore

// MARK: - Accountability Profile

struct AccountabilityProfile: Codable {
    var isEnabled: Bool = false
    var hasPartner: Bool = false
    var partnerUID: String? = nil

    // Time guards
    var dmCurfewEnabled: Bool = false
    var dmCurfewHour: Int = 23      // no DMs after 11 pm

    // Behavioral signals (counts, not content)
    var lateNightDMCount: Int = 0
    var flaggedConversationCount: Int = 0
    var cooldownBypassedCount: Int = 0
    var conflictEscalationCount: Int = 0
    var consistencyStreak: Int = 0          // days without flagged behavior
    var lastResetDate: Date = Date()

    // Growth metrics
    var reflectionDepthScore: Double = 0    // based on church note engagement
    var obedienceActionCount: Int = 0       // actions completed from BereanActionEngine
    var prayerConsistencyDays: Int = 0

    // Struggled areas (user-labeled, not AI-detected without consent)
    var trackedAreas: Set<StruggleArea> = []

    enum StruggleArea: String, Codable, CaseIterable {
        case lust, anger, pride, isolation, anxiety, doubt, addiction, bitterness

        var displayName: String { rawValue.capitalized }

        var icon: String {
            switch self {
            case .lust:       return "flame"
            case .anger:      return "bolt.fill"
            case .pride:      return "crown"
            case .isolation:  return "person.slash"
            case .anxiety:    return "waveform.path"
            case .doubt:      return "questionmark.circle"
            case .addiction:  return "circle.dotted"
            case .bitterness: return "xmark.circle"
            }
        }
    }
}

// MARK: - Accountability Insight

struct AccountabilityInsight: Identifiable {
    let id = UUID()
    let type: InsightType
    let message: String
    let options: [InsightOption]
    let createdAt: Date

    enum InsightType { case pattern, encouragement, warning, milestone }

    struct InsightOption: Identifiable {
        let id = UUID()
        let title: String
        let action: InsightAction

        enum InsightAction {
            case setTimeGuard
            case addPartner
            case openReflection
            case dismiss
            case openChurchNotes
        }
    }
}

// MARK: - Accountability Signal

enum AccountabilitySignal {
    case lateNightDM           // DM started after 10 pm
    case flaggedConversation   // safety system flagged this conversation
    case cooldownBypassed      // user bypassed a suggested cooldown
    case conflictEscalation    // argument detection triggered
    case positiveInteraction   // encouraging/prayer-focused message
    case prayerActivity        // user engaged with prayer
    case churchNoteCreated     // engagement with spiritual content
}

// MARK: - Weekly Reflection Card

struct WeeklyReflectionCard: Identifiable {
    let id = UUID()
    let consistencyStreak: Int
    let purityScore: Double       // 0–100 based on absence of flagged behavior
    let patienceScore: Double     // 0–100 based on conflict avoidance
    let disciplineScore: Double   // 0–100 based on action completion + growth engagement
    let encouragementMessage: String
    let topGrowthArea: String
    let weekStartDate: Date
}

// MARK: - Service

@MainActor
final class BereanAccountabilityService: ObservableObject {

    static let shared = BereanAccountabilityService()

    @Published var profile: AccountabilityProfile = AccountabilityProfile()
    @Published var pendingInsight: AccountabilityInsight? = nil
    @Published var weeklyReflectionCard: WeeklyReflectionCard? = nil
    @Published var isLoaded: Bool = false

    private lazy var db = Firestore.firestore()
    private var listener: ListenerRegistration?

    // Firestore: users/{uid}/bereanAccountability/profile
    private func profileRef(uid: String) -> DocumentReference {
        db.collection("users").document(uid)
          .collection("bereanAccountability").document("profile")
    }

    private init() {}

    // MARK: - Lifecycle

    func startListening() {
        guard let uid = Auth.auth().currentUser?.uid else {
            dlog("[BereanAccountability] No authenticated user")
            return
        }
        listener = profileRef(uid: uid).addSnapshotListener { [weak self] snapshot, error in
            guard let self else { return }
            if let error = error {
                dlog("[BereanAccountability] Listen error: \(error.localizedDescription)")
                return
            }
            if let data = snapshot?.data(),
               let decoded = try? Firestore.Decoder().decode(AccountabilityProfile.self, from: data) {
                self.profile = decoded
                self.isLoaded = true
                dlog("[BereanAccountability] profile loaded streak=\(decoded.consistencyStreak)")
            } else {
                self.isLoaded = true
            }
        }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }

    // MARK: - Setup

    func enableAccountability() async {
        profile.isEnabled = true
        await saveProfile()
        dlog("[BereanAccountability] accountability enabled")
    }

    func disableAccountability() async {
        profile.isEnabled = false
        await saveProfile()
        dlog("[BereanAccountability] accountability disabled")
    }

    func updateTrackedAreas(_ areas: Set<AccountabilityProfile.StruggleArea>) async {
        profile.trackedAreas = areas
        await saveProfile()
        dlog("[BereanAccountability] tracked areas updated: \(areas.map(\.rawValue).joined(separator: ", "))")
    }

    // MARK: - Signal Recording

    func recordSignal(_ signal: AccountabilitySignal) async {
        guard profile.isEnabled else { return }

        switch signal {
        case .lateNightDM:
            profile.lateNightDMCount += 1
            dlog("[BereanAccountability] lateNightDM count=\(profile.lateNightDMCount)")
        case .flaggedConversation:
            profile.flaggedConversationCount += 1
            profile.consistencyStreak = 0
        case .cooldownBypassed:
            profile.cooldownBypassedCount += 1
        case .conflictEscalation:
            profile.conflictEscalationCount += 1
        case .positiveInteraction:
            // Positive signals help sustain streak
            break
        case .prayerActivity:
            profile.prayerConsistencyDays += 1
        case .churchNoteCreated:
            profile.obedienceActionCount += 1
            profile.reflectionDepthScore = min(profile.reflectionDepthScore + 0.05, 1.0)
        }

        await saveProfile()

        // Check if a pattern insight should surface
        if let insight = await evaluatePatterns() {
            pendingInsight = insight
        }
    }

    // MARK: - Pattern Detection

    func evaluatePatterns() async -> AccountabilityInsight? {
        guard profile.isEnabled else { return nil }

        // Pattern: 3+ late night DMs in past week
        if profile.lateNightDMCount >= 3 {
            return AccountabilityInsight(
                type: .pattern,
                message: "I've noticed a pattern in late-night conversations that may not align with your values. Consider setting a DM curfew.",
                options: [
                    .init(title: "Set time guard", action: .setTimeGuard),
                    .init(title: "Reflect on this", action: .openReflection),
                    .init(title: "Dismiss", action: .dismiss)
                ],
                createdAt: Date()
            )
        }

        // Pattern: multiple flagged conversations
        if profile.flaggedConversationCount >= 2 {
            return AccountabilityInsight(
                type: .warning,
                message: "A few of your recent conversations have been flagged. Would it help to add an accountability partner?",
                options: [
                    .init(title: "Add a partner", action: .addPartner),
                    .init(title: "Open reflection", action: .openReflection),
                    .init(title: "Dismiss", action: .dismiss)
                ],
                createdAt: Date()
            )
        }

        // Milestone: consistency streak
        if profile.consistencyStreak >= 7 {
            return AccountabilityInsight(
                type: .milestone,
                message: "Seven days of honoring your values in every conversation. That's faithfulness in action. (Matthew 25:21)",
                options: [
                    .init(title: "Give thanks", action: .openReflection),
                    .init(title: "Dismiss", action: .dismiss)
                ],
                createdAt: Date()
            )
        }

        // Encouragement: active prayer + spiritual engagement
        if profile.prayerConsistencyDays >= 5 && profile.obedienceActionCount >= 3 {
            return AccountabilityInsight(
                type: .encouragement,
                message: "You've been consistently engaging with Scripture and prayer this week. Keep going — growth is happening.",
                options: [
                    .init(title: "Open church notes", action: .openChurchNotes),
                    .init(title: "Dismiss", action: .dismiss)
                ],
                createdAt: Date()
            )
        }

        return nil
    }

    // MARK: - Weekly Reflection Card

    func generateWeeklyCard() -> WeeklyReflectionCard? {
        guard profile.isEnabled else { return nil }

        // Purity score: inversely proportional to flagged behavior
        let flaggedPenalty = Double(profile.flaggedConversationCount) * 15.0
        let purityScore = max(0, min(100, 100 - flaggedPenalty))

        // Patience score: based on conflict avoidance
        let conflictPenalty = Double(profile.conflictEscalationCount) * 20.0
        let patienceScore = max(0, min(100, 100 - conflictPenalty))

        // Discipline score: based on growth engagement
        let disciplineBase = (profile.reflectionDepthScore * 40)
                           + (min(Double(profile.obedienceActionCount), 5) * 8)
                           + (min(Double(profile.prayerConsistencyDays), 7) * 2.86)
        let disciplineScore = min(100, disciplineBase)

        // Determine top growth area
        var topArea = "consistency"
        if disciplineScore >= purityScore && disciplineScore >= patienceScore { topArea = "discipline" }
        else if patienceScore >= purityScore { topArea = "patience" }
        else { topArea = "purity" }

        // Encouragement message
        let encouragement: String
        let avg = (purityScore + patienceScore + disciplineScore) / 3
        switch avg {
        case 80...: encouragement = "You're walking in real faithfulness. Stay the course. (Galatians 6:9)"
        case 60..<80: encouragement = "Solid week. Keep leaning into growth where it matters most."
        case 40..<60: encouragement = "Every week is a chance to begin again. Grace is new every morning. (Lamentations 3:23)"
        default:     encouragement = "God's strength is made perfect in weakness. Don't give up. (2 Corinthians 12:9)"
        }

        let card = WeeklyReflectionCard(
            consistencyStreak: profile.consistencyStreak,
            purityScore: purityScore,
            patienceScore: patienceScore,
            disciplineScore: disciplineScore,
            encouragementMessage: encouragement,
            topGrowthArea: topArea,
            weekStartDate: Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        )

        weeklyReflectionCard = card
        return card
    }

    // MARK: - Time Guard

    func isDMAllowed() -> Bool {
        guard profile.dmCurfewEnabled else { return true }
        let hour = Calendar.current.component(.hour, from: Date())
        return hour < profile.dmCurfewHour
    }

    func dmCurfewMessage() -> String {
        let hour = profile.dmCurfewHour
        let displayHour = hour % 12 == 0 ? 12 : hour % 12
        let period = hour >= 12 ? "pm" : "am"
        return "You've set a curfew for DMs after \(displayHour)\(period). Rest well. 🙏"
    }

    // MARK: - Streak Management

    func incrementStreak() async {
        profile.consistencyStreak += 1
        await saveProfile()
    }

    func resetStreak() async {
        profile.consistencyStreak = 0
        await saveProfile()
    }

    // MARK: - Persistence

    private func saveProfile() async {
        guard let uid = Auth.auth().currentUser?.uid else {
            dlog("[BereanAccountability] No authenticated user — skipping save")
            return
        }
        do {
            let encoded = try Firestore.Encoder().encode(profile)
            try await profileRef(uid: uid).setData(encoded, merge: true)
            dlog("[BereanAccountability] profile saved")
        } catch {
            dlog("[BereanAccountability] save error: \(error.localizedDescription)")
        }
    }
}
