//
//  WalkWithChristViewModel.swift
//  AMENAPP
//
//  Data layer for the Walk With Christ personalized experience.
//  Reads user profile from Firestore and provides faith-stage-aware content.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import Combine

// MARK: - Faith Stage

enum FaithStage: String, Codable, CaseIterable {
    case newBeliever = "new_believer"
    case growing = "growing"
    case established = "established"
    case mentor = "mentor"

    var greeting: String {
        switch self {
        case .newBeliever: return "Welcome to your faith journey"
        case .growing: return "Keep growing in His Word"
        case .established: return "Walking strong in faith"
        case .mentor: return "Leading others to Christ"
        }
    }

    var color: String {
        switch self {
        case .newBeliever: return "green"
        case .growing: return "blue"
        case .established: return "purple"
        case .mentor: return "gold"
        }
    }

    var progressLabel: String {
        switch self {
        case .newBeliever: return "Seedling"
        case .growing: return "Growing"
        case .established: return "Rooted"
        case .mentor: return "Shepherd"
        }
    }
}

// MARK: - Walk Path

struct WalkPath: Identifiable, Codable {
    let id: String
    let title: String
    let description: String
    let icon: String
    let totalLessons: Int
    var completedLessons: Int
    let requiredStage: FaithStage
    let color: String // hex color string

    var progress: Double {
        guard totalLessons > 0 else { return 0 }
        return Double(completedLessons) / Double(totalLessons)
    }

    var isComplete: Bool { completedLessons >= totalLessons }
}

// MARK: - Reflection Prompt

struct ReflectionPrompt: Identifiable, Codable {
    let id: String
    let prompt: String
    let category: String
    let scripture: String?
    var isCompleted: Bool
}

// MARK: - Faith Quiz

struct FaithQuiz: Identifiable, Codable {
    let id: String
    let question: String
    let options: [String]
    let correctIndex: Int
    let explanation: String
    let scripture: String
    var isAnswered: Bool
    var userAnswer: Int?

    var isCorrect: Bool {
        guard let answer = userAnswer else { return false }
        return answer == correctIndex
    }
}

// MARK: - View Model

@MainActor
final class WalkWithChristViewModel: ObservableObject {
    // User info
    @Published var firstName: String = "Friend"
    @Published var faithStage: FaithStage = .newBeliever
    @Published var walkStreak: Int = 0
    @Published var walkStartedAt: Date?
    @Published var totalLessonsCompleted: Int = 0

    // Content
    @Published var paths: [WalkPath] = []
    @Published var todayReflection: ReflectionPrompt?
    @Published var todayQuiz: FaithQuiz?
    @Published var dailyVerse: PersonalizedDailyVerse?

    // State
    @Published var isLoading = true
    @Published var hasAppeared = false
    @Published var progressAnimated = false
    @Published var pathBarsAnimated = false

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    var daysOnJourney: Int {
        guard let start = walkStartedAt else { return 0 }
        return max(1, Calendar.current.dateComponents([.day], from: start, to: Date()).day ?? 0)
    }

    var streakEmoji: String {
        switch walkStreak {
        case 0: return ""
        case 1...6: return "🌱"
        case 7...29: return "🔥"
        case 30...99: return "⭐"
        default: return "👑"
        }
    }

    var streakLabel: String {
        guard walkStreak > 0 else { return "" }
        return "\(walkStreak)-day streak \(streakEmoji)"
    }

    // MARK: - Load Data

    func loadUserData() async {
        guard let uid = Auth.auth().currentUser?.uid else {
            isLoading = false
            return
        }

        do {
            let doc = try await db.collection("users").document(uid).getDocument()
            let data = doc.data() ?? [:]

            firstName = (data["firstName"] as? String)?.trimmingCharacters(in: .whitespaces).isEmpty == false
                ? (data["firstName"] as? String ?? "Friend")
                : "Friend"

            if let stageStr = data["faith_stage"] as? String,
               let stage = FaithStage(rawValue: stageStr) {
                faithStage = stage
            }

            walkStreak = data["walk_streak"] as? Int ?? 0

            if let ts = data["walk_started_at"] as? Timestamp {
                walkStartedAt = ts.dateValue()
            }

            totalLessonsCompleted = data["total_lessons_completed"] as? Int ?? 0

            // Load paths
            await loadPaths(uid: uid)

            // Load today's reflection
            await loadTodayReflection()

            // Load today's quiz
            await loadTodayQuiz()

            // Load daily verse
            await loadDailyVerse()

        } catch {
            print("⚠️ WalkWithChrist: Failed to load user data: \(error.localizedDescription)")
        }

        isLoading = false
    }

