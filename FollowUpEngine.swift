//
//  FollowUpEngine.swift
//  AMENAPP
//
//  Follow-Up Engine — scheduled spiritual check-ins and growth evaluation.
//
//  After a Berean conversation, action step, or training prompt, this engine
//  schedules follow-ups at key intervals:
//    - 24h → behavior check ("Did you follow through?")
//    - 3d  → pattern detection ("How has this been going?")
//    - 7d  → growth evaluation ("Let's reflect on your week.")
//
//  Follow-ups are stored locally (UserDefaults) and in Firestore for
//  cross-device sync. They surface as gentle prompts in Berean, not
//  as push notifications (unless the user opts in).
//
//  Privacy:
//    - Only stores follow-up metadata (topic, date, status)
//    - No conversation content is stored
//    - User can delete/disable any follow-up
//
//  Architecture:
//    FollowUpEngine (singleton, @MainActor)
//    ├── FollowUpItem             (one scheduled follow-up)
//    ├── FollowUpInterval         (24h / 3d / 7d)
//    ├── scheduleFollowUp()       (create a new follow-up)
//    ├── getDueFollowUps()        (what's ready to surface)
//    ├── completeFollowUp()       (mark as done + record outcome)
//    └── generateFollowUpPrompt() (build the Berean prompt)
//

import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

// MARK: - Follow-Up Interval

enum FollowUpInterval: String, Codable, CaseIterable {
    case twentyFourHours = "24h"
    case threeDays       = "3d"
    case sevenDays       = "7d"

    var displayName: String {
        switch self {
        case .twentyFourHours: return "24-hour check-in"
        case .threeDays:       return "3-day check-in"
        case .sevenDays:       return "Weekly reflection"
        }
    }

    var timeInterval: TimeInterval {
        switch self {
        case .twentyFourHours: return 86400      // 24 hours
        case .threeDays:       return 259200      // 3 days
        case .sevenDays:       return 604800      // 7 days
        }
    }

    /// The type of follow-up question for this interval.
    var followUpStyle: FollowUpStyle {
        switch self {
        case .twentyFourHours: return .behaviorCheck
        case .threeDays:       return .patternDetection
        case .sevenDays:       return .growthEvaluation
        }
    }

    enum FollowUpStyle: String, Codable {
        case behaviorCheck      // "Did you follow through?"
        case patternDetection   // "How has this been going?"
        case growthEvaluation   // "Let's reflect on your week."
    }
}

// MARK: - Follow-Up Topic

/// What the follow-up is about.
enum FollowUpTopic: String, Codable {
    case actionStep          // User committed to a specific action
    case trainingPrompt      // User received a daily training prompt
    case struggle            // User discussed a recurring struggle
    case prayerRequest       // User posted a prayer
    case churchNote          // User took church notes
    case sermonWeek          // Part of a sermon → week transformation
    case bereanConversation  // General Berean conversation follow-up

    var emoji: String {
        switch self {
        case .actionStep:         return "checkmark.circle"
        case .trainingPrompt:     return "flame"
        case .struggle:           return "heart"
        case .prayerRequest:      return "hands.sparkles"
        case .churchNote:         return "book"
        case .sermonWeek:         return "calendar"
        case .bereanConversation: return "sparkles"
        }
    }
}

// MARK: - Follow-Up Outcome

/// What happened when the follow-up was checked.
enum FollowUpOutcome: String, Codable {
    case completed        // User followed through
    case partial          // User made some progress
    case notDone          // User didn't follow through
    case needsMore        // User wants to continue working on it
    case dismissed        // User dismissed without engaging
    case expired          // Follow-up expired without user seeing it
}

// MARK: - Follow-Up Item

struct FollowUpItem: Identifiable, Codable {
    let id: String
    let userId: String
    let topic: FollowUpTopic
    let interval: FollowUpInterval
    let contextSummary: String           // Brief description of what to follow up on
    let scriptureReference: String?      // Related verse
    let createdAt: Date
    let dueAt: Date
    var status: FollowUpStatus
    var outcome: FollowUpOutcome?
    var completedAt: Date?
    var userResponse: String?            // Brief user input at follow-up

    enum FollowUpStatus: String, Codable {
        case scheduled       // Waiting for due date
        case due             // Ready to surface
        case completed       // User engaged with it
        case expired         // Past due + grace period
        case dismissed       // User dismissed
    }

    var isDue: Bool {
        status == .scheduled && Date() >= dueAt
    }

    var isExpired: Bool {
        // Grace period: 48 hours after due date
        status == .scheduled && Date() > dueAt.addingTimeInterval(172800)
    }
}

// MARK: - Follow-Up Engine

@MainActor
final class FollowUpEngine: ObservableObject {

    static let shared = FollowUpEngine()

