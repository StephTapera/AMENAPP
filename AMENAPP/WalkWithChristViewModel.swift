// WalkWithChristViewModel.swift
// AMENAPP
import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Combine

@MainActor
final class WalkWithChristViewModel: ObservableObject {

    // MARK: - Published state
    @Published var streakDays: Int = 0
    @Published var progressPercent: Double = 0.0
    @Published var currentWeek: Int = 0
    @Published var totalWeeks: Int = 12
    @Published var devotionalProgress: Double = 0.0
    @Published var devotionalDay: Int = 0
    @Published var devotionalTotal: Int = 40
    @Published var milestoneProgress: Double = 0.0
    @Published var milestonesCompleted: Int = 0
    @Published var milestonesTotal: Int = 10
    @Published var completedReflections: Set<String> = []
    @Published var completedQuizzes: Set<String> = []
    @Published var firstName: String = "Friend"
    @Published var faithStage: FaithStagePersonal = .exploring
    @Published var pathName: String = "New Believer Path"
    @Published var isLoading: Bool = false

    // MARK: - FaithStage
    enum FaithStagePersonal: String, Codable {
        case exploring, growing, deepening, leading

        var greeting: String {
            switch self {
            case .exploring: return "Welcome to your journey"
            case .growing:   return "Keep building"
            case .deepening: return "Going deeper"
            case .leading:   return "Leading well"
            }
        }

        var accentHex: String {
            switch self {
            case .exploring: return "#2563EB"
            case .growing:   return "#B45309"
            case .deepening: return "#7C3AED"
            case .leading:   return "#16A34A"
            }
        }
    }

    // MARK: - Computed
    var greetingPrefix: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default:      return "Good evening"
        }
    }

    var fullGreeting: String { "\(greetingPrefix), \(firstName)." }
    var stageGreeting: String { faithStage.greeting }

    var isStreakGold: Bool { streakDays >= 30 }
    var dailyHabitsUnlocked: Bool { devotionalDay >= 21 }
    var daysUntilHabits: Int { max(0, 21 - devotionalDay) }

    // MARK: - Load
    func loadUserData() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isLoading = true
        let db = Firestore.firestore()
        do {
            let doc = try await db.collection("users").document(uid).getDocument()
            let data = doc.data() ?? [:]

            firstName = data["first_name"] as? String ?? data["firstName"] as? String ?? "Friend"
            if firstName.isEmpty { firstName = "Friend" }

            streakDays          = data["walk_streak"] as? Int ?? 0
            devotionalDay       = data["devotional_day"] as? Int ?? 0
            devotionalTotal     = data["devotional_total"] as? Int ?? 40
            milestonesCompleted = data["milestones_completed"] as? Int ?? 0
            milestonesTotal     = data["milestones_total"] as? Int ?? 10
            completedReflections = Set(data["completed_reflections"] as? [String] ?? [])
            completedQuizzes    = Set(data["completed_quizzes"] as? [String] ?? [])

            if let stageRaw = data["faith_stage"] as? String,
               let stage = FaithStagePersonal(rawValue: stageRaw) {
                faithStage = stage
            }

            // Calculate progress
            if devotionalTotal > 0 {
                devotionalProgress = Double(devotionalDay) / Double(devotionalTotal)
            }
            if milestonesTotal > 0 {
                milestoneProgress = Double(milestonesCompleted) / Double(milestonesTotal)
            }
            progressPercent = (devotionalProgress + milestoneProgress) / 2.0

            // Week calculation
            if let startedAt = (data["walk_started_at"] as? Timestamp)?.dateValue() {
                let weeks = Calendar.current.dateComponents([.weekOfYear], from: startedAt, to: Date()).weekOfYear ?? 0
                currentWeek = max(1, weeks + 1)
            } else {
                currentWeek = 1
            }
        } catch {
            dlog("⚠️ WalkWithChristViewModel: loadUserData error: \(error)")
        }
        isLoading = false
    }

    func markReflectionComplete(promptId: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        completedReflections.insert(promptId)
        let db = Firestore.firestore()
        do {
            try await db.collection("users").document(uid).updateData([
                "completed_reflections": FieldValue.arrayUnion([promptId])
            ])
        } catch {
            dlog("⚠️ markReflectionComplete error: \(error)")
        }
    }

    func markQuizComplete(quizId: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        completedQuizzes.insert(quizId)
        let db = Firestore.firestore()
        do {
            try await db.collection("users").document(uid).updateData([
                "completed_quizzes": FieldValue.arrayUnion([quizId])
            ])
        } catch {
            dlog("⚠️ markQuizComplete error: \(error)")
        }
    }
}
