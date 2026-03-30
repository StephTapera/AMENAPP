// GrowthLoopEngine.swift
// AMENAPP
//
// Growth Loop: Content → Behavior Change Over Time
//
// The core discipleship system:
//   Day 0: Content created (church note, verse study, sermon)
//   +24h:  Reflection prompt
//   +3d:   "Did you apply this?"
//   +7d:   "What changed?"
//   +30d:  Long-term integration check
//
// Tracks real growth metrics:
//   - Consistency (showing up)
//   - Application (doing something)
//   - Reflection depth (how deeply they engage)
//   - Obedience score (not likes — real transformation)
//
// Entry points:
//   GrowthLoopEngine.shared.startLoop(for:) async
//   GrowthLoopEngine.shared.respondToPrompt(_ promptId:response:) async
//   GrowthLoopEngine.shared.getGrowthReport() async -> GrowthReport

import Foundation
import SwiftUI
import Combine
import FirebaseFirestore
import FirebaseAuth
import UserNotifications

// MARK: - Models

/// A growth loop tracking an insight over time
struct GrowthLoop: Identifiable, Codable {
    let id: String
    let userId: String
    let sourceContent: String       // What triggered the loop
    let sourceType: GrowthSourceType
    let sourceId: String?
    let createdAt: Date
    var milestones: [GrowthMilestone]
    var status: LoopStatus
    var overallReflectionScore: Double // 0.0 - 1.0

    var isActive: Bool { status == .active }
}

enum GrowthSourceType: String, Codable {
    case churchNote = "church_note"
    case sermonAnalysis = "sermon"
    case scriptureStudy = "scripture"
    case bereanConversation = "berean_chat"
    case prayer = "prayer"
    case testimony = "testimony"
}

enum LoopStatus: String, Codable {
    case active = "active"
    case completed = "completed"
    case abandoned = "abandoned"
    case paused = "paused"
}

/// A milestone within a growth loop
struct GrowthMilestone: Identifiable, Codable {
    let id: String
    let dayOffset: Int              // Days after loop start
    let prompt: String              // The reflection question
    let type: MilestoneType
    var response: String?           // User's response
    var respondedAt: Date?
    var reflectionDepth: ReflectionQuality?
    var isCompleted: Bool { response != nil }
}

enum MilestoneType: String, Codable {
    case reflection = "reflection"      // Think about it
    case application = "application"    // Did you do it?
    case assessment = "assessment"      // What changed?
    case integration = "integration"    // Long-term check
}

enum ReflectionQuality: String, Codable {
    case shallow = "shallow"            // < 20 words, generic
    case moderate = "moderate"          // 20-50 words, some specifics
    case deep = "deep"                  // 50+ words, personal, specific
    case transformative = "transformative" // Shows real behavior change
}

/// Aggregate growth report
struct GrowthReport: Codable {
    let userId: String
    let period: String              // "week", "month", "quarter"
    let timestamp: Date

    // Core metrics
    let consistencyScore: Double    // 0-100: How regularly they engage
    let applicationScore: Double    // 0-100: How often they act
    let reflectionDepthScore: Double // 0-100: Quality of reflections
    let overallGrowthScore: Double  // Weighted composite

    // Stats
    let loopsStarted: Int
    let loopsCompleted: Int
    let milestonesResponded: Int
    let totalReflections: Int
    let averageReflectionLength: Int

    // Insights
    let topGrowthAreas: [String]
    let areasForGrowth: [String]
    let encouragement: String
}

// MARK: - GrowthLoopEngine

@MainActor
final class GrowthLoopEngine: ObservableObject {

    static let shared = GrowthLoopEngine()

    @Published var activeLoops: [GrowthLoop] = []
    @Published var pendingMilestones: [PendingMilestoneInfo] = []
    @Published var currentReport: GrowthReport?
    @Published var isLoading = false

    // Growth stats
    @Published var consistencyScore: Double = 0
    @Published var totalLoopsCompleted: Int = 0
    @Published var currentStreak: Int = 0

    struct PendingMilestoneInfo: Identifiable {
        var id: String { "\(loop.id)_\(milestone.id)" }
        let loop: GrowthLoop
        let milestone: GrowthMilestone
    }

