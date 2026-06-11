// FindChurch2VisitPlannerService.swift
// AMENAPP — Find Church 2.0 — Wave 4: Visit Planner
//
// Coordinates the full visit lifecycle:
//   planVisit    → Firestore write + EventKit calendar event + UNNotification morning-of reminder
//   loadUpcoming → Firestore read of upcoming VisitPlans for current user
//   updateStatus → Status machine write (planned → reminded → checkedIn → reflected → cancelled)
//   startPostVisitReflection → creates / links a church note for post-visit reflection
//   whatToExpectCard → synchronously computes WhatToExpectCard from ChurchObject fields
//
// Feature gate: AMENFeatureFlags.shared.findChurch2VisitPlannerEnabled
// Firestore path: visitPlans/{uid}_{planId}   (composite doc ID)
//
// Privacy: no background polling, no location access, no implicit data collection.
// All writes are explicitly user-initiated.

import SwiftUI
import Foundation
import FirebaseAuth
import FirebaseFirestore
import EventKit
import UserNotifications

// MARK: - WhatToExpectCard

struct WhatToExpectCard {
    let parkingInfo: String?       // from AccessibilityInfo.parkingNotes
    let entranceInfo: String?      // from AccessibilityInfo.entranceNotes
    let hasChildcare: Bool
    let hasASL: Bool
    let languages: [String]        // BCP-47 language codes
    let serviceStyleHint: String?  // from BeliefSchema.worshipStyle
    let dressHint: String          // default: "Dress comfortably — come as you are"
}

// MARK: - FindChurch2VisitPlannerError

enum FindChurch2VisitPlannerError: LocalizedError {
    case featureDisabled
    case notAuthenticated
    case invalidServiceDate(String)
    case firestoreWriteFailed(Error)
    case planNotFound(String)

    var errorDescription: String? {
        switch self {
        case .featureDisabled:
            return "Visit Planner (Find Church 2.0 Wave 4) is not enabled. Check Remote Config flag 'findChurch2_visitPlanner'."
        case .notAuthenticated:
            return "User must be signed in to create a visit plan."
        case .invalidServiceDate(let detail):
            return "Cannot compute a service date: \(detail)"
        case .firestoreWriteFailed(let underlying):
            return "Firestore write failed: \(underlying.localizedDescription)"
        case .planNotFound(let planId):
            return "Visit plan '\(planId)' not found in Firestore."
        }
    }
}

// MARK: - FindChurch2VisitPlannerService

@MainActor
final class FindChurch2VisitPlannerService: ObservableObject {

    // MARK: - Shared Instance

    static let shared = FindChurch2VisitPlannerService()

    // MARK: - Published State

    @Published var activePlan: VisitPlan?
    @Published var upcomingPlans: [VisitPlan] = []

    // MARK: - Private

    private let db = Firestore.firestore()
    private let ekStore = EKEventStore()
    private let notificationCenter = UNUserNotificationCenter.current()

    private init() {}

    // MARK: - planVisit