    // MARK: - Paths

    private func loadPaths(uid: String) async {
        // Default paths — personalized based on faith stage
        let allPaths: [WalkPath] = [
            WalkPath(
                id: "foundations",
                title: "Foundations of Faith",
                description: "Core beliefs and first steps",
                icon: "book.closed.fill",
                totalLessons: 12,
                completedLessons: 0,
                requiredStage: .newBeliever,
                color: "#16a34a"
            ),
            WalkPath(
                id: "prayer_life",
                title: "Building a Prayer Life",
                description: "Learning to talk with God",
                icon: "hands.sparkles.fill",
                totalLessons: 10,
                completedLessons: 0,
                requiredStage: .newBeliever,
                color: "#7c3aed"
            ),
            WalkPath(
                id: "bible_study",
                title: "Studying the Word",
                description: "How to read and apply Scripture",
                icon: "text.book.closed.fill",
                totalLessons: 15,
                completedLessons: 0,
                requiredStage: .growing,
                color: "#2563eb"
            ),
            WalkPath(
                id: "spiritual_disciplines",
                title: "Spiritual Disciplines",
                description: "Fasting, worship, and community",
                icon: "figure.mind.and.body",
                totalLessons: 10,
                completedLessons: 0,
                requiredStage: .growing,
                color: "#b45309"
            ),
            WalkPath(
                id: "theology_deep",
                title: "Theology Deep Dive",
                description: "Understanding doctrine and church history",
                icon: "graduationcap.fill",
                totalLessons: 20,
                completedLessons: 0,
                requiredStage: .established,
                color: "#9333ea"
            ),
            WalkPath(
                id: "mentoring",
                title: "Mentoring Others",
                description: "How to disciple and lead",
                icon: "person.2.fill",
                totalLessons: 8,
                completedLessons: 0,
                requiredStage: .mentor,
                color: "#b45309"
            )
        ]

        // Try to load user progress from Firestore
        do {
            let snapshot = try await db.collection("users").document(uid)
                .collection("walk_paths").getDocuments()

            var progressMap: [String: Int] = [:]
            for doc in snapshot.documents {
                let data = doc.data()
                progressMap[doc.documentID] = data["completedLessons"] as? Int ?? 0
            }

            paths = allPaths.map { path in
                var updated = path
                if let completed = progressMap[path.id] {
                    updated.completedLessons = completed
                }
                return updated
            }
        } catch {
            paths = allPaths
        }
    }

    // MARK: - Reflection

    private func loadTodayReflection() async {
        // Generate a daily reflection prompt based on faith stage
        let prompts: [FaithStage: [ReflectionPrompt]] = [
            .newBeliever: [
                ReflectionPrompt(id: "r1", prompt: "What drew you to faith?", category: "Journey", scripture: "Jeremiah 29:13", isCompleted: false),
                ReflectionPrompt(id: "r2", prompt: "What is one thing about God that amazes you?", category: "Wonder", scripture: "Psalm 139:14", isCompleted: false),
                ReflectionPrompt(id: "r3", prompt: "Who has been a spiritual encouragement to you?", category: "Community", scripture: "Hebrews 10:24-25", isCompleted: false),
            ],
            .growing: [
                ReflectionPrompt(id: "r4", prompt: "How has God challenged you this week?", category: "Growth", scripture: "James 1:2-4", isCompleted: false),
                ReflectionPrompt(id: "r5", prompt: "What Scripture spoke to you recently?", category: "Word", scripture: "Psalm 119:105", isCompleted: false),
                ReflectionPrompt(id: "r6", prompt: "Where do you see God at work in your life?", category: "Awareness", scripture: "Philippians 1:6", isCompleted: false),
            ],
            .established: [
                ReflectionPrompt(id: "r7", prompt: "How are you serving others this season?", category: "Service", scripture: "Galatians 5:13", isCompleted: false),
                ReflectionPrompt(id: "r8", prompt: "What spiritual discipline is God refining in you?", category: "Discipline", scripture: "1 Timothy 4:7", isCompleted: false),
            ],
            .mentor: [
                ReflectionPrompt(id: "r9", prompt: "Who is God calling you to invest in?", category: "Discipleship", scripture: "2 Timothy 2:2", isCompleted: false),
                ReflectionPrompt(id: "r10", prompt: "What wisdom have you gained that others need?", category: "Legacy", scripture: "Proverbs 27:17", isCompleted: false),
            ]
        ]

        let stagePrompts = prompts[faithStage] ?? prompts[.newBeliever]!
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
        let index = (dayOfYear - 1) % stagePrompts.count
        todayReflection = stagePrompts[index]
    }

