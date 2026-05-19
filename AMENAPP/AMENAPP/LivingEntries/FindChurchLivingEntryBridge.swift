import Foundation
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class FindChurchLivingEntryBridge {
    static let shared = FindChurchLivingEntryBridge()

    private let service: LivingEntryService

    private init(service: LivingEntryService? = nil) {
        self.service = service ?? .shared
    }

    func handleChurchSaved(_ church: Church) {
        Task { await handleSavedChurch(church) }
    }

    func handleDirectionsOpened(for church: Church) {
        Task { await handleOpenedDirections(church) }
    }

    func handleSavedChurch(_ church: Church) async {
        await createChurchEntryIfNeeded(
            sourceKey: "saved",
            church: church,
            type: .reminder,
            intent: .churchVisit,
            title: "Visit \(church.name) Sunday",
            body: "You saved this church. Want to check service times or directions?",
            dueAt: Self.nextSundayMorning(),
            triggerRules: [
                LivingEntryTriggerRule(type: .beforeService, churchId: church.canonicalChurchId, beforeEventMinutes: 90),
                LivingEntryTriggerRule(type: .churchProximity, locationRadiusMeters: 350, churchId: church.canonicalChurchId)
            ]
        )
    }

    func handleOpenedDirections(_ church: Church) async {
        await createChurchEntryIfNeeded(
            sourceKey: "directions",
            church: church,
            type: .followUp,
            intent: .churchVisit,
            title: "Reflect after visiting \(church.name)",
            body: "Capture what stood out, what felt welcoming, and whether to return.",
            dueAt: Calendar.current.date(byAdding: .hour, value: 4, to: Date()),
            triggerRules: [
                LivingEntryTriggerRule(type: .afterChurch, churchId: church.canonicalChurchId, afterEventMinutes: 180),
                LivingEntryTriggerRule(type: .quietMoment, minQuietMinutes: 12)
            ]
        )
    }

    func handlePlannedVisit(_ church: Church) async {
        await createChurchEntryIfNeeded(
            sourceKey: "planned_visit",
            church: church,
            type: .followUp,
            intent: .churchVisit,
            title: "Check service time for \(church.name)",
            body: "Amen can keep this visible before service and after you leave.",
            dueAt: Self.nextSundayMorning(),
            triggerRules: [
                LivingEntryTriggerRule(type: .beforeService, churchId: church.canonicalChurchId, beforeEventMinutes: 60),
                LivingEntryTriggerRule(type: .time, scheduledAt: Self.nextSundayMorning())
            ]
        )
    }

    func handleVisitedChurch(_ church: Church) async {
        await createChurchEntryIfNeeded(
            sourceKey: "visit_reflection",
            church: church,
            type: .reflection,
            intent: .churchVisit,
            title: "How was \(church.name)?",
            body: "Take notes after visiting, or pray about whether this is a good fit.",
            dueAt: Calendar.current.date(byAdding: .hour, value: 3, to: Date()),
            triggerRules: [
                LivingEntryTriggerRule(type: .afterChurch, churchId: church.canonicalChurchId, afterEventMinutes: 180),
                LivingEntryTriggerRule(type: .quietMoment, minQuietMinutes: 8)
            ]
        )
    }

    private func createChurchEntryIfNeeded(
        sourceKey: String,
        church: Church,
        type: LivingEntryType,
        intent: LivingEntryIntent,
        title: String,
        body: String,
        dueAt: Date?,
        triggerRules: [LivingEntryTriggerRule]
    ) async {
        guard let userId = FirebaseManager.shared.currentUser?.uid else { return }
        let tag = "find_church:\(church.canonicalChurchId):\(sourceKey)"
        do {
            let existing = try await Firestore.firestore()
                .collection("users")
                .document(userId)
                .collection("living_entries")
                .whereField("tags", arrayContains: tag)
                .limit(to: 1)
                .getDocuments()
                .documents
                .first
                .flatMap { try? $0.data(as: LivingEntry.self) }

            let entry = LivingEntry(
                id: existing?.id,
                userId: userId,
                type: type,
                intent: intent,
                title: title,
                body: body,
                churchId: church.canonicalChurchId,
                churchName: church.name,
                tags: [tag, "find_church"],
                dueAt: dueAt,
                priorityScore: 0.54,
                gravityScore: 0.58,
                emotionalWeight: 0.3,
                regretRisk: 0.18,
                spiritualWeight: 0.68,
                triggerRules: triggerRules,
                contextSnapshot: .current(sourceSurface: .findChurch, nearbyChurchId: church.canonicalChurchId),
                suggestedNextAction: "Open directions or take notes after you visit.",
                reflectionPrompt: "Was this church visit meaningful, mistimed, or still undecided?"
            )
            _ = try await (existing == nil ? service.createEntry(entry) : service.updateEntry(entry))
        } catch {
        }
    }

    static func nextSundayMorning(from now: Date = Date(), calendar: Calendar = .current) -> Date {
        let weekday = calendar.component(.weekday, from: now)
        let daysUntilSunday = (1 - weekday + 7) % 7
        let nextSunday = calendar.date(byAdding: .day, value: daysUntilSunday == 0 ? 7 : daysUntilSunday, to: now) ?? now
        return calendar.date(bySettingHour: 8, minute: 0, second: 0, of: nextSunday) ?? now
    }
}
