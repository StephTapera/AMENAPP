// ChurchJourneyPlanner.swift
// AMENAPP
//
// Local-first timing intelligence for Church Journey planning.
// Computes departure, reminder, prep, coffee, notes, and reflection windows
// from service time, travel estimate, user routine, and options.
//
// This runs entirely on-device (no network required) so planning UI
// updates are instant when toggles change. The Cloud Function mirrors
// this same logic server-side for authoritative timing storage.

import Foundation

// MARK: - Planner Inputs

struct ChurchJourneyPlannerInputs {
    let serviceStartAt: Date
    let serviceEndAt: Date
    let options: ChurchJourneyOptions
    let routeEstimateMinutes: Int
    let parkingComplexity: String // "low" | "medium" | "high"
    let quietHoursStart: Int?    // Hour 0-23, nil = disabled
    let quietHoursEnd: Int?
}

// MARK: - Planner

/// Computes all timing windows for a church journey plan.
/// All computation is synchronous and local — safe to call from SwiftUI
/// `onChange` or as a computed property in a ViewModel.
enum ChurchJourneyPlanner {

    static func computeTiming(from inputs: ChurchJourneyPlannerInputs) -> ChurchJourneyTiming {
        let serviceStart = inputs.serviceStartAt
        let serviceEnd = inputs.serviceEndAt
        let route = Double(inputs.routeEstimateMinutes)

        // Parking buffer
        let parkingBuffer: Double
        switch inputs.parkingComplexity {
        case "high":   parkingBuffer = 20
        case "medium": parkingBuffer = 10
        default:       parkingBuffer = 5
        }

        // Family mode adds 15 min
        let familyBuffer: Double = inputs.options.familyModeEnabled ? 15 : 0

        // Arrival buffer: 10 min before service
        let arrivalBuffer: Double = 10

        let totalLead = route + parkingBuffer + familyBuffer + arrivalBuffer
        let departure = serviceStart.addingTimeInterval(-totalLead * 60)

        // Coffee window: 20 min before departure to 5 min before
        let coffeeWindowStart: Date? = inputs.options.coffeeEnabled
            ? departure.addingTimeInterval(-20 * 60)
            : nil
        let coffeeWindowEnd: Date? = inputs.options.coffeeEnabled
            ? departure.addingTimeInterval(-5 * 60)
            : nil

        // Prep window: 30 min before departure if prep enabled
        let prepEnabled = inputs.options.worshipPrepEnabled || inputs.options.scripturePrepEnabled
        let prepStart: Date? = prepEnabled
            ? departure.addingTimeInterval(-30 * 60)
            : nil

        // Reminder: 60 min before departure — adjust for quiet hours
        var reminder = departure.addingTimeInterval(-60 * 60)
        reminder = adjustForQuietHours(
            reminder,
            quietStart: inputs.quietHoursStart,
            quietEnd: inputs.quietHoursEnd
        )

        // Notes prompt at service start
        let notesPrompt: Date? = inputs.options.noteModeEnabled ? serviceStart : nil

        // Reflection prompt 30 min after service ends
        let reflectionPrompt: Date? = inputs.options.reflectionEnabled
            ? serviceEnd.addingTimeInterval(30 * 60)
            : nil

        return ChurchJourneyTiming(
            reminderAt: reminder,
            prepStartAt: prepStart,
            departureAt: departure,
            coffeeWindowStartAt: coffeeWindowStart,
            coffeeWindowEndAt: coffeeWindowEnd,
            notesPromptAt: notesPrompt,
            reflectionPromptAt: reflectionPrompt
        )
    }

    /// Human-readable departure summary
    static func departureSummary(timing: ChurchJourneyTiming, serviceStart: Date) -> String {
        guard let departure = timing.departureAt else {
            return "Plan saved"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        let depStr = formatter.string(from: departure)
        let serviceStr = formatter.string(from: serviceStart)
        return "Leave by \(depStr) for \(serviceStr) service"
    }

    /// Returns a human-readable leave-in summary from now
    static func leaveInSummary(timing: ChurchJourneyTiming) -> String? {
        guard let departure = timing.departureAt else { return nil }
        let minutes = Int(departure.timeIntervalSinceNow / 60)
        if minutes <= 0 { return "Time to leave now" }
        if minutes < 60 { return "Leave in \(minutes) min" }
        let hours = minutes / 60
        let rem = minutes % 60
        if rem == 0 { return "Leave in \(hours)h" }
        return "Leave in \(hours)h \(rem)m"
    }

    // MARK: - Private

    private static func adjustForQuietHours(
        _ date: Date,
        quietStart: Int?,
        quietEnd: Int?
    ) -> Date {
        guard let qStart = quietStart, let qEnd = quietEnd else { return date }
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)

        let inQuiet: Bool
        if qStart < qEnd {
            inQuiet = hour >= qStart && hour < qEnd
        } else {
            inQuiet = hour >= qStart || hour < qEnd
        }

        guard inQuiet else { return date }

        // Push to end of quiet hours (same day or next day)
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = qEnd
        components.minute = 1
        var adjusted = calendar.date(from: components) ?? date
        if adjusted < date {
            adjusted = calendar.date(byAdding: .day, value: 1, to: adjusted) ?? adjusted
        }
        return adjusted
    }
}