    // MARK: - Quiz

    private func loadTodayQuiz() async {
        let quizzes: [FaithQuiz] = [
            FaithQuiz(
                id: "q1",
                question: "Which book of the Bible begins with 'In the beginning'?",
                options: ["Exodus", "Genesis", "Psalms", "John"],
                correctIndex: 1,
                explanation: "Genesis 1:1 — 'In the beginning God created the heavens and the earth.'",
                scripture: "Genesis 1:1",
                isAnswered: false,
                userAnswer: nil
            ),
            FaithQuiz(
                id: "q2",
                question: "How many disciples did Jesus choose?",
                options: ["7", "10", "12", "14"],
                correctIndex: 2,
                explanation: "Jesus chose 12 disciples, also called apostles, to be His closest followers.",
                scripture: "Matthew 10:1-4",
                isAnswered: false,
                userAnswer: nil
            ),
            FaithQuiz(
                id: "q3",
                question: "What is the shortest verse in the Bible?",
                options: ["God is love.", "Jesus wept.", "Pray always.", "Be still."],
                correctIndex: 1,
                explanation: "John 11:35 — 'Jesus wept.' shows His compassion at Lazarus's tomb.",
                scripture: "John 11:35",
                isAnswered: false,
                userAnswer: nil
            ),
            FaithQuiz(
                id: "q4",
                question: "Who built the ark?",
                options: ["Abraham", "Moses", "Noah", "David"],
                correctIndex: 2,
                explanation: "God instructed Noah to build an ark to save his family and the animals from the flood.",
                scripture: "Genesis 6:14",
                isAnswered: false,
                userAnswer: nil
            ),
            FaithQuiz(
                id: "q5",
                question: "What fruit of the Spirit is listed first in Galatians 5:22?",
                options: ["Joy", "Peace", "Love", "Patience"],
                correctIndex: 2,
                explanation: "Galatians 5:22 lists love as the first fruit of the Spirit.",
                scripture: "Galatians 5:22",
                isAnswered: false,
                userAnswer: nil
            )
        ]

        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
        let index = (dayOfYear - 1) % quizzes.count
        todayQuiz = quizzes[index]
    }

    // MARK: - Daily Verse

    private func loadDailyVerse() async {
        let verse = await DailyVerseGenkitService.shared.generatePersonalizedDailyVerse()
        dailyVerse = verse
    }

    // MARK: - Actions

    func completeReflection() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        todayReflection?.isCompleted = true

        // Save to Firestore
        do {
            try await db.collection("users").document(uid).collection("reflections")
                .document(todayReflection?.id ?? UUID().uuidString)
                .setData([
                    "promptId": todayReflection?.id ?? "",
                    "prompt": todayReflection?.prompt ?? "",
                    "completedAt": FieldValue.serverTimestamp(),
                    "faithStage": faithStage.rawValue
                ])
        } catch {
            print("⚠️ WalkWithChrist: Failed to save reflection: \(error.localizedDescription)")
        }
    }

    func submitQuizAnswer(_ answerIndex: Int) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        todayQuiz?.userAnswer = answerIndex
        todayQuiz?.isAnswered = true

        do {
            try await db.collection("users").document(uid).collection("quiz_answers")
                .document(todayQuiz?.id ?? UUID().uuidString)
                .setData([
                    "quizId": todayQuiz?.id ?? "",
                    "answer": answerIndex,
                    "correct": todayQuiz?.isCorrect ?? false,
                    "answeredAt": FieldValue.serverTimestamp()
                ])
        } catch {
            print("⚠️ WalkWithChrist: Failed to save quiz answer: \(error.localizedDescription)")
        }
    }

    func isPathLocked(_ path: WalkPath) -> Bool {
        let stageOrder: [FaithStage] = [.newBeliever, .growing, .established, .mentor]
        guard let requiredIndex = stageOrder.firstIndex(of: path.requiredStage),
              let currentIndex = stageOrder.firstIndex(of: faithStage) else { return false }
        return currentIndex < requiredIndex
    }

    deinit {
        listener?.remove()
    }
}
