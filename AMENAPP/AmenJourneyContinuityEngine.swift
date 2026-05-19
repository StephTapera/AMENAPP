// AmenJourneyContinuityEngine.swift
// AMENAPP
// Journey / Continuity Engine — synthesizes spiritual memory, study threads,
// and engagement history into a formation path surface for Selah and Berean.
// Session-aware; outputs contextual continuity signals used by BereanChatView,
// SelahView, and BereanStudyHomeView to surface "continue where you left off" prompts.

import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class AmenJourneyContinuityEngine: ObservableObject {
    static let shared = AmenJourneyContinuityEngine()

    // Surfaces to UI
    @Published private(set) var continuityPrompts: [ContinuityPrompt] = []
    @Published private(set) var formationMilestones: [FormationMilestone] = []
    @Published private(set) var currentStreak: Int = 0
    @Published private(set) var weeklyEngagement: WeeklyEngagement = WeeklyEngagement()

    private let db = Firestore.firestore()
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Models

    struct ContinuityPrompt: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let icon: String
        let actionType: ActionType
        let contextId: String?

        enum ActionType {
            case continueStudyThread
            case revisitVerse
            case resumeChurchNote
            case returnToSelah
            case followUpPrayer
        }
    }

    struct FormationMilestone: Identifiable {
        let id: String
        let title: String
        let description: String
        let achievedAt: Date
        let icon: String
        let category: String
    }

    struct WeeklyEngagement {
        var bibleStudyDays: Int = 0
        var prayerCheckIns: Int = 0
        var selahSessions: Int = 0
        var bereanSessions: Int = 0
        var churchNotesCreated: Int = 0

        var overallScore: Double {
            let total = Double(bibleStudyDays + prayerCheckIns + selahSessions + bereanSessions + churchNotesCreated)
            return min(total / 15.0, 1.0)
        }
    }

    // MARK: - Public API

    func loadForCurrentUser() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        async let prompts: Void = loadContinuityPrompts(uid: uid)
        async let milestones: Void = loadMilestones(uid: uid)
        async let streak: Void = loadStreak(uid: uid)
        _ = await (prompts, milestones, streak)
    }

    /// Call when user opens Berean to potentially surface a continuity prompt.
    func bereanSessionOpened() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        // Record engagement signal
        let ref = db.collection("users").document(uid)
            .collection("journey_engagement")
            .document(todayKey())
        try? await ref.setData(["bereanSessions": FieldValue.increment(Int64(1))], merge: true)
    }

    /// Call when user completes a Selah session.
    func selahSessionCompleted(duration: TimeInterval) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let ref = db.collection("users").document(uid)
            .collection("journey_engagement")
            .document(todayKey())
        try? await ref.setData([
            "selahSessions": FieldValue.increment(Int64(1)),
            "totalSelahMinutes": FieldValue.increment(Int64(duration / 60))
        ], merge: true)
        await updateStreak(uid: uid)
    }

    /// Call when user creates a church note (triggers potential milestone).
    func churchNoteCreated() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let ref = db.collection("users").document(uid)
            .collection("journey_engagement")
            .document(todayKey())
        try? await ref.setData(["churchNotesCreated": FieldValue.increment(Int64(1))], merge: true)
    }

    // MARK: - Private

    private func loadContinuityPrompts(uid: String) async {
        // Source continuity prompts from recent study threads and berean sessions
        let threads = BereanStudyThreadService.shared.threads
        var prompts: [ContinuityPrompt] = []

        for thread in threads.prefix(3) {
            prompts.append(ContinuityPrompt(
                id: thread.id,
                title: "Continue: \(thread.title)",
                subtitle: thread.passage.map { "Studying \($0)" } ?? "Pick up where you left off",
                icon: "arrow.triangle.branch",
                actionType: .continueStudyThread,
                contextId: thread.id
            ))
        }

        // Add a Selah continuity prompt if last session was >12h ago
        if let lastSelah = lastSelahDate(), Date().timeIntervalSince(lastSelah) > 43_200 {
            prompts.append(ContinuityPrompt(
                id: "selah_return",
                title: "Return to Selah",
                subtitle: "Continue your spiritual practice",
                icon: "sparkles",
                actionType: .returnToSelah,
                contextId: nil
            ))
        }

        continuityPrompts = prompts
    }

    private func loadMilestones(uid: String) async {
        do {
            let snap = try await db.collection("users").document(uid)
                .collection("journey_milestones")
                .order(by: "achievedAt", descending: true)
                .limit(to: 10)
                .getDocuments()
            formationMilestones = snap.documents.compactMap { doc -> FormationMilestone? in
                let d = doc.data()
                guard let ts = (d["achievedAt"] as? Timestamp)?.dateValue(),
                      let title = d["title"] as? String else { return nil }
                return FormationMilestone(
                    id: doc.documentID,
                    title: title,
                    description: d["description"] as? String ?? "",
                    achievedAt: ts,
                    icon: d["icon"] as? String ?? "star.fill",
                    category: d["category"] as? String ?? "general"
                )
            }
        } catch {
            dlog("[AmenJourneyContinuityEngine] loadMilestones error: \(error)")
        }
    }

    private func loadStreak(uid: String) async {
        do {
            let doc = try await db.collection("users").document(uid)
                .collection("journey_state")
                .document("streak")
                .getDocument()
            currentStreak = doc.data()?["currentStreak"] as? Int ?? 0
        } catch {
            currentStreak = 0
        }
    }

    private func updateStreak(uid: String) async {
        let ref = db.collection("users").document(uid)
            .collection("journey_state")
            .document("streak")
        try? await ref.setData([
            "lastEngagementDate": Timestamp(date: Date()),
            "currentStreak": FieldValue.increment(Int64(1))
        ], merge: true)
        currentStreak += 1
    }

    private func todayKey() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: Date())
    }

    private func lastSelahDate() -> Date? {
        UserDefaults.standard.object(forKey: "amen_last_selah_date") as? Date
    }
}