    @Published private(set) var followUps: [FollowUpItem] = []
    @Published private(set) var dueFollowUps: [FollowUpItem] = []

    private let localStorageKey = "berean_followups_v1"
    private let db = Firestore.firestore()
    private let maxActiveFollowUps = 20

    private init() {
        loadLocalFollowUps()
        updateDueStatus()
    }

    // MARK: - Schedule Follow-Up

    /// Schedules a follow-up at a specific interval.
    /// Automatically creates the full chain (24h → 3d → 7d) if `chainAll` is true.
    func scheduleFollowUp(
        topic: FollowUpTopic,
        contextSummary: String,
        scriptureReference: String? = nil,
        interval: FollowUpInterval = .twentyFourHours,
        chainAll: Bool = true
    ) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        // Don't exceed max active follow-ups
        let activeCount = followUps.filter { $0.status == .scheduled || $0.status == .due }.count
        guard activeCount < maxActiveFollowUps else { return }

        let intervals: [FollowUpInterval] = chainAll
            ? [.twentyFourHours, .threeDays, .sevenDays]
            : [interval]

        let now = Date()

        for interval in intervals {
            let item = FollowUpItem(
                id: UUID().uuidString,
                userId: uid,
                topic: topic,
                interval: interval,
                contextSummary: contextSummary,
                scriptureReference: scriptureReference,
                createdAt: now,
                dueAt: now.addingTimeInterval(interval.timeInterval),
                status: .scheduled,
                outcome: nil,
                completedAt: nil,
                userResponse: nil
            )

            followUps.append(item)
            await persistToFirestore(item)
        }

