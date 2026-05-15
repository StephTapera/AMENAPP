// AmenStudyPlanBuilder.swift
// AMENAPP

import Foundation
import FirebaseAuth
import FirebaseFirestore

// MARK: - Models

enum AmenStudyPlanDuration: Int, CaseIterable, Identifiable, Codable {
    case three  = 3
    case seven  = 7
    case fourteen = 14
    case thirty = 30
    case custom = 0

    var id: Int { rawValue }

    var displayLabel: String {
        switch self {
        case .three:    return "3 Days"
        case .seven:    return "1 Week"
        case .fourteen: return "2 Weeks"
        case .thirty:   return "30 Days"
        case .custom:   return "Custom"
        }
    }
}

enum AmenStudyPlanSource: String, Codable {
    case book, topic, sermon, devotional, scripture, bereanAnswer
}

struct AmenStudyDay: Identifiable, Codable {
    let id: UUID
    let dayNumber: Int
    let title: String
    let readingExcerpt: String?      // book chapter range or article title
    let scriptureFocus: String       // e.g. "John 15:1-11"
    let reflectionPrompt: String
    let prayerPrompt: String
    let audioPrompt: String?         // optional; nil when not available
    var isCompleted: Bool

    init(dayNumber: Int, title: String, readingExcerpt: String?, scriptureFocus: String,
         reflectionPrompt: String, prayerPrompt: String, audioPrompt: String? = nil) {
        self.id = UUID()
        self.dayNumber = dayNumber
        self.title = title
        self.readingExcerpt = readingExcerpt
        self.scriptureFocus = scriptureFocus
        self.reflectionPrompt = reflectionPrompt
        self.prayerPrompt = prayerPrompt
        self.audioPrompt = audioPrompt
        self.isCompleted = false
    }
}

struct AmenStudyPlan: Identifiable, Codable {
    let id: String
    let title: String
    let subtitle: String
    let source: AmenStudyPlanSource
    let sourceTitle: String          // e.g. book title or scripture reference
    let createdAt: Date
    var days: [AmenStudyDay]
    var currentDayIndex: Int
    var isCompleted: Bool

    var progress: Double {
        guard !days.isEmpty else { return 0 }
        return Double(days.filter(\.isCompleted).count) / Double(days.count)
    }

    var currentDay: AmenStudyDay? {
        guard currentDayIndex < days.count else { return nil }
        return days[currentDayIndex]
    }
}

// MARK: - Builder

@MainActor
final class AmenStudyPlanBuilder: ObservableObject {

    static let shared = AmenStudyPlanBuilder()

    @Published private(set) var activePlans: [AmenStudyPlan] = []
    @Published private(set) var isBuilding = false
    @Published var lastError: String?

    private let db = Firestore.firestore()
    private init() {}

    // MARK: - Load

