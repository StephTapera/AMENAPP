//
//  BereanActionEngine.swift
//  AMENAPP
//
//  Turns Berean insights into executable actions stored in Firestore.
//  Moves users from content → behavior change through saveable, completable actions.
//

import Foundation
import Combine
import UserNotifications
import FirebaseAuth
import FirebaseFirestore

// MARK: - Action Models

struct BereanAction: Codable, Identifiable {
    var id: String = UUID().uuidString
    var title: String
    var description: String
    var type: ActionType
    var linkedNoteId: String?
    var linkedVerse: String?
    var dueDate: Date?
    var reminderDate: Date?
    var isCompleted: Bool = false
    var completedAt: Date?
    var createdAt: Date = Date()
    var source: ActionSource

    enum ActionType: String, Codable, CaseIterable {
        case pray, reflect, reach_out, read, study, journal, apply, share

        var icon: String {
            switch self {
            case .pray:      return "hands.sparkles.fill"
            case .reflect:   return "brain.head.profile"
            case .reach_out: return "person.crop.circle.badge.plus"
            case .read:      return "book.fill"
            case .study:     return "magnifyingglass"
            case .journal:   return "pencil.and.outline"
            case .apply:     return "checkmark.seal.fill"
            case .share:     return "square.and.arrow.up.fill"
            }
        }

        var displayName: String {
            switch self {
            case .pray:      return "Pray"
            case .reflect:   return "Reflect"
            case .reach_out: return "Reach Out"
            case .read:      return "Read"
            case .study:     return "Study"
            case .journal:   return "Journal"
            case .apply:     return "Apply"
            case .share:     return "Share"
            }
        }
    }

    enum ActionSource: String, Codable {
        case bereanChat, churchNote, verse, decision, growthLoop
    }
}

struct BereanActionSuggestion {
    let title: String
    let type: BereanAction.ActionType
    let urgency: Int   // 1 (low) to 3 (high)
}

// MARK: - Service

@MainActor
final class BereanActionEngine: ObservableObject {

    static let shared = BereanActionEngine()

    @Published var actions: [BereanAction] = []
    @Published var pendingActions: [BereanAction] = []

    private lazy var db = Firestore.firestore()
    private var listener: ListenerRegistration?

    private init() {}

    // MARK: - Firestore Path

    private func actionsRef(uid: String) -> CollectionReference {
        db.collection("users").document(uid).collection("bereanActions")
    }

    // MARK: - Lifecycle