    /// Creates a VisitPlan from a church + optional service time.
    ///
    /// Steps:
    ///   1. Gate check (feature flag + auth)
    ///   2. Build VisitPlan value and persist to `visitPlans/{uid}_{planId}`
    ///   3. Create EventKit calendar event (graceful fallback on denial)
    ///   4. Schedule UNNotification morning-of reminder at 8 AM on service day
    ///   5. Update activePlan
    ///
    /// - Returns: The new plan's Firestore document ID (composite `{uid}_{planId}`).
    @discardableResult
    func planVisit(
        to church: ChurchObject,
        serviceTime: StructuredServiceTime?,
        comfortPrefs: [SeekerProfile.ComfortChip]
    ) async throws -> String {

        // 1. Gate check
        guard AMENFeatureFlags.shared.findChurch2VisitPlannerEnabled else {
            throw FindChurch2VisitPlannerError.featureDisabled
        }
        guard let uid = Auth.auth().currentUser?.uid else {
            throw FindChurch2VisitPlannerError.notAuthenticated
        }

        // 2. Derive service date
        let serviceDate = try nextServiceDate(from: serviceTime)
        let timeString = serviceTime?.displayTime ?? "Service time TBD"
        let serviceTypeString = serviceTime?.serviceType ?? "Main Service"

        // 3. Build VisitPlan
        let planId = UUID().uuidString
        let compositeDocId = "\(uid)_\(planId)"
        let now = Timestamp(date: Date())

        let plan = VisitPlan(
            id: compositeDocId,
            userId: uid,
            churchId: church.id,
            churchName: church.name,
            serviceDate: Timestamp(date: serviceDate),
            serviceTime: timeString,
            serviceType: serviceTypeString,
            calendarEventId: nil,         // filled in after EK attempt
            calendarSynced: false,
            reminderScheduled: false,     // filled in after UNNotification attempt
            reminderNotificationId: nil,
            dayOfReminderScheduled: false,
            dayOfReminderNotificationId: nil,
            churchAddress: church.address,
            churchCoordinates: nil,
            status: .planned,
            visited: false,
            visitedAt: nil,
            autoNoteCreated: false,
            noteId: nil,
            createdAt: now,
            updatedAt: now
        )

        // 4. Persist to Firestore
        do {
            let data = try Firestore.Encoder().encode(plan)
            try await db.collection("visitPlans").document(compositeDocId).setData(data)
            dlog("[VisitPlanner] Created plan \(compositeDocId) for church \(church.name)")
        } catch {
            throw FindChurch2VisitPlannerError.firestoreWriteFailed(error)
        }

        // 5. EventKit — non-throwing: graceful fallback on denial
        let calendarEventId = await createCalendarEvent(
            for: church,
            serviceTime: serviceTime,
            serviceDate: serviceDate,
            planId: planId
        )

        // 6. Morning-of UNNotification — non-throwing: graceful fallback on denial
        let notificationId = await scheduleMorningOfReminder(
            for: church,
            serviceDate: serviceDate,
            planId: planId
        )

        // 7. Patch Firestore with EK / notification IDs if obtained
        if calendarEventId != nil || notificationId != nil {
            var patch: [String: Any] = ["updatedAt": Timestamp(date: Date())]
            if let ekId = calendarEventId {
                patch["calendar_event_id"] = ekId
                patch["calendar_synced"] = true
            }
            if let notifId = notificationId {
                patch["day_of_reminder_scheduled"] = true
                patch["day_of_reminder_notification_id"] = notifId
            }
            try? await db.collection("visitPlans").document(compositeDocId).updateData(patch)
        }

        // 8. Update active plan
        let updatedPlan = VisitPlan(
            id: compositeDocId,
            userId: uid,
            churchId: church.id,
            churchName: church.name,
            serviceDate: Timestamp(date: serviceDate),
            serviceTime: timeString,
            serviceType: serviceTypeString,
            calendarEventId: calendarEventId,
            calendarSynced: calendarEventId != nil,
            reminderScheduled: notificationId != nil,
            reminderNotificationId: nil,
            dayOfReminderScheduled: notificationId != nil,
            dayOfReminderNotificationId: notificationId,
            churchAddress: church.address,
            churchCoordinates: nil,
            status: .planned,
            visited: false,
            visitedAt: nil,
            autoNoteCreated: false,
            noteId: nil,
            createdAt: now,
            updatedAt: Timestamp(date: Date())
        )
        activePlan = updatedPlan

        // Ensure the new plan appears in upcomingPlans
        if !upcomingPlans.contains(where: { $0.id == compositeDocId }) {
            upcomingPlans.insert(updatedPlan, at: 0)
        }

        dlog("[VisitPlanner] planVisit complete — docId: \(compositeDocId), ekId: \(calendarEventId ?? "none"), notifId: \(notificationId ?? "none")")
        return compositeDocId
    }

    // MARK: - loadUpcomingPlans