    func loadPlans() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        Task {
            let snap = try? await db.collection("users").document(uid)
                .collection("studyPlans")
                .order(by: "createdAt", descending: true)
                .limit(to: 20)
                .getDocuments()
            activePlans = snap?.documents.compactMap { try? $0.data(as: AmenStudyPlan.self) } ?? []
        }
    }

    // MARK: - Create Plan

    func createPlan(
        from source: AmenStudyPlanSource,
        sourceTitle: String,
        book: WLBook? = nil,
        duration: AmenStudyPlanDuration,
        customDays: Int? = nil
    ) async -> AmenStudyPlan? {
        isBuilding = true
        defer { isBuilding = false }

        let count = duration == .custom ? (customDays ?? 7) : duration.rawValue
        let days = buildDays(
            count: count, source: source, sourceTitle: sourceTitle, book: book
        )

        let plan = AmenStudyPlan(
            id: UUID().uuidString,
            title: planTitle(source: source, sourceTitle: sourceTitle),
            subtitle: "\(count)-day study",
            source: source,
            sourceTitle: sourceTitle,
            createdAt: Date(),
            days: days,
            currentDayIndex: 0,
            isCompleted: false
        )

        await persistPlan(plan)
        activePlans.insert(plan, at: 0)
        return plan
    }

    // MARK: - Progress

    func markDayComplete(planId: String, dayIndex: Int) {
        guard let idx = activePlans.firstIndex(where: { $0.id == planId }) else { return }
        activePlans[idx].days[dayIndex].isCompleted = true
        let nextIdx = dayIndex + 1
        if nextIdx < activePlans[idx].days.count {
            activePlans[idx].currentDayIndex = nextIdx
        } else {
            activePlans[idx].isCompleted = true
        }
        Task { await persistPlan(activePlans[idx]) }
    }

    func deletePlan(_ planId: String) {
        activePlans.removeAll { $0.id == planId }
        guard let uid = Auth.auth().currentUser?.uid else { return }
        db.collection("users").document(uid).collection("studyPlans").document(planId).delete()
    }

    // MARK: - Day Generation

    private func buildDays(count: Int, source: AmenStudyPlanSource,
                           sourceTitle: String, book: WLBook?) -> [AmenStudyDay] {
        (1...count).map { day in
            let script = scriptureForDay(day: day, source: source, sourceTitle: sourceTitle)
            return AmenStudyDay(
                dayNumber: day,
                title: dayTitle(day: day, count: count, sourceTitle: sourceTitle),
                readingExcerpt: book.map { readingExcerpt(book: $0, day: day, total: count) },
                scriptureFocus: script,
                reflectionPrompt: reflectionPrompt(day: day, source: source),
                prayerPrompt: prayerPrompt(day: day, source: source)
            )
        }
    }

    private func dayTitle(day: Int, count: Int, sourceTitle: String) -> String {
        switch day {
        case 1:     return "Beginning: \(sourceTitle)"
        case count: return "Reflection: What Has Changed?"
        default:    return "Day \(day) — Going Deeper"
        }
    }

    private func readingExcerpt(book: WLBook, day: Int, total: Int) -> String {
        let pages = book.pageCount ?? (total * 20)
        let pagesPerDay = max(1, pages / total)
        let start = (day - 1) * pagesPerDay + 1
        let end = day * pagesPerDay
        return "Pages \(start)–\(end)"
    }

    private func scriptureForDay(day: Int, source: AmenStudyPlanSource, sourceTitle: String) -> String {
        // A curated rotating set of scriptures for depth over time
        let pool: [String]
        switch source {
        case .scripture: return sourceTitle
        case .devotional, .bereanAnswer:
            pool = ["Psalm 119:105","Proverbs 3:5-6","Isaiah 40:31","Matthew 6:33",
                    "Romans 8:28","Philippians 4:6-7","Colossians 3:2","James 1:5"]
        case .book, .sermon, .topic:
            pool = ["John 15:5","Hebrews 12:1-2","2 Timothy 3:16-17","Romans 12:2",
                    "Psalm 1:2-3","Joshua 1:8","1 Peter 2:2","Ephesians 4:15"]
        }
        return pool[(day - 1) % pool.count]
    }

    private func reflectionPrompt(day: Int, source: AmenStudyPlanSource) -> String {
        let prompts = [
            "What stood out to you in today's reading?",
            "How does this connect to what God is doing in your life right now?",
            "Is there a conviction, encouragement, or question stirring in you?",
            "What is one thing you want to carry with you from today?",
            "Where do you see God's character reflected in what you read?",
            "What would it look like to live this truth out this week?",
            "Write a short prayer response to what you've read."
        ]
        return prompts[(day - 1) % prompts.count]
    }

    private func prayerPrompt(day: Int, source: AmenStudyPlanSource) -> String {
        let prompts = [
            "Ask God to open your heart to receive what He wants to show you.",
            "Thank God for one specific thing from today's study.",
            "Surrender any area of resistance you felt while reading.",
            "Pray for someone who needs the truth you encountered today.",
            "Ask for wisdom to apply what you are learning.",
            "Rest in silence for 2 minutes before writing anything.",
            "Close by speaking the scripture from today back to God."
        ]
        return prompts[(day - 1) % prompts.count]
    }

    private func planTitle(source: AmenStudyPlanSource, sourceTitle: String) -> String {
        switch source {
        case .book:         return "Study: \(sourceTitle)"
        case .topic:        return "\(sourceTitle) Deep Dive"
        case .sermon:       return "After the Sermon: \(sourceTitle)"
        case .devotional:   return "Devotional: \(sourceTitle)"
        case .scripture:    return "Scripture Study: \(sourceTitle)"
        case .bereanAnswer: return "Following Up on a Berean Answer"
        }
    }

    // MARK: - Persistence

    private func persistPlan(_ plan: AmenStudyPlan) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        try? db.collection("users").document(uid)
            .collection("studyPlans").document(plan.id)
            .setData(from: plan)
    }
}