    private let db = Firestore.firestore()
    private let aiService = ClaudeService.shared
    private var listener: ListenerRegistration?

    // Standard milestone schedule
    private let milestoneSchedule: [(dayOffset: Int, type: MilestoneType)] = [
        (1, .reflection),
        (3, .application),
        (7, .assessment),
        (30, .integration)
    ]

    private init() {
        startListening()
    }

    // MARK: - Public API

    /// Start a new growth loop for content
    func startLoop(
        content: String,
        sourceType: GrowthSourceType,
        sourceId: String? = nil
    ) async -> GrowthLoop? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }

        // Generate personalized milestones
        let milestones = await generateMilestones(for: content, sourceType: sourceType)

        let loop = GrowthLoop(
            id: UUID().uuidString,
            userId: uid,
            sourceContent: String(content.prefix(500)),
            sourceType: sourceType,
            sourceId: sourceId,
            createdAt: Date(),
            milestones: milestones,
            status: .active,
            overallReflectionScore: 0
        )

        do {
            try db.collection("users").document(uid)
                .collection("growthLoops").document(loop.id)
                .setData(from: loop)

            // Schedule notifications
            scheduleNotifications(for: loop)

            activeLoops.insert(loop, at: 0)
            return loop
        } catch {
            dlog("❌ [GrowthLoop] Start failed: \(error)")
            return nil
        }
    }

    /// Respond to a milestone prompt
    func respondToPrompt(loopId: String, milestoneId: String, response: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        let quality = assessReflectionQuality(response)

        let updates: [String: Any] = [
            "milestones": FieldValue.arrayRemove([]),  // Will use transaction
        ]

        // Use transaction to update the specific milestone
        let loopRef = db.collection("users").document(uid)
            .collection("growthLoops").document(loopId)

        do {
            try await db.runTransaction { transaction, _ in
                let doc = try transaction.getDocument(loopRef)
                guard var loop = try? doc.data(as: GrowthLoop.self) else { return nil }

                if let idx = loop.milestones.firstIndex(where: { $0.id == milestoneId }) {
                    loop.milestones[idx].response = response
                    loop.milestones[idx].respondedAt = Date()
                    loop.milestones[idx].reflectionDepth = quality
                }

                // Check if all milestones are complete
                let allComplete = loop.milestones.allSatisfy { $0.isCompleted }
                if allComplete {
                    loop.status = .completed
                }

                // Recalculate score
                let scores = loop.milestones.compactMap { $0.reflectionDepth }
                let avgScore = scores.isEmpty ? 0.0 : scores.reduce(0.0) { total, q in
                    total + (q == .shallow ? 0.25 : q == .moderate ? 0.5 : q == .deep ? 0.75 : 1.0)
                } / Double(scores.count)
                loop.overallReflectionScore = avgScore

                try transaction.setData(from: loop, forDocument: loopRef)
                return nil
            }

            // Update local state
            if let idx = activeLoops.firstIndex(where: { $0.id == loopId }),
               let mIdx = activeLoops[idx].milestones.firstIndex(where: { $0.id == milestoneId }) {
                activeLoops[idx].milestones[mIdx].response = response
                activeLoops[idx].milestones[mIdx].respondedAt = Date()
                activeLoops[idx].milestones[mIdx].reflectionDepth = quality
            }

            // Remove from pending
            pendingMilestones.removeAll { $0.milestone.id == milestoneId }
        } catch {
            dlog("❌ [GrowthLoop] Respond failed: \(error)")
        }
    }

    /// Get a growth report for a period
    func getGrowthReport(period: String = "month") async -> GrowthReport? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }

        isLoading = true
        defer { isLoading = false }

        // Gather data
        let allLoops = activeLoops + (try? await fetchCompletedLoops(uid: uid)) ?? []
        let totalMilestones = allLoops.flatMap { $0.milestones }
        let respondedMilestones = totalMilestones.filter { $0.isCompleted }

        let consistency = allLoops.isEmpty ? 0.0 : Double(allLoops.filter { $0.status == .completed || $0.status == .active }.count) / Double(allLoops.count) * 100

        let avgDepth: Double = {
            let scores = respondedMilestones.compactMap { $0.reflectionDepth }
            guard !scores.isEmpty else { return 0 }
            return scores.reduce(0.0) { total, q in
                total + (q == .shallow ? 25 : q == .moderate ? 50 : q == .deep ? 75 : 100)
            } / Double(scores.count)
        }()

        let applicationMilestones = respondedMilestones.filter { $0.type == .application }
        let applicationRate = totalMilestones.filter({ $0.type == .application }).isEmpty ? 0.0 :
            Double(applicationMilestones.count) / Double(totalMilestones.filter { $0.type == .application }.count) * 100

        let avgLength = respondedMilestones.isEmpty ? 0 :
            respondedMilestones.reduce(0) { $0 + ($1.response?.count ?? 0) } / respondedMilestones.count

        // AI-generated insights
        let insights = await generateGrowthInsights(
            consistency: consistency,
            applicationRate: applicationRate,
            reflectionDepth: avgDepth,
            loops: allLoops
        )

        let report = GrowthReport(
            userId: uid,
            period: period,
            timestamp: Date(),
            consistencyScore: consistency,
            applicationScore: applicationRate,
            reflectionDepthScore: avgDepth,
            overallGrowthScore: (consistency + applicationRate + avgDepth) / 3,
            loopsStarted: allLoops.count,
            loopsCompleted: allLoops.filter { $0.status == .completed }.count,
            milestonesResponded: respondedMilestones.count,
            totalReflections: respondedMilestones.count,
            averageReflectionLength: avgLength,
            topGrowthAreas: insights.strengths,
            areasForGrowth: insights.areas,
            encouragement: insights.encouragement
        )

        currentReport = report
        return report
    }

    // MARK: - Milestone Generation

    private func generateMilestones(for content: String, sourceType: GrowthSourceType) async -> [GrowthMilestone] {
        let prompt = """
        Generate growth loop milestones for this content. Return as JSON array:
        [
            {"id": "m1", "dayOffset": 1, "prompt": "A reflection question for day 1", "type": "reflection"},
            {"id": "m2", "dayOffset": 3, "prompt": "Did you apply this? How?", "type": "application"},
            {"id": "m3", "dayOffset": 7, "prompt": "What has changed in your life?", "type": "assessment"},
            {"id": "m4", "dayOffset": 30, "prompt": "How has this shaped you long-term?", "type": "integration"}
        ]

        Content: \(String(content.prefix(1000)))
        Source: \(sourceType.rawValue)

        Make prompts specific to the content. Be warm and encouraging.
        Types: reflection, application, assessment, integration
        Return ONLY valid JSON array.
        """

        do {
            let response = try await aiService.sendMessage(prompt)
            let cleaned = cleanJSONArray(response)
            let data = Data(cleaned.utf8)
            return try JSONDecoder().decode([GrowthMilestone].self, from: data)
        } catch {
            // Fallback generic milestones
            return milestoneSchedule.enumerated().map { idx, schedule in
                GrowthMilestone(
                    id: "m\(idx)",
                    dayOffset: schedule.dayOffset,
                    prompt: defaultPrompt(for: schedule.type, day: schedule.dayOffset),
                    type: schedule.type
                )
            }
        }
    }

    private func defaultPrompt(for type: MilestoneType, day: Int) -> String {
        switch type {
        case .reflection: return "Take a moment to reflect on what you learned. What stood out most?"
        case .application: return "Have you been able to apply what you learned? What did you do?"
        case .assessment: return "Looking back at this week, what has changed in how you think or act?"
        case .integration: return "How has this insight shaped your life over the past month?"
        }
    }

    // MARK: - Quality Assessment

    private func assessReflectionQuality(_ response: String) -> ReflectionQuality {
        let wordCount = response.split(separator: " ").count

        if wordCount < 10 { return .shallow }
        if wordCount < 30 { return .moderate }

        // Check for personal indicators
        let personalWords = ["I ", "my ", "me ", "changed", "realized", "learned", "felt", "decided", "started", "stopped"]
        let hasPersonal = personalWords.contains { response.localizedCaseInsensitiveContains($0) }

        if wordCount >= 50 && hasPersonal { return .transformative }
        if wordCount >= 30 { return .deep }

        return .moderate
    }

    // MARK: - Notifications

    private func scheduleNotifications(for loop: GrowthLoop) {
        let center = UNUserNotificationCenter.current()

        for milestone in loop.milestones {
            let content = UNMutableNotificationContent()
            content.title = "Growth Check-In"
            content.body = milestone.prompt
            content.sound = .default
            content.userInfo = [
                "type": "growth_loop",
                "loopId": loop.id,
                "milestoneId": milestone.id
            ]

            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: TimeInterval(milestone.dayOffset * 86400),
                repeats: false
            )

            let request = UNNotificationRequest(
                identifier: "growth_\(loop.id)_\(milestone.id)",
                content: content,
                trigger: trigger
            )

            center.add(request)
        }
    }

    // MARK: - Data Fetching

    private func startListening() {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        listener = db.collection("users").document(uid)
            .collection("growthLoops")
            .whereField("status", isEqualTo: LoopStatus.active.rawValue)
            .order(by: "createdAt", descending: true)
            .limit(to: 20)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let docs = snapshot?.documents else { return }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.activeLoops = docs.compactMap { try? $0.data(as: GrowthLoop.self) }
                    self.updatePendingMilestones()
                }
            }
    }

    private func updatePendingMilestones() {
        let now = Date()
        var pending: [PendingMilestoneInfo] = []

        for loop in activeLoops {
            for milestone in loop.milestones where !milestone.isCompleted {
                let dueDate = Calendar.current.date(byAdding: .day, value: milestone.dayOffset, to: loop.createdAt) ?? loop.createdAt
                if dueDate <= now {
                    pending.append(PendingMilestoneInfo(loop: loop, milestone: milestone))
                }
            }
        }

        pendingMilestones = pending
    }

    private func fetchCompletedLoops(uid: String) async throws -> [GrowthLoop] {
        let snapshot = try await db.collection("users").document(uid)
            .collection("growthLoops")
            .whereField("status", isEqualTo: LoopStatus.completed.rawValue)
            .order(by: "createdAt", descending: true)
            .limit(to: 50)
            .getDocuments()

        return snapshot.documents.compactMap { try? $0.data(as: GrowthLoop.self) }
    }

    // MARK: - AI Insights

    private struct GrowthInsights {
        let strengths: [String]
        let areas: [String]
        let encouragement: String
    }

    private func generateGrowthInsights(consistency: Double, applicationRate: Double, reflectionDepth: Double, loops: [GrowthLoop]) async -> GrowthInsights {
        let prompt = """
        Based on this user's growth data, provide brief insights:
        - Consistency: \(Int(consistency))%
        - Application rate: \(Int(applicationRate))%
        - Reflection depth: \(Int(reflectionDepth))%
        - Loops started: \(loops.count)
        - Loops completed: \(loops.filter { $0.status == .completed }.count)

        Return as JSON:
        {
            "strengths": ["2-3 areas where they're growing well"],
            "areas": ["1-2 areas to focus on"],
            "encouragement": "A warm, specific encouragement (2-3 sentences)"
        }

        Be pastoral and encouraging. Return ONLY valid JSON.
        """

        do {
            let response = try await aiService.sendMessage(prompt)
            let data = Data(cleanJSON(response).utf8)

            struct InsightsResponse: Codable {
                let strengths: [String]
                let areas: [String]
                let encouragement: String
            }

            let parsed = try JSONDecoder().decode(InsightsResponse.self, from: data)
            return GrowthInsights(strengths: parsed.strengths, areas: parsed.areas, encouragement: parsed.encouragement)
        } catch {
            return GrowthInsights(
                strengths: ["Consistent engagement"],
                areas: ["Deeper reflection"],
                encouragement: "Keep going — every step of obedience matters."
            )
        }
    }

    // MARK: - Helpers

    private func cleanJSON(_ response: String) -> String {
        var s = response
        if let start = s.range(of: "{"), let end = s.range(of: "}", options: .backwards) {
            s = String(s[start.lowerBound...end.upperBound])
        }
        return s
    }

    private func cleanJSONArray(_ response: String) -> String {
        var s = response
        if let start = s.range(of: "["), let end = s.range(of: "]", options: .backwards) {
            s = String(s[start.lowerBound...end.upperBound])
        }
        return s
    }
}
