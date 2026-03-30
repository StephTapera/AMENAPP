// ActionEngine.swift
// AMENAPP
//
// Action Engine: Insight → Execution
//
// Every Berean response can generate actionable items:
//   - "Do this now" → immediate action
//   - "Save for later" → saved to action queue
//   - "Remind me" → scheduled notification
//
// Actions are stored in Firestore, linked to Growth Loop,
// and tracked for completion.
//
// Entry points:
//   ActionEngine.shared.createAction(from:type:) async -> BereanAction
//   ActionEngine.shared.completeAction(_ id:) async
//   ActionEngine.shared.scheduleReminder(for:at:) async

import Foundation
import SwiftUI
import Combine
import FirebaseFirestore
import FirebaseAuth
import UserNotifications

// MARK: - Models

/// A concrete action generated from AI insight
struct BereanAction: Identifiable, Codable {
    let id: String
    let userId: String
    let content: String             // What to do
    let context: String             // Where this came from (verse, sermon, etc.)
    let type: ActionType
    let category: ActionCategory
    let difficulty: ActionDifficulty
    let relatedVerse: String?
    let createdAt: Date
    var completedAt: Date?
    var status: ActionStatus
    var reminderDate: Date?
    var reflectionNote: String?     // User's reflection after completing

    // Source tracking
    let sourceType: ActionSourceType
    let sourceId: String?           // ID of sermon analysis, conversation, etc.

    var isCompleted: Bool { status == .completed }
}

enum ActionType: String, Codable {
    case doNow = "do_now"           // Immediate action
    case savedForLater = "saved"     // In queue
    case scheduled = "scheduled"     // Has a reminder
    case recurring = "recurring"     // Repeating action
}

enum ActionCategory: String, Codable {
    case prayer = "prayer"
    case outreach = "outreach"      // Reach out to someone
    case study = "study"            // Bible study
    case reflection = "reflection"  // Journal/reflect
    case service = "service"        // Serve someone
    case worship = "worship"
    case rest = "rest"              // Sabbath/rest
    case confession = "confession"
    case gratitude = "gratitude"
    case discipline = "discipline"  // Spiritual discipline
    case general = "general"
}

enum ActionStatus: String, Codable {
    case pending = "pending"
    case inProgress = "in_progress"
    case completed = "completed"
    case skipped = "skipped"
    case overdue = "overdue"
}

enum ActionDifficulty: String, Codable {
    case easy = "easy"
    case moderate = "moderate"
    case challenging = "challenging"
}

enum ActionSourceType: String, Codable {
    case bereanChat = "berean_chat"
    case sermonAnalysis = "sermon_analysis"
    case scriptureVision = "scripture_vision"
    case growthLoop = "growth_loop"
    case decisionEngine = "decision_engine"
    case manual = "manual"
}

// MARK: - ActionEngine

@MainActor
final class ActionEngine: ObservableObject {

    static let shared = ActionEngine()

    @Published var pendingActions: [BereanAction] = []
    @Published var completedActions: [BereanAction] = []
    @Published var todayActions: [BereanAction] = []
    @Published var isLoading = false

    // Stats
    @Published var totalCompleted: Int = 0
    @Published var currentStreak: Int = 0
    @Published var weeklyCompletionRate: Double = 0

    private let db = Firestore.firestore()
    private let aiService = ClaudeService.shared
    private var listener: ListenerRegistration?

    private init() {
        startListening()
    }

    deinit {
        listener?.remove()
    }

    // MARK: - Public API

