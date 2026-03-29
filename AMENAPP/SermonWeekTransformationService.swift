//
//  SermonWeekTransformationService.swift
//  AMENAPP
//
//  Sermon → Week Transformation System
//
//  After a Sunday sermon, this service transforms the key points and verses
//  into a structured daily prompt system for the week (Mon–Sat):
//    - Day 1: Identify (recognize the truth in your life)
//    - Day 2: Meditate (go deeper into the scripture)
//    - Day 3: Pray (bring it to God specifically)
//    - Day 4: Act (take a concrete obedience step)
//    - Day 5: Share (encourage someone with what you've learned)
//    - Day 6: Reflect (evaluate the week's impact)
//
//  Input: Sermon notes (from Church Notes), key verses, topic
//  Output: 6-day structured plan with daily prompts + follow-ups
//
//  Integration:
//    - Church Notes: auto-generates plan from saved sermon notes
//    - FollowUpEngine: each day becomes a scheduled follow-up
//    - PersonalSpiritualGraph: records engagement with sermon content
//    - ScriptureIntelligenceEngine: matches sermon themes to context tags
//
//  Architecture:
//    SermonWeekTransformationService (singleton, @MainActor)
//    ├── SermonInput                 (what the church/user provides)
//    ├── SermonWeekPlan              (the generated 6-day plan)
//    ├── SermonDayPrompt             (one day's prompt)
//    ├── generateWeekPlan()          (AI-powered plan generation)
//    ├── generateWeekPlanLocal()     (offline fallback)
//    └── activatePlan()              (schedules follow-ups)
//

import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

// MARK: - Sermon Input

/// The input from a Sunday sermon — can come from church upload or user's notes.
struct SermonInput: Codable {
    let title: String                    // Sermon title
    let topic: String                    // Main theme (e.g., "forgiveness")
    let keyVerses: [String]              // Scripture references
    let keyPoints: [String]              // Main points from the sermon
    let pastorName: String?              // Optional: who preached
    let churchId: String?               // Optional: church identifier
    let date: Date                       // When the sermon was preached
    let sourceNoteId: String?           // Optional: linked church note ID
}

// MARK: - Day Focus

/// The focus type for each day of the week plan.
enum SermonDayFocus: String, Codable, CaseIterable {
    case identify  = "identify"     // Day 1: Recognize the truth
    case meditate  = "meditate"     // Day 2: Go deeper
    case pray      = "pray"         // Day 3: Bring to God
    case act       = "act"          // Day 4: Obedience step
    case share     = "share"        // Day 5: Encourage others
    case reflect   = "reflect"      // Day 6: Evaluate impact

    var dayNumber: Int {
        switch self {
        case .identify: return 1
        case .meditate: return 2
        case .pray:     return 3
        case .act:      return 4
        case .share:    return 5
        case .reflect:  return 6
        }
    }

    var displayName: String {
        switch self {
        case .identify: return "Identify"
        case .meditate: return "Meditate"
        case .pray:     return "Pray"
        case .act:      return "Act"
        case .share:    return "Share"
        case .reflect:  return "Reflect"
        }
    }

    var description: String {
        switch self {
        case .identify: return "Recognize how this truth applies to your life"
        case .meditate: return "Go deeper into the scripture"
        case .pray:     return "Bring this area to God specifically"
        case .act:      return "Take a concrete step of obedience"
        case .share:    return "Encourage someone with what you've learned"
        case .reflect:  return "Evaluate the week's impact on your life"
        }
    }

    var icon: String {
        switch self {
        case .identify: return "eye.fill"
        case .meditate: return "book.fill"
        case .pray:     return "hands.sparkles.fill"
        case .act:      return "figure.walk"
        case .share:    return "person.2.fill"
        case .reflect:  return "chart.line.uptrend.xyaxis"
        }
    }
}

// MARK: - Sermon Day Prompt