    /// Loads all upcoming (non-cancelled, non-expired) plans from Firestore for the current user.
    func loadUpcomingPlans() async {
        guard AMENFeatureFlags.shared.findChurch2VisitPlannerEnabled else { return }
        guard let uid = Auth.auth().currentUser?.uid else { return }

        do {
            let snapshot = try await db
                .collection("visitPlans")
                .whereField("user_id", isEqualTo: uid)
                .whereField("status", notIn: [
                    VisitPlanStatus.cancelled.rawValue,
                    VisitPlanStatus.expired.rawValue
                ])
                .order(by: "service_date", descending: false)
                .getDocuments()

            let plans: [VisitPlan] = snapshot.documents.compactMap { doc in
                try? doc.data(as: VisitPlan.self)
            }
            upcomingPlans = plans

            // Surface the soonest upcoming plan as activePlan if none is set
            if activePlan == nil {
                activePlan = plans.first(where: { $0.isUpcoming })
            }

            dlog("[VisitPlanner] Loaded \(plans.count) upcoming plan(s) for uid \(uid)")
        } catch {
            dlog("[VisitPlanner] loadUpcomingPlans error: \(error)")
        }
    }

    // MARK: - updateStatus

    /// Transitions a plan to a new status and persists to Firestore.
    ///
    /// Legal transitions mirrored from the VisitPlanStatus machine:
    ///   planned → reminded → dayOf → visited → (reflected via startPostVisitReflection)
    ///   any → cancelled
    func updateStatus(_ status: VisitPlanStatus, for planId: String) async throws {
        guard AMENFeatureFlags.shared.findChurch2VisitPlannerEnabled else {
            throw FindChurch2VisitPlannerError.featureDisabled
        }
        guard Auth.auth().currentUser?.uid != nil else {
            throw FindChurch2VisitPlannerError.notAuthenticated
        }

        let patch: [String: Any] = [
            "status": status.rawValue,
            "visited": status == .visited,
            "visited_at": status == .visited ? Timestamp(date: Date()) : FieldValue.delete(),
            "updatedAt": Timestamp(date: Date())
        ]

        do {
            try await db.collection("visitPlans").document(planId).updateData(patch)
        } catch {
            throw FindChurch2VisitPlannerError.firestoreWriteFailed(error)
        }

        // Reflect update locally
        if let idx = upcomingPlans.firstIndex(where: { $0.id == planId }) {
            let old = upcomingPlans[idx]
            let updated = VisitPlan(
                id: old.id,
                userId: old.userId,
                churchId: old.churchId,
                churchName: old.churchName,
                serviceDate: old.serviceDate,
                serviceTime: old.serviceTime,
                serviceType: old.serviceType,
                calendarEventId: old.calendarEventId,
                calendarSynced: old.calendarSynced,
                reminderScheduled: old.reminderScheduled,
                reminderNotificationId: old.reminderNotificationId,
                dayOfReminderScheduled: old.dayOfReminderScheduled,
                dayOfReminderNotificationId: old.dayOfReminderNotificationId,
                churchAddress: old.churchAddress,
                churchCoordinates: old.churchCoordinates,
                status: status,
                visited: status == .visited,
                visitedAt: status == .visited ? Timestamp(date: Date()) : nil,
                autoNoteCreated: old.autoNoteCreated,
                noteId: old.noteId,
                createdAt: old.createdAt,
                updatedAt: Timestamp(date: Date())
            )
            upcomingPlans[idx] = updated
            if activePlan?.id == planId { activePlan = updated }
        }

        // Remove from upcomingPlans if now terminal
        if status == .cancelled || status == .expired {
            upcomingPlans.removeAll { $0.id == planId }
            if activePlan?.id == planId { activePlan = nil }
        }

        dlog("[VisitPlanner] Updated status to '\(status.rawValue)' for plan \(planId)")
    }

    // MARK: - startPostVisitReflection

