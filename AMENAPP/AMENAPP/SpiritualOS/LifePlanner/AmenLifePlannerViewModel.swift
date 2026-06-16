import Foundation
import Observation
import FirebaseAuth
import FirebaseFirestore

// MARK: - PlannerEventType

enum PlannerEventType {
    case church
    case prayer
    case birthday
    case volunteer
    case reading

    var label: String {
        switch self {
        case .church:    return "Church Event"
        case .prayer:    return "Prayer"
        case .birthday:  return "Birthday"
        case .volunteer: return "Volunteer"
        case .reading:   return "Bible Reading"
        }
    }
}

// MARK: - PlannerEvent

struct PlannerEvent: Identifiable {
    let id: String
    let type: PlannerEventType
    let title: String
    let subtitle: String?       // space name, person name, etc.
    let startTime: Date
    let endTime: Date?
    let spaceId: String?
    let rsvpRequired: Bool
    let userHasRSVPd: Bool
    let suggestedReading: String?   // only for church events with study series
}

// MARK: - PlannerSourceType (retained for AmenLifePlannerSectionView compatibility)

enum PlannerSourceType: String, Codable, CaseIterable {
    case spaceEvent        = "space_event"
    case readingPlan       = "reading_plan"
    case prayerPlan        = "prayer_plan"
    case gathering         = "gathering"
    case personalNote      = "personal_note"
    case bereanSuggestion  = "berean_suggestion"
}

// MARK: - AmenLifePlannerViewModel

@Observable
@MainActor
final class AmenLifePlannerViewModel {

    // MARK: - Public State

    var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    var isExpanded: Bool = false
    var isLoading: Bool = false

    // All loaded events keyed by calendar day (start of day)
    private(set) var allEvents: [Date: [PlannerEvent]] = [:]

    // MARK: - Derived

    /// Events for a specific calendar day.
    func events(for date: Date) -> [PlannerEvent] {
        let key = Calendar.current.startOfDay(for: date)
        return (allEvents[key] ?? []).sorted { $0.startTime < $1.startTime }
    }

    /// Events grouped by day for the current week.
    var eventsThisWeek: [Date: [PlannerEvent]] {
        let cal = Calendar.current
        guard let week = cal.dateInterval(of: .weekOfYear, for: selectedDate) else { return [:] }
        var result: [Date: [PlannerEvent]] = [:]
        for offset in 0..<7 {
            if let day = cal.date(byAdding: .day, value: offset, to: week.start) {
                let key = cal.startOfDay(for: day)
                result[key] = allEvents[key] ?? []
            }
        }
        return result
    }

    /// AI suggestion text shown when certain conditions are met.
    var todaySuggestion: String? {
        _todaySuggestion
    }

    /// Events for today (convenience accessor used by section views).
    var todayEvents: [PlannerEvent] {
        events(for: Date())
    }

    /// Events for tomorrow.
    var tomorrowEvents: [PlannerEvent] {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return events(for: tomorrow)
    }

    // MARK: - Private backing

    private var _todaySuggestion: String?
    @ObservationIgnored private let db = Firestore.firestore()

    // MARK: - Load

    func load(userId: String) async {
        guard !userId.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }

        let cal = Calendar.current
        let now = Date()
        guard let thirtyDaysOut = cal.date(byAdding: .day, value: 30, to: now) else { return }

        var bucket: [Date: [PlannerEvent]] = [:]