    /// Create an action from AI insight
    func createAction(
        content: String,
        context: String,
        type: ActionType = .savedForLater,
        category: ActionCategory = .general,
        difficulty: ActionDifficulty = .easy,
        relatedVerse: String? = nil,
        sourceType: ActionSourceType = .bereanChat,
        sourceId: String? = nil
    ) async -> BereanAction? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }

        let action = BereanAction(
            id: UUID().uuidString,
            userId: uid,
            content: content,
            context: context,
            type: type,
            category: category,
            difficulty: difficulty,
            relatedVerse: relatedVerse,
            createdAt: Date(),
            completedAt: nil,
            status: .pending,
            reminderDate: nil,
            reflectionNote: nil,
            sourceType: sourceType,
            sourceId: sourceId
        )

        do {
            try await saveAction(action)
            pendingActions.insert(action, at: 0)
            return action
        } catch {
            dlog("❌ [ActionEngine] Create failed: \(error)")
            return nil
        }
    }

    /// Generate AI-suggested actions from a response
    func generateActions(from response: String, context: String) async -> [BereanAction] {
        guard let uid = Auth.auth().currentUser?.uid else { return [] }

        let prompt = """
        From this Berean AI response, extract 1-3 concrete, actionable steps the user can take.
        Return as JSON array:
        [
            {
                "content": "Specific action to take",
                "category": "prayer|outreach|study|reflection|service|worship|rest|confession|gratitude|discipline|general",
                "difficulty": "easy|moderate|challenging",
                "relatedVerse": "Verse reference or null",
                "timeframe": "now|today|this_week"
            }
        ]

        Response: \(String(response.prefix(2000)))
        Context: \(context)

        Be specific and practical. Return ONLY valid JSON array.
        """

        do {
            let aiResponse = try await aiService.sendMessage(prompt)
            let cleaned = cleanJSONArray(aiResponse)
            let data = Data(cleaned.utf8)

            struct ActionSuggestion: Codable {
                let content: String
                let category: String
                let difficulty: String
                let relatedVerse: String?
                let timeframe: String
            }

            let suggestions = try JSONDecoder().decode([ActionSuggestion].self, from: data)

            var actions: [BereanAction] = []
            for suggestion in suggestions {
                let actionType: ActionType = suggestion.timeframe == "now" ? .doNow : .savedForLater
                let cat = ActionCategory(rawValue: suggestion.category) ?? .general
                let diff = ActionDifficulty(rawValue: suggestion.difficulty) ?? .easy

                let action = BereanAction(
                    id: UUID().uuidString,
                    userId: uid,
                    content: suggestion.content,
                    context: context,
                    type: actionType,
                    category: cat,
                    difficulty: diff,
                    relatedVerse: suggestion.relatedVerse,
                    createdAt: Date(),
                    status: .pending,
                    sourceType: .bereanChat,
                    sourceId: nil
                )
                actions.append(action)
                try? await saveAction(action)
            }

            pendingActions.insert(contentsOf: actions, at: 0)
            return actions
        } catch {
            return []
        }
    }

    /// Mark an action as completed
    func completeAction(_ actionId: String, reflection: String? = nil) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        var updateData: [String: Any] = [
            "status": ActionStatus.completed.rawValue,
            "completedAt": Timestamp(date: Date())
        ]
        if let reflection = reflection {
            updateData["reflectionNote"] = reflection
        }

        do {
            try await db.collection("users").document(uid)
                .collection("actions").document(actionId)
                .updateData(updateData)

            if let idx = pendingActions.firstIndex(where: { $0.id == actionId }) {
                var action = pendingActions.remove(at: idx)
                action.status = .completed
                action.completedAt = Date()
                action.reflectionNote = reflection
                completedActions.insert(action, at: 0)
            }

            totalCompleted += 1
            updateStreak()
        } catch {
            dlog("❌ [ActionEngine] Complete failed: \(error)")
        }
    }

    /// Schedule a reminder for an action
    func scheduleReminder(for actionId: String, at date: Date) async {
        guard let action = pendingActions.first(where: { $0.id == actionId }) else { return }

        let content = UNMutableNotificationContent()
        content.title = "Action Reminder"
        content.body = action.content
        content.sound = .default
        content.userInfo = ["type": "action_reminder", "actionId": actionId]

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(date.timeIntervalSinceNow, 60),
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: "action_\(actionId)",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request)

        // Update Firestore
        guard let uid = Auth.auth().currentUser?.uid else { return }
        try? await db.collection("users").document(uid)
            .collection("actions").document(actionId)
            .updateData([
                "reminderDate": Timestamp(date: date),
                "type": ActionType.scheduled.rawValue
            ])
    }

    // MARK: - Listening

    private func startListening() {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        listener = db.collection("users").document(uid)
            .collection("actions")
            .order(by: "createdAt", descending: true)
            .limit(to: 50)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let docs = snapshot?.documents else { return }

                Task { @MainActor [weak self] in
                    guard let self else { return }
                    var pending: [BereanAction] = []
                    var completed: [BereanAction] = []

                    for doc in docs {
                        guard let action = try? doc.data(as: BereanAction.self) else { continue }
                        if action.isCompleted {
                            completed.append(action)
                        } else {
                            pending.append(action)
                        }
                    }

                    self.pendingActions = pending
                    self.completedActions = completed
                    self.totalCompleted = completed.count

                    // Today's actions
                    let calendar = Calendar.current
                    self.todayActions = pending.filter {
                        $0.type == .doNow || calendar.isDateInToday($0.createdAt)
                    }

                    self.updateStreak()
                }
            }
    }

    private func updateStreak() {
        let calendar = Calendar.current
        var streak = 0
        var checkDate = Date()

        while true {
            let hasCompletion = completedActions.contains { action in
                guard let completed = action.completedAt else { return false }
                return calendar.isDate(completed, inSameDayAs: checkDate)
            }

            if hasCompletion {
                streak += 1
                checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
            } else {
                break
            }
        }

        currentStreak = streak
    }

    // MARK: - Persistence

    private func saveAction(_ action: BereanAction) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        try db.collection("users").document(uid)
            .collection("actions").document(action.id)
            .setData(from: action)
    }

    private func cleanJSONArray(_ response: String) -> String {
        var s = response
        if let start = s.range(of: "["), let end = s.range(of: "]", options: .backwards) {
            s = String(s[start.lowerBound...end.upperBound])
        }
        return s
    }
}

