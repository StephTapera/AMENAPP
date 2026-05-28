// MentorModel.swift
// AMENAPP
// Extended mentorship data models

import Foundation
import SwiftUI
import FirebaseFirestore

// MARK: - Mentor Availability Status
enum MentorStatus: String, Codable, Hashable {
    case open, limited, closed, onLeave
    var label: String {
        switch self {
        case .open:    return "Open"
        case .limited: return "Limited"
        case .closed:  return "Closed"
        case .onLeave: return "On Leave"
        }
    }
    var color: Color {
        switch self {
        case .open:    return Color(red: 0.09, green: 0.64, blue: 0.29)
        case .limited: return Color(red: 0.85, green: 0.47, blue: 0.02)
        case .closed:  return Color(.systemGray3)
        case .onLeave: return Color(.systemGray3)
        }
    }
    var dotColor: Color { color }
}

// MARK: - Mentorship Plan
struct MentorshipPlan: Identifiable, Codable, Hashable {
    var id: String
    var name: String                // "Community", "Growth", "Deep Discipleship"
    var priceMonthly: Double        // 0.0 for free
    var stripePriceId: String       // from Stripe dashboard (empty for free)
    var sessionsPerMonth: Int
    var includesChat: Bool
    var includesCheckIns: Bool
    var includesCustomPlan: Bool
    var description: String
    var badge: String?              // "Free", "Popular", "Premium"

    var isFree: Bool { priceMonthly == 0 }
    var priceLabel: String { isFree ? "Free" : "$\(String(format: "%.0f", priceMonthly))/mo" }

    init(id: String, name: String, priceMonthly: Double, stripePriceId: String,
         sessionsPerMonth: Int, includesChat: Bool, includesCheckIns: Bool,
         includesCustomPlan: Bool, description: String, badge: String? = nil) {
        self.id = id
        self.name = name
        self.priceMonthly = priceMonthly
        self.stripePriceId = stripePriceId
        self.sessionsPerMonth = sessionsPerMonth
        self.includesChat = includesChat
        self.includesCheckIns = includesCheckIns
        self.includesCustomPlan = includesCustomPlan
        self.description = description
        self.badge = badge
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let price = try container.decode(Double.self, forKey: .priceMonthly)
        guard price >= 0 else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: [CodingKeys.priceMonthly],
                debugDescription: "priceMonthly must be non-negative"
            ))
        }
        self.priceMonthly = price

        let priceId = try container.decode(String.self, forKey: .stripePriceId)
        if price > 0 && priceId.trimmingCharacters(in: .whitespaces).isEmpty {
            throw DecodingError.dataCorrupted(.init(
                codingPath: [CodingKeys.stripePriceId],
                debugDescription: "stripePriceId is required for paid plans"
            ))
        }
        self.stripePriceId = priceId

        self.id = try container.decode(String.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.sessionsPerMonth = try container.decode(Int.self, forKey: .sessionsPerMonth)
        self.includesChat = try container.decode(Bool.self, forKey: .includesChat)
        self.includesCheckIns = try container.decode(Bool.self, forKey: .includesCheckIns)
        self.includesCustomPlan = try container.decode(Bool.self, forKey: .includesCustomPlan)
        self.description = try container.decode(String.self, forKey: .description)
        self.badge = try container.decodeIfPresent(String.self, forKey: .badge)
    }

    static func defaultPlans() -> [MentorshipPlan] {
        [
            MentorshipPlan(id: "community", name: "Community", priceMonthly: 0, stripePriceId: "",
                           sessionsPerMonth: 1, includesChat: true, includesCheckIns: false,
                           includesCustomPlan: false, description: "Monthly check-in + group support", badge: "Free"),
            MentorshipPlan(id: "growth", name: "Growth", priceMonthly: 19, stripePriceId: "price_growth",
                           sessionsPerMonth: 2, includesChat: true, includesCheckIns: true,
                           includesCustomPlan: false, description: "Bi-weekly sessions + check-ins", badge: "Popular"),
            MentorshipPlan(id: "deep", name: "Deep Discipleship", priceMonthly: 39, stripePriceId: "price_deep",
                           sessionsPerMonth: 4, includesChat: true, includesCheckIns: true,
                           includesCustomPlan: true, description: "Weekly sessions + custom growth plan", badge: "Premium")
        ]
    }
}

// MARK: - Mentorship Relationship
enum MentorshipRelationshipStatus: String, Codable {
    case active, paused, ended, pending
}

struct MentorshipRelationship: Identifiable, Codable {
    var id: String
    var mentorId: String
    var menteeId: String
    var planId: String
    var planName: String
    var startedAt: Date
    var status: MentorshipRelationshipStatus
    var sessionsCompleted: Int
    var totalSessions: Int
    var stripeSubscriptionId: String?
    var nextCheckInDate: Date?
    var mentorName: String
    var mentorPhotoURL: String?

    var sessionProgress: Double {
        guard totalSessions > 0 else { return 0 }
        return Double(sessionsCompleted) / Double(totalSessions)
    }
}

// MARK: - Check-In Status
enum CheckInStatus: String, Codable {
    case pending, completed, overdue
    var label: String {
        switch self {
        case .pending:   return "Pending"
        case .completed: return "Completed"
        case .overdue:   return "Overdue"
        }
    }
    var color: Color {
        switch self {
        case .pending:   return Color(red: 0.85, green: 0.47, blue: 0.02)
        case .completed: return Color(red: 0.09, green: 0.64, blue: 0.29)
        case .overdue:   return Color.red
        }
    }
}

struct MentorshipCheckIn: Identifiable, Codable {
    var id: String
    var relationshipId: String
    var mentorId: String
    var menteeId: String
    var mentorName: String
    var mentorPhotoURL: String?
    var prompt: String
    var dueDate: Date
    var completedAt: Date?
    var response: String?
    var mentorReply: String?
    var status: CheckInStatus

    var dueSectionLabel: String {
        let cal = Calendar.current
        if cal.isDateInToday(dueDate) { return "Due Today" }
        if cal.isDate(dueDate, equalTo: Date(), toGranularity: .weekOfYear) { return "This Week" }
        return "Upcoming"
    }
}

// MARK: - Mentor (extended from existing MentorProfile)
struct Mentor: Identifiable, Codable {
    var id: String
    var userId: String
    var name: String
    var role: String
    var church: String
    var bio: String
    var photoURL: String?
    var specialties: [String]
    var isVerified: Bool
    var availabilityStatus: MentorStatus
    var spotsAvailable: Int
    var plans: [MentorshipPlan]
    var rating: Double
    var sessionCount: Int
    var responseTimeHours: Int
}
