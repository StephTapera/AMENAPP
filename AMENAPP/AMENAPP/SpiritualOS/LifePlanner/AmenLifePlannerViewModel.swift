import Foundation
import FirebaseFirestore
import FirebaseFunctions

// MARK: - PlannerSourceType

enum PlannerSourceType: String, Codable, CaseIterable {
    case spaceEvent        = "space_event"
    case readingPlan       = "reading_plan"
    case prayerPlan        = "prayer_plan"
    case gathering         = "gathering"
    case personalNote      = "personal_note"
    case bereanSuggestion  = "berean_suggestion"
}

// MARK: - PlannerEvent

struct PlannerEvent: Identifiable, Codable {
    var id: String
    var sourceType: PlannerSourceType
    var title: String
    var description: String?
    var startDate: Date
    var endDate: Date?
    var isAllDay: Bool
    var isCompleted: Bool
    var spaceId: String?
    var sourceRef: String?
    var bereanNote: String?
    var isBereanNote: Bool
    var isDismissed: Bool
    var color: String?
}

// MARK: - PlannerSuggestion

struct PlannerSuggestion: Identifiable {
    var id: String
    var promptLabel: String
    var bereanNote: String
    var targetDate: Date
}

// MARK: - AmenLifePlannerViewModel

@MainActor
final class AmenLifePlannerViewModel: ObservableObject {

    @Published var todayEvents: [PlannerEvent] = []
    @Published var tomorrowEvents: [PlannerEvent] = []
    @Published var bereanSuggestions: [PlannerSuggestion] = []
    @Published var isLoading: Bool = false

    private let db = Firestore.firestore()

    // MARK: Load

    func load(userId: String) async {
        guard !userId.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }

        let calendar = Calendar.current
        let now = Date()

        guard
            let todayStart  = calendar.dateInterval(of: .day, for: now)?.start,
            let todayEnd    = calendar.dateInterval(of: .day, for: now)?.end,
            let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart),
            let tomorrowEnd   = calendar.date(byAdding: .day, value: 1, to: todayEnd)
        else {
            return
        }

        let payload: [String: Any] = [
            "userId": userId,
            "todayStart": todayStart.timeIntervalSince1970,
            "todayEnd": todayEnd.timeIntervalSince1970,
            "tomorrowStart": tomorrowStart.timeIntervalSince1970,
            "tomorrowEnd": tomorrowEnd.timeIntervalSince1970
        ]

        do {
            let callable = Functions.functions().httpsCallable("getPlannerEvents")
            let result = try await callable.call(payload)

            guard let data = result.data as? [String: Any] else { return }

            let todayRaw      = data["today"] as? [[String: Any]] ?? []
            let tomorrowRaw   = data["tomorrow"] as? [[String: Any]] ?? []
            let suggestionsRaw = data["suggestions"] as? [[String: Any]] ?? []

            todayEvents = todayRaw.compactMap { Self.decodePlannerEvent($0) }
                .filter { !$0.isDismissed }
                .sorted { $0.startDate < $1.startDate }

            tomorrowEvents = tomorrowRaw.compactMap { Self.decodePlannerEvent($0) }
                .filter { !$0.isDismissed }
                .sorted { $0.startDate < $1.startDate }

            bereanSuggestions = suggestionsRaw.compactMap { Self.decodePlannerSuggestion($0) }

        } catch {
            // Silent failure — planner degrades gracefully to empty state
        }
    }

    // MARK: Toggle Complete

    func toggleComplete(eventId: String, userId: String) async {
        guard !eventId.isEmpty, !userId.isEmpty else { return }

        // Optimistic local update
        if let idx = todayEvents.firstIndex(where: { $0.id == eventId }) {
            todayEvents[idx].isCompleted.toggle()
        } else if let idx = tomorrowEvents.firstIndex(where: { $0.id == eventId }) {
            tomorrowEvents[idx].isCompleted.toggle()
        }

        let currentValue: Bool
        if let event = todayEvents.first(where: { $0.id == eventId }) {
            currentValue = event.isCompleted
        } else if let event = tomorrowEvents.first(where: { $0.id == eventId }) {
            currentValue = event.isCompleted
        } else {
            return
        }

        do {
            try await db
                .collection("spiritualOS_planner")
                .document(userId)
                .collection("events")
                .document(eventId)
                .setData(["isCompleted": currentValue], merge: true)
        } catch {
            // Revert optimistic update on failure
            if let idx = todayEvents.firstIndex(where: { $0.id == eventId }) {
                todayEvents[idx].isCompleted.toggle()
            } else if let idx = tomorrowEvents.firstIndex(where: { $0.id == eventId }) {
                tomorrowEvents[idx].isCompleted.toggle()
            }
        }
    }

    // MARK: Dismiss Suggestion

    func dismissSuggestion(itemId: String, userId: String) async {
        guard !itemId.isEmpty, !userId.isEmpty else { return }

        // Optimistic local removal
        bereanSuggestions.removeAll { $0.id == itemId }

        do {
            let callable = Functions.functions().httpsCallable("dismissSuggestion")
            _ = try await callable.call(["itemId": itemId, "userId": userId])
        } catch {
            // Silent — suggestion is already gone from the local list; re-load will reconcile
        }
    }

    // MARK: Decoding helpers

    private static func decodePlannerEvent(_ dict: [String: Any]) -> PlannerEvent? {
        guard
            let id        = dict["id"] as? String,
            let typeRaw   = dict["sourceType"] as? String,
            let title     = dict["title"] as? String,
            let startTs   = dict["startDate"] as? TimeInterval
        else { return nil }

        let sourceType = PlannerSourceType(rawValue: typeRaw) ?? .personalNote
        let startDate  = Date(timeIntervalSince1970: startTs)
        let endDate: Date?
        if let endTs = dict["endDate"] as? TimeInterval {
            endDate = Date(timeIntervalSince1970: endTs)
        } else {
            endDate = nil
        }

        return PlannerEvent(
            id:            id,
            sourceType:    sourceType,
            title:         title,
            description:   dict["description"] as? String,
            startDate:     startDate,
            endDate:       endDate,
            isAllDay:      dict["isAllDay"] as? Bool ?? false,
            isCompleted:   dict["isCompleted"] as? Bool ?? false,
            spaceId:       dict["spaceId"] as? String,
            sourceRef:     dict["sourceRef"] as? String,
            bereanNote:    dict["bereanNote"] as? String,
            isBereanNote:  dict["isBereanNote"] as? Bool ?? false,
            isDismissed:   dict["isDismissed"] as? Bool ?? false,
            color:         dict["color"] as? String
        )
    }

    private static func decodePlannerSuggestion(_ dict: [String: Any]) -> PlannerSuggestion? {
        guard
            let id          = dict["id"] as? String,
            let promptLabel = dict["promptLabel"] as? String,
            let bereanNote  = dict["bereanNote"] as? String,
            let targetTs    = dict["targetDate"] as? TimeInterval
        else { return nil }

        return PlannerSuggestion(
            id:          id,
            promptLabel: promptLabel,
            bereanNote:  bereanNote,
            targetDate:  Date(timeIntervalSince1970: targetTs)
        )
    }
}