    func startListening() {
        guard let uid = Auth.auth().currentUser?.uid else {
            dlog("BereanActionEngine: no authenticated user, skipping listen")
            return
        }

        dlog("BereanActionEngine: starting listener for uid \(uid)")

        listener = actionsRef(uid: uid)
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if let error {
                    dlog("BereanActionEngine listener error: \(error.localizedDescription)")
                    return
                }
                guard let docs = snapshot?.documents else { return }
                let decoder = Firestore.Decoder()
                let all = docs.compactMap { try? $0.data(as: BereanAction.self, decoder: decoder) }
                self.actions = all

                let now = Date()
                let soon = now.addingTimeInterval(60 * 60 * 48) // next 48 hours
                self.pendingActions = all.filter { action in
                    guard !action.isCompleted else { return false }
                    if let due = action.dueDate {
                        return due <= soon
                    }
                    return true
                }

                dlog("BereanActionEngine: loaded \(all.count) actions, \(self.pendingActions.count) pending")
            }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
        dlog("BereanActionEngine: stopped listener")
    }

    // MARK: - Action Operations

    func saveAction(_ action: BereanAction) async {
        guard let uid = Auth.auth().currentUser?.uid else {
            dlog("BereanActionEngine.saveAction: no authenticated user")
            return
        }
        do {
            let encoder = Firestore.Encoder()
            let data = try encoder.encode(action)
            try await actionsRef(uid: uid).document(action.id).setData(data)
            dlog("BereanActionEngine: saved action '\(action.title)' [\(action.type.rawValue)]")
        } catch {
            dlog("BereanActionEngine.saveAction error: \(error.localizedDescription)")
        }
    }

    func completeAction(_ id: String) async {
        guard let uid = Auth.auth().currentUser?.uid else {
            dlog("BereanActionEngine.completeAction: no authenticated user")
            return
        }
        do {
            try await actionsRef(uid: uid).document(id).updateData([
                "isCompleted": true,
                "completedAt": Timestamp(date: Date())
            ])
            dlog("BereanActionEngine: completed action \(id)")
        } catch {
            dlog("BereanActionEngine.completeAction error: \(error.localizedDescription)")
        }
    }

    func deleteAction(_ id: String) async {
        guard let uid = Auth.auth().currentUser?.uid else {
            dlog("BereanActionEngine.deleteAction: no authenticated user")
            return
        }
        do {
            try await actionsRef(uid: uid).document(id).delete()
            // Also cancel any scheduled notification for this action
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id, "\(id)_reminder"])
            dlog("BereanActionEngine: deleted action \(id)")
        } catch {
            dlog("BereanActionEngine.deleteAction error: \(error.localizedDescription)")
        }
    }

    // MARK: - Extraction

    /// Extract up to 3 action suggestions from an AI response by parsing imperative sentences and numbered steps.
    func extractActions(from aiResponse: String, source: BereanAction.ActionSource) -> [BereanActionSuggestion] {
        var suggestions: [BereanActionSuggestion] = []

        let lines = aiResponse
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let actionVerbs: [(keyword: String, type: BereanAction.ActionType)] = [
            ("pray",      .pray),
            ("read",      .read),
            ("study",     .study),
            ("reflect",   .reflect),
            ("journal",   .journal),
            ("write",     .journal),
            ("reach out", .reach_out),
            ("contact",   .reach_out),
            ("message",   .reach_out),
            ("share",     .share),
            ("tell",      .share),
            ("apply",     .apply),
            ("practice",  .apply),
            ("memorize",  .study),
            ("fast",      .pray),
            ("meditate",  .reflect)
        ]

        for line in lines {
            guard suggestions.count < 3 else { break }

            // Strip leading list markers: "1.", "•", "-", "*"
            let cleaned = line
                .replacingOccurrences(of: #"^\d+\.\s*"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"^[•\-\*]\s*"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)

            guard cleaned.count > 10 else { continue }

            let lower = cleaned.lowercased()
            var matched: BereanAction.ActionType = .apply
            var found = false

            for (keyword, type) in actionVerbs {
                if lower.hasPrefix(keyword) || lower.contains(" \(keyword) ") {
                    matched = type
                    found = true
                    break
                }
            }

            // Only include lines that read as action instructions
            guard found || isImperativeSentence(cleaned) else { continue }

            let urgency = urgencyScore(for: cleaned)
            suggestions.append(BereanActionSuggestion(
                title: String(cleaned.prefix(100)),
                type: matched,
                urgency: urgency
            ))
        }

        return suggestions
    }

    private func isImperativeSentence(_ sentence: String) -> Bool {
        // Rough heuristic: starts with a capitalized verb (common imperative form)
        let imperativeStarters = [
            "Take", "Make", "Set", "Find", "Ask", "Consider", "Think",
            "Spend", "Write", "Talk", "Seek", "Trust", "Open", "Start",
            "Commit", "Decide", "Choose", "Begin", "Schedule", "Call"
        ]
        return imperativeStarters.contains(where: { sentence.hasPrefix($0) })
    }

    private func urgencyScore(for text: String) -> Int {
        let lower = text.lowercased()
        if lower.contains("today") || lower.contains("now") || lower.contains("immediately") {
            return 3
        }
        if lower.contains("this week") || lower.contains("soon") || lower.contains("quickly") {
            return 2
        }
        return 1
    }

    // MARK: - Growth Loop

    /// Schedule a 3-part Growth Loop for a Church Note action (24h, 3d, 7d follow-ups).
    func scheduleGrowthLoop(noteId: String, noteTitle: String) async {
        guard Auth.auth().currentUser?.uid != nil else {
            dlog("BereanActionEngine.scheduleGrowthLoop: no authenticated user")
            return
        }

        let now = Date()
        let loopItems: [(interval: TimeInterval, title: String, description: String)] = [
            (
                60 * 60 * 24,
                "Reflect on \"\(noteTitle)\"",
                "Take a few minutes to review your notes and think about what stood out to you."
            ),
            (
                60 * 60 * 24 * 3,
                "Did you apply your action steps from \"\(noteTitle)\"?",
                "Check in on the practical steps you planned. What progress have you made?"
            ),
            (
                60 * 60 * 24 * 7,
                "One week later — what changed from \"\(noteTitle)\"?",
                "Reflect on how this teaching has shaped your week. What has God been doing?"
            )
        ]

        for item in loopItems {
            let dueDate = now.addingTimeInterval(item.interval)
            let action = BereanAction(
                title: item.title,
                description: item.description,
                type: .reflect,
                linkedNoteId: noteId,
                dueDate: dueDate,
                reminderDate: dueDate,
                source: .growthLoop
            )
            await saveAction(action)
            await scheduleLocalNotification(for: action)
        }

        dlog("BereanActionEngine: scheduled 3-part growth loop for note '\(noteTitle)'")
    }

    private func scheduleLocalNotification(for action: BereanAction) async {
        guard let triggerDate = action.reminderDate else { return }
        guard triggerDate > Date() else { return }

        let status = await UNUserNotificationCenter.current().notificationSettings()
        guard status.authorizationStatus == .authorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "Berean Reminder"
        content.body = action.title
        content.sound = .default

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: "\(action.id)_reminder", content: content, trigger: trigger)

        do {
            try await UNUserNotificationCenter.current().add(request)
            dlog("BereanActionEngine: scheduled notification for action '\(action.title)' at \(triggerDate)")
        } catch {
            dlog("BereanActionEngine.scheduleLocalNotification error: \(error.localizedDescription)")
        }
    }

    // MARK: - Summaries

    var completionRate: Double {
        guard !actions.isEmpty else { return 0 }
        return Double(actions.filter(\.isCompleted).count) / Double(actions.count)
    }

    var streakDays: Int {
        guard !actions.isEmpty else { return 0 }

        let completedDates = actions
            .filter { $0.isCompleted }
            .compactMap { $0.completedAt }
            .map { Calendar.current.startOfDay(for: $0) }

        guard !completedDates.isEmpty else { return 0 }

        let uniqueDays = Array(Set(completedDates)).sorted(by: >)
        var streak = 0
        var checkDate = Calendar.current.startOfDay(for: Date())

        for day in uniqueDays {
            if day == checkDate {
                streak += 1
                checkDate = Calendar.current.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
            } else {
                break
            }
        }

        return streak
    }
}