        saveLocalFollowUps()
        updateDueStatus()
    }

    /// Quick schedule: after a Berean conversation about a struggle.
    func scheduleStruggleFollowUp(
        struggle: String,
        scriptureReference: String? = nil
    ) async {
        await scheduleFollowUp(
            topic: .struggle,
            contextSummary: "Follow up on your struggle with \(struggle)",
            scriptureReference: scriptureReference
        )
    }

    /// Quick schedule: after user commits to an action step.
    func scheduleActionFollowUp(
        action: String,
        scriptureReference: String? = nil
    ) async {
        await scheduleFollowUp(
            topic: .actionStep,
            contextSummary: action,
            scriptureReference: scriptureReference
        )
    }

    // MARK: - Get Due Follow-Ups

    /// Returns follow-ups that are currently due.
    func getDueFollowUps() -> [FollowUpItem] {
        updateDueStatus()
        return dueFollowUps
    }

    // MARK: - Complete Follow-Up

    /// Marks a follow-up as completed with an outcome.
    func completeFollowUp(
        _ id: String,
        outcome: FollowUpOutcome,
        userResponse: String? = nil
    ) async {
        guard let index = followUps.firstIndex(where: { $0.id == id }) else { return }

        followUps[index].status = .completed
        followUps[index].outcome = outcome
        followUps[index].completedAt = Date()
        followUps[index].userResponse = userResponse

        saveLocalFollowUps()
        updateDueStatus()
        await persistToFirestore(followUps[index])

        // Record outcome to Personal Spiritual Graph
        if outcome == .completed {
            await PersonalSpiritualGraphService.shared.recordObedienceAction(
                category: followUps[index].contextSummary,
                source: .bereanChat
            )
        }
    }

    /// Dismisses a follow-up.
    func dismissFollowUp(_ id: String) async {
        guard let index = followUps.firstIndex(where: { $0.id == id }) else { return }

        followUps[index].status = .dismissed
        followUps[index].outcome = .dismissed
        followUps[index].completedAt = Date()

        saveLocalFollowUps()
        updateDueStatus()
        await persistToFirestore(followUps[index])
    }

    // MARK: - Generate Follow-Up Prompt

    /// Generates a Berean prompt for a due follow-up.
    func generateFollowUpPrompt(for item: FollowUpItem) -> String {
        switch item.interval.followUpStyle {
        case .behaviorCheck:
            return buildBehaviorCheckPrompt(item)
        case .patternDetection:
            return buildPatternDetectionPrompt(item)
        case .growthEvaluation:
            return buildGrowthEvaluationPrompt(item)
        }
    }

    private func buildBehaviorCheckPrompt(_ item: FollowUpItem) -> String {
        var prompt = "--- 24-Hour Follow-Up ---\n"
        prompt += "The user committed to: \(item.contextSummary)\n"
        if let ref = item.scriptureReference {
            prompt += "Related scripture: \(ref)\n"
        }
        prompt += "Ask gently whether they followed through. "
        prompt += "If yes, celebrate and reinforce. "
        prompt += "If no, don't shame — explore what got in the way and re-encourage.\n"
        prompt += "--- End Follow-Up ---"
        return prompt
    }

    private func buildPatternDetectionPrompt(_ item: FollowUpItem) -> String {
        var prompt = "--- 3-Day Pattern Check ---\n"
        prompt += "Context: \(item.contextSummary)\n"
        if let ref = item.scriptureReference {
            prompt += "Related scripture: \(ref)\n"
        }
        prompt += "Ask how this area has been going over the past few days. "
        prompt += "Look for patterns — is this getting easier or harder? "
        prompt += "Suggest adjustments if needed. Offer a deeper question.\n"
        prompt += "--- End Follow-Up ---"
        return prompt
    }

    private func buildGrowthEvaluationPrompt(_ item: FollowUpItem) -> String {
        var prompt = "--- Weekly Growth Reflection ---\n"
        prompt += "Context: \(item.contextSummary)\n"
        if let ref = item.scriptureReference {
            prompt += "Related scripture: \(ref)\n"
        }
        prompt += "Help the user reflect on their week holistically. "
        prompt += "What changed? What stayed the same? "
        prompt += "Celebrate any growth. If the struggle persists, suggest a focused plan. "
        prompt += "Ask: 'Would you like to build a focused 3-day plan around this?'\n"
        prompt += "--- End Follow-Up ---"
        return prompt
    }

    /// Builds a system prompt block for all currently due follow-ups.
    func systemPromptForDueFollowUps() -> String {
        let due = getDueFollowUps()
        guard !due.isEmpty else { return "" }

        var lines: [String] = []
        lines.append("--- Active Follow-Ups ---")
        lines.append("The following follow-ups are due. Weave them naturally into conversation:")
        lines.append("")

        for item in due.prefix(3) { // Max 3 at a time
            lines.append(generateFollowUpPrompt(for: item))
            lines.append("")
        }

        lines.append("--- End Follow-Ups ---")
        return lines.joined(separator: "\n")
    }

    // MARK: - Status Updates

    private func updateDueStatus() {
        let now = Date()

        for i in followUps.indices {
            if followUps[i].isExpired {
                followUps[i].status = .expired
                followUps[i].outcome = .expired
            } else if followUps[i].isDue {
                followUps[i].status = .due
            }
        }

        dueFollowUps = followUps.filter { $0.status == .due }

        // Clean up old completed/expired items (keep last 50)
        let active = followUps.filter { $0.status == .scheduled || $0.status == .due }
        let inactive = followUps.filter { $0.status != .scheduled && $0.status != .due }
            .sorted { ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt) }
            .prefix(50)

        followUps = active + inactive
    }

    // MARK: - Persistence (Local)

    private func loadLocalFollowUps() {
        guard let data = UserDefaults.standard.data(forKey: localStorageKey),
              let items = try? JSONDecoder().decode([FollowUpItem].self, from: data) else {
            return
        }
        followUps = items
    }

    private func saveLocalFollowUps() {
        guard let data = try? JSONEncoder().encode(followUps) else { return }
        UserDefaults.standard.set(data, forKey: localStorageKey)
    }

    // MARK: - Persistence (Firestore)

    private func persistToFirestore(_ item: FollowUpItem) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        do {
            let data = try Firestore.Encoder().encode(item)
            try await db.collection("users").document(uid)
                .collection("followUps")
                .document(item.id)
                .setData(data, merge: true)
        } catch {
            dlog("[FollowUpEngine] Firestore persist failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Sync from Firestore

    /// Syncs follow-ups from Firestore (call on app launch for cross-device sync).
    func syncFromFirestore() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        do {
            let snapshot = try await db.collection("users").document(uid)
                .collection("followUps")
                .whereField("status", in: ["scheduled", "due"])
                .order(by: "dueAt")
                .limit(to: 50)
                .getDocuments()

            let remoteItems: [FollowUpItem] = snapshot.documents.compactMap { doc in
                try? doc.data(as: FollowUpItem.self)
            }

            // Merge: remote items not in local get added
            let localIDs = Set(followUps.map(\.id))
            let newRemote = remoteItems.filter { !localIDs.contains($0.id) }
            followUps.append(contentsOf: newRemote)

            saveLocalFollowUps()
            updateDueStatus()

        } catch {
            dlog("[FollowUpEngine] Firestore sync failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Delete All

    func deleteAll() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        followUps.removeAll()
        dueFollowUps.removeAll()
        UserDefaults.standard.removeObject(forKey: localStorageKey)

        // Delete from Firestore
        do {
            let docs = try await db.collection("users").document(uid)
                .collection("followUps")
                .limit(to: 500)
                .getDocuments()

            let batch = db.batch()
            for doc in docs.documents {
                batch.deleteDocument(doc.reference)
            }
            try await batch.commit()
        } catch {
            dlog("[FollowUpEngine] Delete all failed: \(error.localizedDescription)")
        }
    }
}