/// A single day's prompt in the week plan.
struct SermonDayPrompt: Identifiable, Codable {
    let id: String
    let dayNumber: Int                   // 1–6
    let focus: SermonDayFocus
    let title: String                    // e.g., "Identify your resentment"
    let prompt: String                   // The main question/action
    let scriptureReference: String       // Verse to read/meditate on
    let actionStep: String               // Concrete thing to do
    let reflectionQuestion: String       // Question to journal about
    let scheduledDate: Date              // When this day's prompt is due
    var isCompleted: Bool
    var completedAt: Date?
}

// MARK: - Sermon Week Plan

/// The full 6-day plan generated from a sermon.
struct SermonWeekPlan: Identifiable, Codable {
    let id: String
    let userId: String
    let sermonInput: SermonInput
    var days: [SermonDayPrompt]
    let createdAt: Date
    var isActive: Bool
    var completedDays: Int

    var progress: Double {
        guard !days.isEmpty else { return 0 }
        return Double(days.filter(\.isCompleted).count) / Double(days.count)
    }

    var currentDay: SermonDayPrompt? {
        days.first { !$0.isCompleted && $0.scheduledDate <= Date() }
    }

    var isComplete: Bool {
        days.allSatisfy(\.isCompleted)
    }
}

// MARK: - Service

@MainActor
final class SermonWeekTransformationService: ObservableObject {

    static let shared = SermonWeekTransformationService()

    @Published private(set) var activePlans: [SermonWeekPlan] = []
    @Published private(set) var isGenerating = false

    private let db = Firestore.firestore()
    private let functions = Functions.functions()
    private let localStorageKey = "sermon_week_plans_v1"
    private let maxActivePlans = 5

    private init() {
        loadLocalPlans()
    }

    // MARK: - Generate Week Plan (AI-Powered)