    /// Starts the post-visit reflection flow for a completed visit plan.
    ///
    /// - If the plan already has a linked `noteId`, returns it directly.
    /// - Otherwise creates a new church note stub in `users/{uid}/churchNotes/{noteId}`
    ///   and links it back to the visitPlan document.
    ///
    /// - Returns: The church note ID, or nil if the user is not authenticated.
    func startPostVisitReflection(for planId: String) async throws -> String? {
        guard AMENFeatureFlags.shared.findChurch2VisitPlannerEnabled else {
            throw FindChurch2VisitPlannerError.featureDisabled
        }
        guard let uid = Auth.auth().currentUser?.uid else {
            throw FindChurch2VisitPlannerError.notAuthenticated
        }

        // Fetch current plan from Firestore
        let planDoc: DocumentSnapshot
        do {
            planDoc = try await db.collection("visitPlans").document(planId).getDocument()
        } catch {
            throw FindChurch2VisitPlannerError.firestoreWriteFailed(error)
        }

        guard planDoc.exists else {
            throw FindChurch2VisitPlannerError.planNotFound(planId)
        }

        let plan = try planDoc.data(as: VisitPlan.self)

        // Return existing note ID if already linked
        if let existingNoteId = plan.noteId, !existingNoteId.isEmpty {
            dlog("[VisitPlanner] Plan \(planId) already has note \(existingNoteId)")
            return existingNoteId
        }

        // Create a new church note stub
        let noteId = UUID().uuidString
        let noteStub: [String: Any] = [
            "id": noteId,
            "userId": uid,
            "churchId": plan.churchId,
            "churchName": plan.churchName,
            "visitPlanId": planId,
            "title": "Visit to \(plan.churchName)",
            "body": "",
            "serviceDate": plan.serviceDate,
            "createdAt": Timestamp(date: Date()),
            "updatedAt": Timestamp(date: Date()),
            "isReflection": true
        ]

        do {
            try await db
                .collection("users").document(uid)
                .collection("churchNotes").document(noteId)
                .setData(noteStub)
        } catch {
            throw FindChurch2VisitPlannerError.firestoreWriteFailed(error)
        }

        // Link noteId back to the visitPlan
        let linkPatch: [String: Any] = [
            "note_id": noteId,
            "auto_note_created": true,
            "updatedAt": Timestamp(date: Date())
        ]
        try? await db.collection("visitPlans").document(planId).updateData(linkPatch)

        // Update local state
        if let idx = upcomingPlans.firstIndex(where: { $0.id == planId }) {
            let old = upcomingPlans[idx]
            let updated = VisitPlan(
                id: old.id,
                userId: old.userId,
                churchId: old.churchId,
                churchName: old.churchName,
                serviceDate: old.serviceDate,
                serviceTime: old.serviceTime,
                serviceType: old.serviceType,
                calendarEventId: old.calendarEventId,
                calendarSynced: old.calendarSynced,
                reminderScheduled: old.reminderScheduled,
                reminderNotificationId: old.reminderNotificationId,
                dayOfReminderScheduled: old.dayOfReminderScheduled,
                dayOfReminderNotificationId: old.dayOfReminderNotificationId,
                churchAddress: old.churchAddress,
                churchCoordinates: old.churchCoordinates,
                status: old.status,
                visited: old.visited,
                visitedAt: old.visitedAt,
                autoNoteCreated: true,
                noteId: noteId,
                createdAt: old.createdAt,
                updatedAt: Timestamp(date: Date())
            )
            upcomingPlans[idx] = updated
            if activePlan?.id == planId { activePlan = updated }
        }

        // Notify ChurchVisitSessionManager so it can attach the note to the session
        await ChurchVisitSessionManager.shared.attachNote(noteId: noteId)

        dlog("[VisitPlanner] Created reflection note \(noteId) for plan \(planId)")
        return noteId
    }

    // MARK: - whatToExpectCard