        // ── 1. Church events per space ──────────────────────────────────────
        do {
            let spacesSnap = try await db
                .collection("users").document(userId)
                .collection("spaces")
                .getDocuments()

            for spaceDoc in spacesSnap.documents {
                let spaceId = spaceDoc.documentID
                let spaceName = spaceDoc.data()["name"] as? String ?? ""

                let eventsSnap = try await db
                    .collection("spaces").document(spaceId)
                    .collection("events")
                    .whereField("startTime", isGreaterThanOrEqualTo: Timestamp(date: now))
                    .whereField("startTime", isLessThanOrEqualTo: Timestamp(date: thirtyDaysOut))
                    .order(by: "startTime")
                    .limit(to: 5)
                    .getDocuments()

                for doc in eventsSnap.documents {
                    let data = doc.data()
                    guard let ts = data["startTime"] as? Timestamp else { continue }
                    let start = ts.dateValue()
                    let end: Date? = (data["endTime"] as? Timestamp)?.dateValue()
                    let rsvpIds = data["rsvpUserIds"] as? [String] ?? []
                    let studySeries = data["studySeries"] as? String
                    let reading = studySeries.map { _ in data["suggestedReading"] as? String ?? "Romans 12" }

                    let event = PlannerEvent(
                        id: doc.documentID,
                        type: .church,
                        title: data["title"] as? String ?? "Church Event",
                        subtitle: spaceName.isEmpty ? nil : spaceName,
                        startTime: start,
                        endTime: end,
                        spaceId: spaceId,
                        rsvpRequired: data["rsvpRequired"] as? Bool ?? false,
                        userHasRSVPd: rsvpIds.contains(userId),
                        suggestedReading: reading
                    )
                    let key = cal.startOfDay(for: start)
                    bucket[key, default: []].append(event)
                }
            }
        } catch {
            // degrade gracefully
        }

        // ── 2. Prayer plans ─────────────────────────────────────────────────
        do {
            let prayerSnap = try await db
                .collection("users").document(userId)
                .collection("prayerPlans")
                .getDocuments()

            for doc in prayerSnap.documents {
                let data = doc.data()
                guard let ts = data["scheduledTime"] as? Timestamp else { continue }
                let start = ts.dateValue()

                let event = PlannerEvent(
                    id: doc.documentID,
                    type: .prayer,
                    title: data["title"] as? String ?? "Prayer",
                    subtitle: data["frequency"] as? String,
                    startTime: start,
                    endTime: nil,
                    spaceId: nil,
                    rsvpRequired: false,
                    userHasRSVPd: false,
                    suggestedReading: nil
                )
                let key = cal.startOfDay(for: start)
                bucket[key, default: []].append(event)
            }
        } catch {
            // degrade gracefully
        }

        // ── 3. Bible reading plans ───────────────────────────────────────────
        do {
            let readingSnap = try await db
                .collection("users").document(userId)
                .collection("readingPlans")
                .getDocuments()

            for doc in readingSnap.documents {
                let data = doc.data()
                let event = PlannerEvent(
                    id: doc.documentID,
                    type: .reading,
                    title: data["planName"] as? String ?? "Reading Plan",
                    subtitle: data["todayReading"] as? String,
                    startTime: cal.startOfDay(for: now),
                    endTime: nil,
                    spaceId: nil,
                    rsvpRequired: false,
                    userHasRSVPd: false,
                    suggestedReading: data["todayReading"] as? String
                )
                let key = cal.startOfDay(for: now)
                bucket[key, default: []].append(event)
            }
        } catch {
            // degrade gracefully
        }

