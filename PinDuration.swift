//
//  PinDuration.swift
//  AMENAPP
//
//  How long a pinned post stays pinned.
//

import Foundation
import FirebaseFirestore

enum PinDuration: CaseIterable, Identifiable {
    case h24
    case h48
    case week
    case sunday
    case indefinite

    var id: String { label }

    var label: String {
        switch self {
        case .h24:        return "24 hours"
        case .h48:        return "48 hours"
        case .week:       return "1 week"
        case .sunday:     return "Until Sunday"
        case .indefinite: return "Keep pinned"
        }
    }

    var icon: String {
        switch self {
        case .h24:        return "clock"
        case .h48:        return "clock.badge.2"
        case .week:       return "calendar.badge.clock"
        case .sunday:     return "sun.max"
        case .indefinite: return "pin.fill"
        }
    }

    /// Firestore Timestamp for expiry, or nil for indefinite.
    var timestamp: Timestamp? {
        switch self {
        case .h24:        return Timestamp(date: Date.now.addingTimeInterval(86_400))
        case .h48:        return Timestamp(date: Date.now.addingTimeInterval(172_800))
        case .week:       return Timestamp(date: Date.now.addingTimeInterval(604_800))
        case .sunday:     return Timestamp(date: nextSunday())
        case .indefinite: return nil
        }
    }

    private func nextSunday() -> Date {
        var cal = Calendar.current
        cal.firstWeekday = 1 // Sunday
        let today = cal.startOfDay(for: Date.now)
        let weekday = cal.component(.weekday, from: today) // 1 = Sunday
        let daysUntilSunday = weekday == 1 ? 7 : (8 - weekday)
        return cal.date(byAdding: .day, value: daysUntilSunday, to: today)
            ?? today.addingTimeInterval(604_800)
    }
}