    /// Computes a WhatToExpectCard from a ChurchObject synchronously.
    /// Returns nil when every meaningful field is unknown (honest "not provided" state).
    func whatToExpectCard(for church: ChurchObject) -> WhatToExpectCard? {
        let parking = church.accessibility.parkingNotes
        let entrance = church.accessibility.entranceNotes
        let hasChildcare = church.accessibility.hasChildcare
        let hasASL = church.accessibility.hasASL
        let languages = church.accessibility.languages
        let styleHint = church.beliefs?.worshipStyle
        let dressHint = "Dress comfortably — come as you are"

        // Return nil only when all informative fields are unknown
        let hasAnyInfo = parking != nil
            || entrance != nil
            || hasChildcare
            || hasASL
            || !languages.isEmpty
            || styleHint != nil

        guard hasAnyInfo else { return nil }

        return WhatToExpectCard(
            parkingInfo: parking,
            entranceInfo: entrance,
            hasChildcare: hasChildcare,
            hasASL: hasASL,
            languages: languages,
            serviceStyleHint: styleHint,
            dressHint: dressHint
        )
    }

    // MARK: - Private: Service Date Computation

    /// Computes the next upcoming calendar date that matches the dayOfWeek in `serviceTime`.
    /// If `serviceTime` is nil, defaults to next Sunday at 10:00 AM.
    private func nextServiceDate(from serviceTime: StructuredServiceTime?) throws -> Date {
        let now = Date()

        guard let serviceTime else {
            // Default: next Sunday at 10 AM
            let weekday = 1 // Sunday in Calendar (1=Sun … 7=Sat)
            guard let next = nextDate(forWeekday: weekday, hour: 10, minute: 0, from: now) else {
                throw FindChurch2VisitPlannerError.invalidServiceDate("Could not compute next Sunday")
            }
            return next
        }

        // serviceTime.dayOfWeek: 1=Sunday … 7=Saturday (matching Calendar.current weekday convention)
        let targetWeekday = serviceTime.dayOfWeek
        guard (1...7).contains(targetWeekday) else {
            throw FindChurch2VisitPlannerError.invalidServiceDate("dayOfWeek \(targetWeekday) is out of range 1–7")
        }

        // Resolve timezone
        let tz = TimeZone(identifier: serviceTime.timezone) ?? TimeZone.current
        var tzCalendar = Calendar.current
        tzCalendar.timeZone = tz

        guard let next = nextDate(
            forWeekday: targetWeekday,
            hour: serviceTime.startHour,
            minute: serviceTime.startMinute,
            from: now,
            calendar: tzCalendar
        ) else {
            throw FindChurch2VisitPlannerError.invalidServiceDate(
                "Could not compute next occurrence for dayOfWeek \(targetWeekday)"
            )
        }
        return next
    }

    /// Returns the next Date on or after `from` that falls on `weekday` at `hour:minute`.
    private func nextDate(
        forWeekday weekday: Int,
        hour: Int,
        minute: Int,
        from referenceDate: Date,
        calendar: Calendar = .current
    ) -> Date? {
        var comps = DateComponents()
        comps.weekday = weekday
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        return calendar.nextDate(
            after: referenceDate,
            matching: comps,
            matchingPolicy: .nextTime
        )
    }

    // MARK: - Private: EventKit

