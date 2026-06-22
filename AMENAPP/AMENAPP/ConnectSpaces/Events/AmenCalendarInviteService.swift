import Foundation
import EventKit

@MainActor
final class AmenCalendarInviteService {

    private let store = EKEventStore()

    func generateICSContent(for event: AmenSpaceEvent, spaceName: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withYear, .withMonth, .withDay, .withTime, .withTimeZone]

        let endDate = Calendar.current.date(
            byAdding: .minute,
            value: event.durationMinutes,
            to: event.scheduledAt
        ) ?? event.scheduledAt

        let uid = "\(event.id)@amen.app"
        let dtstamp = formatter.string(from: Date()).replacingOccurrences(of: "-", with: "").replacingOccurrences(of: ":", with: "")
        let dtstart = formatter.string(from: event.scheduledAt).replacingOccurrences(of: "-", with: "").replacingOccurrences(of: ":", with: "")
        let dtend = formatter.string(from: endDate).replacingOccurrences(of: "-", with: "").replacingOccurrences(of: ":", with: "")

        var lines: [String] = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//AMEN App//AMEN//EN",
            "CALSCALE:GREGORIAN",
            "METHOD:PUBLISH",
            "BEGIN:VEVENT",
            "UID:\(uid)",
            "DTSTAMP:\(dtstamp)",
            "DTSTART:\(dtstart)",
            "DTEND:\(dtend)",
            "SUMMARY:\(event.title) — \(spaceName)",
            "DESCRIPTION:\(event.eventDescription.replacingOccurrences(of: "\n", with: "\\n"))",
        ]

        if event.isRecurring, let rrule = event.recurrenceRule {
            lines.append("RRULE:\(rrule)")
        }

        lines += ["END:VEVENT", "END:VCALENDAR"]
        return lines.joined(separator: "\r\n")
    }

    func addToCalendar(event: AmenSpaceEvent, spaceName: String) async throws {
        let granted: Bool
        if #available(iOS 17.0, *) {
            granted = try await store.requestWriteOnlyAccessToEvents()
        } else {
            granted = try await store.requestAccess(to: .event)
        }

        guard granted else {
            throw AmenCalendarError.permissionDenied(
                "Calendar access was denied. Please enable it in Settings > AMEN > Calendars."
            )
        }

        let ekEvent = EKEvent(eventStore: store)
        ekEvent.title = "\(event.title) — \(spaceName)"
        ekEvent.startDate = event.scheduledAt
        ekEvent.endDate = Calendar.current.date(
            byAdding: .minute,
            value: event.durationMinutes,
            to: event.scheduledAt
        ) ?? event.scheduledAt
        ekEvent.notes = event.eventDescription
        ekEvent.calendar = store.defaultCalendarForNewEvents

        if event.isRecurring, let rrule = event.recurrenceRule {
            if let rule = buildEKRecurrenceRule(from: rrule) {
                ekEvent.recurrenceRules = [rule]
            }
        }

        try store.save(ekEvent, span: .thisEvent)
    }

    func icsData(for event: AmenSpaceEvent, spaceName: String) -> Data {
        let ics = generateICSContent(for: event, spaceName: spaceName)
        return Data(ics.utf8)
    }

    // RRULE strings from Firestore are iCal-format; map a subset to EKRecurrenceRule.
    // Only handles FREQ=DAILY/WEEKLY/MONTHLY/YEARLY with optional INTERVAL.
    private func buildEKRecurrenceRule(from rrule: String) -> EKRecurrenceRule? {
        var frequency: EKRecurrenceFrequency = .weekly
        var interval = 1

        let parts = rrule.components(separatedBy: ";")
        for part in parts {
            let kv = part.components(separatedBy: "=")
            guard kv.count == 2 else { continue }
            switch kv[0].uppercased() {
            case "FREQ":
                switch kv[1].uppercased() {
                case "DAILY":   frequency = .daily
                case "WEEKLY":  frequency = .weekly
                case "MONTHLY": frequency = .monthly
                case "YEARLY":  frequency = .yearly
                default: break
                }
            case "INTERVAL":
                interval = Int(kv[1]) ?? 1
            default:
                break
            }
        }
        return EKRecurrenceRule(
            recurrenceWith: frequency,
            interval: interval,
            end: nil
        )
    }
}

enum AmenCalendarError: LocalizedError {
    case permissionDenied(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied(let msg): return msg
        }
    }
}
