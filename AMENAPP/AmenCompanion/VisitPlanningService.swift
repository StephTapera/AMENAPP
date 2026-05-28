import Foundation
import FirebaseAuth
import FirebaseFirestore
import UserNotifications

@MainActor
final class VisitPlanningService: ObservableObject {
    static let shared = VisitPlanningService()

    @Published private(set) var activePlans: [ChurchVisitPlan] = []
    @Published private(set) var isLoading = false

    private lazy var db = Firestore.firestore()

    private init() {}

    func loadPlans() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let snap = try await db.collection("users").document(uid)
                .collection("visit_plans")
                .order(by: "createdAt", descending: true)
                .limit(to: 10)
                .getDocuments()
            activePlans = snap.documents.compactMap {
                try? Firestore.Decoder().decode(ChurchVisitPlan.self, from: $0.data())
            }
        } catch {}
    }

    func createPlan(church: SmartChurchSummary, serviceTime: SmartChurchServiceTime) async throws -> ChurchVisitPlan {
        guard let uid = Auth.auth().currentUser?.uid else { throw VisitPlanError.notAuthenticated }

        let id = UUID().uuidString
        let plan = ChurchVisitPlan(
            id: id,
            churchId: church.id,
            churchName: church.name,
            serviceTime: serviceTime.displayText,
            serviceDay: serviceTime.day,
            visitDate: nextOccurrence(for: serviceTime.day),
            directionsURL: buildDirectionsURL(for: church),
            invitedFriendUIDs: [],
            prayerNote: nil,
            reminderEnabled: true,
            reflectionPrompted: false,
            createdAt: Date(),
            updatedAt: Date()
        )

        let data = try Firestore.Encoder().encode(plan)
        try await db.collection("users").document(uid)
            .collection("visit_plans").document(id)
            .setData(data)

        activePlans.insert(plan, at: 0)

        if plan.reminderEnabled, let date = plan.visitDate {
            await scheduleReminder(plan: plan, visitDate: date)
        }

        return plan
    }

    func updatePrayerNote(planId: String, note: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        guard let idx = activePlans.firstIndex(where: { $0.id == planId }) else { return }
        activePlans[idx].prayerNote = note
        try await db.collection("users").document(uid)
            .collection("visit_plans").document(planId)
            .updateData(["prayerNote": note, "updatedAt": FieldValue.serverTimestamp()])
    }

    func inviteFriend(planId: String, friendUID: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        guard let idx = activePlans.firstIndex(where: { $0.id == planId }) else { return }
        activePlans[idx].invitedFriendUIDs.append(friendUID)
        try await db.collection("users").document(uid)
            .collection("visit_plans").document(planId)
            .updateData(["invitedFriendUIDs": FieldValue.arrayUnion([friendUID])])
    }

    func markReflectionPrompted(planId: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        guard let idx = activePlans.firstIndex(where: { $0.id == planId }) else { return }
        activePlans[idx].reflectionPrompted = true
        try await db.collection("users").document(uid)
            .collection("visit_plans").document(planId)
            .updateData(["reflectionPrompted": true])
    }

    func deletePlan(planId: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        try await db.collection("users").document(uid)
            .collection("visit_plans").document(planId)
            .delete()
        activePlans.removeAll { $0.id == planId }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["visit_reminder_\(planId)"])
    }

    // Returns post-visit reflection prompt if visit date has passed
    func postVisitReflectionPlan() -> ChurchVisitPlan? {
        activePlans.first { plan in
            guard let date = plan.visitDate else { return false }
            return date < Date() && !plan.reflectionPrompted
        }
    }

    private func scheduleReminder(plan: ChurchVisitPlan, visitDate: Date) async {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "Visit planned: \(plan.churchName)"
        content.body = "Service at \(plan.serviceTime) today. Tap to see directions and prayer notes."
        content.sound = .default

        let reminderDate = Calendar.current.date(byAdding: .hour, value: -2, to: visitDate) ?? visitDate
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminderDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let request = UNNotificationRequest(identifier: "visit_reminder_\(plan.id)", content: content, trigger: trigger)
        try? await center.add(request)
    }

    private func nextOccurrence(for dayName: String) -> Date? {
        let calendar = Calendar.current
        let weekdays = ["Sunday": 1, "Monday": 2, "Tuesday": 3, "Wednesday": 4, "Thursday": 5, "Friday": 6, "Saturday": 7]
        guard let targetWeekday = weekdays[dayName] else { return nil }

        var components = DateComponents()
        components.weekday = targetWeekday
        return calendar.nextDate(after: Date(), matching: components, matchingPolicy: .nextTime)
    }

    private func buildDirectionsURL(for church: SmartChurchSummary) -> String? {
        let encoded = church.address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return "maps://?q=\(encoded)"
    }
}

enum VisitPlanError: LocalizedError {
    case notAuthenticated

    var errorDescription: String? {
        "Sign in to plan a visit."
    }
}