    /// Generates a 6-day plan from sermon input using the cloud function.
    /// Falls back to local generation if the cloud call fails.
    func generateWeekPlan(from input: SermonInput) async -> SermonWeekPlan? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }

        // Don't exceed max active plans
        let activeCount = activePlans.filter(\.isActive).count
        guard activeCount < maxActivePlans else {
            dlog("[SermonWeek] Max active plans reached (\(maxActivePlans))")
            return nil
        }

        isGenerating = true
        defer { isGenerating = false }

        // Try AI-powered generation
        if let plan = await generateViaCloudFunction(input: input, userId: uid) {
            activePlans.append(plan)
            saveLocalPlans()
            await persistToFirestore(plan)
            return plan
        }

        // Fallback to local generation
        let plan = generateWeekPlanLocal(from: input, userId: uid)
        activePlans.append(plan)
        saveLocalPlans()
        await persistToFirestore(plan)
        return plan
    }

    // MARK: - Cloud Function Generation

    private func generateViaCloudFunction(input: SermonInput, userId: String) async -> SermonWeekPlan? {
        do {
            let requestData: [String: Any] = [
                "title": input.title,
                "topic": input.topic,
                "keyVerses": input.keyVerses,
                "keyPoints": input.keyPoints,
                "pastorName": input.pastorName ?? "",
                "date": ISO8601DateFormatter().string(from: input.date)
            ]

            let result = try await functions.httpsCallable("bereanSermonWeekPlan").call(requestData)

            guard let responseData = result.data as? [String: Any],
                  let daysArray = responseData["days"] as? [[String: Any]] else {
                return nil
            }

            let calendar = Calendar.current
            let startDate = calendar.date(byAdding: .day, value: 1, to: input.date) ?? Date()

            var days: [SermonDayPrompt] = []
            for (index, dayData) in daysArray.prefix(6).enumerated() {
                let focus = SermonDayFocus.allCases[index]
                let scheduledDate = calendar.date(byAdding: .day, value: index, to: startDate) ?? Date()

                days.append(SermonDayPrompt(
                    id: UUID().uuidString,
                    dayNumber: index + 1,
                    focus: focus,
                    title: dayData["title"] as? String ?? "\(focus.displayName): \(input.topic)",
                    prompt: dayData["prompt"] as? String ?? focus.description,
                    scriptureReference: dayData["scriptureReference"] as? String ?? (input.keyVerses.first ?? ""),
                    actionStep: dayData["actionStep"] as? String ?? "Reflect on today's focus.",
                    reflectionQuestion: dayData["reflectionQuestion"] as? String ?? "What did God show you today?",
                    scheduledDate: scheduledDate,
                    isCompleted: false,
                    completedAt: nil
                ))
            }

            return SermonWeekPlan(
                id: UUID().uuidString,
                userId: userId,
                sermonInput: input,
                days: days,
                createdAt: Date(),
                isActive: true,
                completedDays: 0
            )

        } catch {
            dlog("[SermonWeek] Cloud function failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Local Fallback Generation

    /// Generates a plan without AI — uses template-based approach.
    func generateWeekPlanLocal(from input: SermonInput, userId: String) -> SermonWeekPlan {
        let calendar = Calendar.current
        let startDate = calendar.date(byAdding: .day, value: 1, to: input.date) ?? Date()
        let topic = input.topic
        let mainVerse = input.keyVerses.first ?? "Psalm 119:105"

        let days: [SermonDayPrompt] = SermonDayFocus.allCases.enumerated().map { (index, focus) in
            let scheduledDate = calendar.date(byAdding: .day, value: index, to: startDate) ?? Date()
            let verse = index < input.keyVerses.count ? input.keyVerses[index] : mainVerse

            let (title, prompt, action, question) = templateForFocus(focus, topic: topic, verse: verse, keyPoints: input.keyPoints)

            return SermonDayPrompt(
                id: UUID().uuidString,
                dayNumber: index + 1,
                focus: focus,
                title: title,
                prompt: prompt,
                scriptureReference: verse,
                actionStep: action,
                reflectionQuestion: question,
                scheduledDate: scheduledDate,
                isCompleted: false,
                completedAt: nil
            )
        }

        return SermonWeekPlan(
            id: UUID().uuidString,
            userId: userId,
            sermonInput: input,
            days: days,
            createdAt: Date(),
            isActive: true,
            completedDays: 0
        )
    }

    private func templateForFocus(
        _ focus: SermonDayFocus,
        topic: String,
        verse: String,
        keyPoints: [String]
    ) -> (title: String, prompt: String, action: String, question: String) {
        let firstPoint = keyPoints.first ?? topic

        switch focus {
        case .identify:
            return (
                "Identify: \(topic) in your life",
                "Read \(verse). Where do you see \(topic.lowercased()) showing up in your daily life?",
                "Write down one specific area where \(topic.lowercased()) applies to you right now.",
                "What part of Sunday's message hit you hardest? Why?"
            )
        case .meditate:
            return (
                "Meditate: Going deeper into \(verse)",
                "Read \(verse) slowly three times. What new detail do you notice?",
                "Write out \(verse) by hand. Circle the word that stands out most.",
                "What is God saying to you personally through this verse?"
            )
        case .pray:
            return (
                "Pray: Bring \(topic) to God",
                "Use \(verse) as a prayer framework. Pray specifically about \(firstPoint.lowercased()).",
                "Spend 10 minutes in focused prayer about this area. Write your prayer out.",
                "What did you sense God saying back to you in prayer?"
            )
        case .act:
            return (
                "Act: Live out \(topic) today",
                "Based on \(verse), take one concrete step of obedience related to \(topic.lowercased()).",
                "Do one thing today that demonstrates \(topic.lowercased()) in a real situation.",
                "What happened when you put this into practice? What was hard about it?"
            )
        case .share:
            return (
                "Share: Encourage someone with \(topic)",
                "Who in your life needs to hear about \(topic.lowercased()) right now?",
                "Share \(verse) with one person today — text, call, or in person.",
                "How did it feel to share? How did they respond?"
            )
        case .reflect:
            return (
                "Reflect: Your week with \(topic)",
                "Look back on this week. How has \(topic.lowercased()) shaped your thoughts and actions?",
                "Write a brief reflection: What changed in you this week?",
                "What will you carry forward from this sermon into next week?"
            )
        }
    }

    // MARK: - Activate Plan (Schedule Follow-Ups)

    /// Activates a plan by scheduling follow-ups for each day.
    func activatePlan(_ planId: String) async {
        guard let plan = activePlans.first(where: { $0.id == planId }) else { return }

        for day in plan.days {
            await FollowUpEngine.shared.scheduleFollowUp(
                topic: .sermonWeek,
                contextSummary: "\(day.focus.displayName): \(day.title)",
                scriptureReference: day.scriptureReference,
                interval: .twentyFourHours,
                chainAll: false
            )
        }
    }

    // MARK: - Complete Day

    /// Marks a day as completed in a plan.
    func completeDay(_ dayId: String, in planId: String) async {
        guard let planIndex = activePlans.firstIndex(where: { $0.id == planId }),
              let dayIndex = activePlans[planIndex].days.firstIndex(where: { $0.id == dayId }) else {
            return
        }

        activePlans[planIndex].days[dayIndex].isCompleted = true
        activePlans[planIndex].days[dayIndex].completedAt = Date()
        activePlans[planIndex].completedDays = activePlans[planIndex].days.filter(\.isCompleted).count

        // Check if plan is complete
        if activePlans[planIndex].isComplete {
            activePlans[planIndex].isActive = false

            // Record to spiritual graph
            await PersonalSpiritualGraphService.shared.recordRhythm(.scripture, source: .bereanChat)
            await PersonalSpiritualGraphService.shared.recordObedienceAction(
                category: "Completed sermon week plan: \(activePlans[planIndex].sermonInput.topic)",
                source: .churchNotes
            )
        }

        saveLocalPlans()
        await persistToFirestore(activePlans[planIndex])
    }

    // MARK: - Get Current Day Prompt

    /// Returns the prompt for today across all active plans.
    func todaysPrompts() -> [SermonDayPrompt] {
        activePlans
            .filter(\.isActive)
            .compactMap(\.currentDay)
    }

    /// Builds a system prompt block for Berean about active sermon week plans.
    func systemPromptForActivePlans() -> String {
        let todays = todaysPrompts()
        guard !todays.isEmpty else { return "" }

        var lines: [String] = []
        lines.append("--- Sermon Week Plans ---")
        lines.append("The user has active sermon-to-week plans. Today's focus:")
        lines.append("")

        for day in todays {
            lines.append("Day \(day.dayNumber) (\(day.focus.displayName)): \(day.title)")
            lines.append("Scripture: \(day.scriptureReference)")
            lines.append("Action: \(day.actionStep)")
            lines.append("")
        }

        lines.append("Weave these naturally into conversation if relevant.")
        lines.append("--- End Sermon Week ---")
        return lines.joined(separator: "\n")
    }

    // MARK: - Persistence

    private func loadLocalPlans() {
        guard let data = UserDefaults.standard.data(forKey: localStorageKey),
              let plans = try? JSONDecoder().decode([SermonWeekPlan].self, from: data) else {
            return
        }
        activePlans = plans
    }

    private func saveLocalPlans() {
        guard let data = try? JSONEncoder().encode(activePlans) else { return }
        UserDefaults.standard.set(data, forKey: localStorageKey)
    }

    private func persistToFirestore(_ plan: SermonWeekPlan) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        do {
            let data = try Firestore.Encoder().encode(plan)
            try await db.collection("users").document(uid)
                .collection("sermonWeekPlans")
                .document(plan.id)
                .setData(data, merge: true)
        } catch {
            dlog("[SermonWeek] Firestore persist failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Delete

    func deletePlan(_ planId: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        activePlans.removeAll { $0.id == planId }
        saveLocalPlans()

        do {
            try await db.collection("users").document(uid)
                .collection("sermonWeekPlans")
                .document(planId)
                .delete()
        } catch {
            dlog("[SermonWeek] Delete failed: \(error.localizedDescription)")
        }
    }

    func reset() {
        activePlans.removeAll()
        UserDefaults.standard.removeObject(forKey: localStorageKey)
    }
}