// MARK: - Action Card View

struct ActionCardView: View {
    let action: BereanAction
    let onComplete: (String?) -> Void
    let onRemind: () -> Void

    @State private var showReflection = false
    @State private var reflectionText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: categoryIcon(action.category))
                    .foregroundStyle(categoryColor(action.category))

                Text(action.content)
                    .font(.subheadline)
                    .lineLimit(3)

                Spacer()

                difficultyBadge(action.difficulty)
            }

            if let verse = action.relatedVerse {
                Text(verse)
                    .font(.caption)
                    .foregroundStyle(.blue)
            }

            HStack(spacing: 12) {
                Button {
                    showReflection = true
                } label: {
                    Label("Done", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                Button {
                    onRemind()
                } label: {
                    Label("Remind Me", systemImage: "bell.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .alert("Reflect on This", isPresented: $showReflection) {
            TextField("What did you learn?", text: $reflectionText)
            Button("Save") { onComplete(reflectionText.isEmpty ? nil : reflectionText) }
            Button("Skip Reflection") { onComplete(nil) }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func categoryIcon(_ cat: ActionCategory) -> String {
        switch cat {
        case .prayer: return "hands.sparkles.fill"
        case .outreach: return "person.wave.2.fill"
        case .study: return "book.fill"
        case .reflection: return "brain.head.profile.fill"
        case .service: return "heart.fill"
        case .worship: return "music.note"
        case .rest: return "moon.fill"
        case .confession: return "bubble.left.fill"
        case .gratitude: return "star.fill"
        case .discipline: return "figure.strengthtraining.traditional"
        case .general: return "target"
        }
    }

    private func categoryColor(_ cat: ActionCategory) -> Color {
        switch cat {
        case .prayer: return .purple
        case .outreach: return .blue
        case .study: return .indigo
        case .reflection: return .teal
        case .service: return .pink
        case .worship: return .orange
        case .rest: return .mint
        case .confession: return .gray
        case .gratitude: return .yellow
        case .discipline: return .red
        case .general: return .secondary
        }
    }

    private func difficultyBadge(_ diff: ActionDifficulty) -> some View {
        Text(diff.rawValue.capitalized)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background({
                switch diff {
                case .easy: return Color.green.opacity(0.2)
                case .moderate: return Color.orange.opacity(0.2)
                case .challenging: return Color.red.opacity(0.2)
                }
            }() as Color)
            .clipShape(Capsule())
    }
}