    /// Requests write-only EventKit access and creates a calendar event.
    /// Returns the EKEvent identifier, or nil if access was denied or the write failed.
    private func createCalendarEvent(
        for church: ChurchObject,
        serviceTime: StructuredServiceTime?,
        serviceDate: Date,
        planId: String
    ) async -> String? {
        let authorized = await requestCalendarAccess()
        guard authorized else {
            dlog("[VisitPlanner] Calendar access denied — skipping EK event creation")
            return nil
        }

        // Compute WhatToExpectCard on MainActor before entering the detached task
        let card = whatToExpectCard(for: church)

        return await Task.detached(priority: .userInitiated) {
            // Create a new EKEventStore scoped to this task (EKEventStore is not Sendable)
            let store = EKEventStore()

            let event = EKEvent(eventStore: store)
            event.title = "Visit \(church.name)"
            event.calendar = store.defaultCalendarForNewEvents

            // Build notes from WhatToExpectCard (computed above on MainActor)
            if let card {
                var notesLines: [String] = []
                notesLines.append("Dress: \(card.dressHint)")
                if let parking = card.parkingInfo { notesLines.append("Parking: \(parking)") }
                if let entrance = card.entranceInfo { notesLines.append("Entrance: \(entrance)") }
                if card.hasChildcare { notesLines.append("Childcare available") }
                if card.hasASL { notesLines.append("ASL interpretation available") }
                if let style = card.serviceStyleHint { notesLines.append("Worship style: \(style)") }
                event.notes = notesLines.joined(separator: "\n")
            } else {
                event.notes = "Visit planned via AMEN App."
            }

            // Timing
            event.startDate = serviceDate
            let durationSeconds = TimeInterval((serviceTime?.durationMinutes ?? 90) * 60)
            event.endDate = serviceDate.addingTimeInterval(durationSeconds)

            // Location from address
            event.location = church.address

            do {
                try store.save(event, span: .thisEvent)
                let ekId = event.eventIdentifier
                dlog("[VisitPlanner] EK event created: \(ekId ?? "nil")")
                return ekId
            } catch {
                dlog("[VisitPlanner] EK save error: \(error)")
                return nil
            }
        }.value
    }

    /// Requests calendar write access using iOS 17+ API with fallback for older OS.
    private func requestCalendarAccess() async -> Bool {
        if #available(iOS 17.0, *) {
            do {
                return try await ekStore.requestWriteOnlyAccessToEvents()
            } catch {
                dlog("[VisitPlanner] EKEventStore requestWriteOnlyAccessToEvents error: \(error)")
                return false
            }
        } else {
            return await withCheckedContinuation { continuation in
                ekStore.requestAccess(to: .event) { granted, error in
                    if let error { dlog("[VisitPlanner] EK requestAccess error: \(error)") }
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    // MARK: - Private: Notifications

    /// Schedules a morning-of UNNotification at 8 AM on the service day.
    /// Returns the notification identifier, or nil if not authorized or scheduling fails.
    private func scheduleMorningOfReminder(
        for church: ChurchObject,
        serviceDate: Date,
        planId: String
    ) async -> String? {
        let authorized = await requestNotificationAccess()
        guard authorized else {
            dlog("[VisitPlanner] Notification access denied — skipping morning-of reminder")
            return nil
        }

        // Compute 8:00 AM on the service day
        let calendar = Calendar.current
        guard let morningDate = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: serviceDate) else {
            dlog("[VisitPlanner] Could not compute 8 AM for service date")
            return nil
        }

        // Do not schedule if in the past
        guard morningDate > Date() else {
            dlog("[VisitPlanner] Morning-of reminder date is in the past — skipping")
            return nil
        }

        let notificationId = "visit_planner_morningof_\(planId)"
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [notificationId])

        let content = UNMutableNotificationContent()
        content.title = "Your visit to \(church.name) is today."
        content.body = "Your visit to \(church.name) is today. Tap to prepare."
        content.sound = .default
        content.categoryIdentifier = "CHURCH_VISIT_REMINDER"
        content.userInfo = [
            "type": "visit_planner_morning_of",
            "plan_id": planId,
            "church_id": church.id,
            "church_name": church.name
        ]

        let comps = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: morningDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: notificationId, content: content, trigger: trigger)

        do {
            try await notificationCenter.add(request)
            dlog("[VisitPlanner] Scheduled morning-of reminder \(notificationId) for \(morningDate)")
            return notificationId
        } catch {
            dlog("[VisitPlanner] Notification schedule error: \(error)")
            return nil
        }
    }

    /// Requests UNNotification authorization. Returns true if currently or newly authorized.
    private func requestNotificationAccess() async -> Bool {
        let settings = await notificationCenter.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        case .denied:
            return false
        @unknown default:
            return false
        }
    }
}