        // ── 4. Birthdays ─────────────────────────────────────────────────────
        do {
            let currentMonth = cal.component(.month, from: now)
            let nextMonthDate = cal.date(byAdding: .month, value: 1, to: now) ?? now
            let nextMonth = cal.component(.month, from: nextMonthDate)
            let nextMonthStart = cal.date(from: cal.dateComponents([.year, .month], from: nextMonthDate)) ?? nextMonthDate
            let firstWeekOfNextMonth = cal.date(byAdding: .day, value: 7, to: nextMonthStart) ?? nextMonthDate

            let connectionsSnap = try await db
                .collection("users").document(userId)
                .collection("connections")
                .getDocuments()

            for doc in connectionsSnap.documents {
                let data = doc.data()
                guard
                    let birthdayMonth = data["birthdayMonth"] as? Int,
                    let birthdayDay   = data["birthdayDay"]   as? Int
                else { continue }

                let isThisMonth = birthdayMonth == currentMonth
                var isEarlyNextMonth = false
                if birthdayMonth == nextMonth {
                    isEarlyNextMonth = birthdayDay <= 7 ||
                        (cal.date(from: DateComponents(month: birthdayMonth, day: birthdayDay)).map { $0 <= firstWeekOfNextMonth } ?? false)
                }

                guard isThisMonth || isEarlyNextMonth else { continue }

                let year = cal.component(.year, from: isThisMonth ? now : nextMonthDate)
                var comps = DateComponents()
                comps.year  = year
                comps.month = birthdayMonth
                comps.day   = birthdayDay
                let birthdayDate = cal.date(from: comps) ?? now

                let event = PlannerEvent(
                    id: doc.documentID + "_birthday",
                    type: .birthday,
                    title: "\(data["displayName"] as? String ?? "Friend")'s Birthday",
                    subtitle: nil,
                    startTime: cal.startOfDay(for: birthdayDate),
                    endTime: nil,
                    spaceId: nil,
                    rsvpRequired: false,
                    userHasRSVPd: false,
                    suggestedReading: nil
                )
                let key = cal.startOfDay(for: birthdayDate)
                bucket[key, default: []].append(event)
            }
        } catch {
            // degrade gracefully
        }

        // ── 5. Volunteer schedules ───────────────────────────────────────────
        do {
            let spacesSnap2 = try await db
                .collection("users").document(userId)
                .collection("spaces")
                .getDocuments()

            for spaceDoc in spacesSnap2.documents {
                let spaceId = spaceDoc.documentID
                let spaceName = spaceDoc.data()["name"] as? String ?? ""

                let scheduleSnap = try await db
                    .collection("spaces").document(spaceId)
                    .collection("volunteers").document(userId)
                    .collection("schedule")
                    .whereField("startTime", isGreaterThanOrEqualTo: Timestamp(date: now))
                    .getDocuments()

                for doc in scheduleSnap.documents {
                    let data = doc.data()
                    guard let ts = data["startTime"] as? Timestamp else { continue }
                    let start = ts.dateValue()

                    let event = PlannerEvent(
                        id: doc.documentID + "_vol",
                        type: .volunteer,
                        title: data["title"] as? String ?? "Volunteer Shift",
                        subtitle: spaceName.isEmpty ? nil : spaceName,
                        startTime: start,
                        endTime: (data["endTime"] as? Timestamp)?.dateValue(),
                        spaceId: spaceId,
                        rsvpRequired: false,
                        userHasRSVPd: false,
                        suggestedReading: nil
                    )
                    let key = cal.startOfDay(for: start)
                    bucket[key, default: []].append(event)
                }
            }
        } catch {
            // degrade gracefully
        }

        allEvents = bucket

        // ── 6. Today suggestion ──────────────────────────────────────────────
        await buildTodaySuggestion(userId: userId, cal: cal, now: now, bucket: bucket)
    }

    // MARK: - Today Suggestion

    private func buildTodaySuggestion(userId: String, cal: Calendar, now: Date, bucket: [Date: [PlannerEvent]]) async {
        let todayKey = cal.startOfDay(for: selectedDate)
        let todayChurchEvents = (bucket[todayKey] ?? []).filter { $0.type == .church }

        guard let event = todayChurchEvents.first, let spaceId = event.spaceId else {
            _todaySuggestion = nil
            return
        }

        do {
            let notesSnap = try await db
                .collection("users").document(userId)
                .collection("notes")
                .whereField("spaceId", isEqualTo: spaceId)
                .whereField("createdAt", isGreaterThanOrEqualTo: Timestamp(date: todayKey))
                .limit(to: 1)
                .getDocuments()

            if notesSnap.documents.isEmpty {
                let reading = event.suggestedReading ?? "Romans 12"
                _todaySuggestion = "\(event.title) tonight — suggested reading: \(reading)"
            } else {
                _todaySuggestion = nil
            }
        } catch {
            _todaySuggestion = nil
        }
    }
}
