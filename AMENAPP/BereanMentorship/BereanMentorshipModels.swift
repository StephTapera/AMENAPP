// BereanMentorshipModels.swift
// AMENAPP — Berean Mentorship OS — Data models
// Swift 6, iOS 18+
// Color is NOT Codable — all Color properties are computed vars.

import Foundation
import SwiftUI

// MARK: - Mentorship

struct BereanMentorship: Identifiable, Codable {
    let id: String
    let mentorId: String
    let menteeId: String
    var mentorDisplayName: String
    var menteeDisplayName: String
    var focus: String               // e.g. "Leadership development"
    var startedAt: Date
    var status: BereanMentorshipStatus
    var sessionCount: Int
    var nextSessionDate: Date?
}

// BereanMentorshipStatus is defined in BereanOSModels.swift (single source of truth)

// MARK: - Mentor signal

enum BereanMentorSignal: String, CaseIterable {
    case needsAttention
    case openQuestion
    case prayerRequest
    case upcomingSession
    case progressUpdate
    case suggestedResource

    var displayName: String {
        switch self {
        case .needsAttention:    return "Needs Attention"
        case .openQuestion:      return "Open Question"
        case .prayerRequest:     return "Prayer Request"
        case .upcomingSession:   return "Upcoming Session"
        case .progressUpdate:    return "Progress Update"
        case .suggestedResource: return "Suggested Resource"
        }
    }

    var systemImage: String {
        switch self {
        case .needsAttention:    return "exclamationmark.circle.fill"
        case .openQuestion:      return "questionmark.circle.fill"
        case .prayerRequest:     return "hands.and.sparkles.fill"
        case .upcomingSession:   return "calendar.circle.fill"
        case .progressUpdate:    return "chart.line.uptrend.xyaxis.circle.fill"
        case .suggestedResource: return "book.circle.fill"
        }
    }

    // Color is NOT stored — computed only
    var color: Color {
        switch self {
        case .needsAttention:    return Color(hex: "#E05252")
        case .openQuestion:      return Color(hex: "#C9A84C")
        case .prayerRequest:     return Color(hex: "#A78FD4")
        case .upcomingSession:   return Color(hex: "#4C9EC9")
        case .progressUpdate:    return Color(hex: "#4CAF82")
        case .suggestedResource: return Color(hex: "#C9A84C")
        }
    }

    /// 1 = highest priority
    var priority: Int {
        switch self {
        case .needsAttention:    return 1
        case .prayerRequest:     return 1
        case .openQuestion:      return 2
        case .upcomingSession:   return 2
        case .progressUpdate:    return 3
        case .suggestedResource: return 3
        }
    }
}

// MARK: - Pulse item

struct BereanMentorPulseItem: Identifiable {
    let id: String
    let menteeId: String
    let menteeName: String
    let signal: BereanMentorSignal
    let detail: String
    let date: Date
}

// MARK: - Mentor pulse (aggregated view for a mentor)

struct BereanMentorPulse {
    var mentorships: [BereanMentorship]
    var items: [BereanMentorPulseItem]
    let generatedAt: Date
}

// MARK: - Growth plan (Codable — no Color stored)

struct BereanMenteeGrowthPlan: Codable {
    var goals: [String]
    var currentStudy: String?
    var nextSessionDate: Date?
    var suggestedResources: [String]
    var milestones: [BereanMilestoneBadge]
}

// MARK: - Milestone badge

struct BereanMilestoneBadge: Identifiable, Codable {
    let id: String
    let title: String
    let earnedAt: Date
    let iconName: String   // SF Symbol name
}

// MARK: - Firestore decode helpers

extension BereanMentorship {
    init?(documentID: String, data: [String: Any]) {
        guard
            let mentorId          = data["mentorId"]          as? String,
            let menteeId          = data["menteeId"]          as? String,
            let mentorDisplayName = data["mentorDisplayName"] as? String,
            let menteeDisplayName = data["menteeDisplayName"] as? String,
            let focus             = data["focus"]             as? String,
            let startedAtTs       = data["startedAt"]         as? Timestamp,
            let statusRaw         = data["status"]            as? String,
            let status            = BereanMentorshipStatus(rawValue: statusRaw)
        else { return nil }

        let nextSessionDate: Date? = (data["nextSessionDate"] as? Timestamp).map { $0.dateValue() }

        self.init(
            id: documentID,
            mentorId: mentorId,
            menteeId: menteeId,
            mentorDisplayName: mentorDisplayName,
            menteeDisplayName: menteeDisplayName,
            focus: focus,
            startedAt: startedAtTs.dateValue(),
            status: status,
            sessionCount: data["sessionCount"] as? Int ?? 0,
            nextSessionDate: nextSessionDate
        )
    }
}

extension BereanMilestoneBadge {
    init?(data: [String: Any]) {
        guard
            let id       = data["id"]       as? String,
            let title    = data["title"]    as? String,
            let earnedTs = data["earnedAt"] as? Timestamp,
            let iconName = data["iconName"] as? String
        else { return nil }
        self.init(id: id, title: title, earnedAt: earnedTs.dateValue(), iconName: iconName)
    }
}

// MARK: - Mock data (DEBUG only)

#if DEBUG
enum BereanMentorshipMockData {
    static let mentorships: [BereanMentorship] = [
        BereanMentorship(
            id: "ment_001",
            mentorId: "uid_mentor",
            menteeId: "uid_mentee_1",
            mentorDisplayName: "Jordan B.",
            menteeDisplayName: "Marcus T.",
            focus: "Leadership development",
            startedAt: Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? Date(),
            status: .active,
            sessionCount: 6,
            nextSessionDate: Calendar.current.date(byAdding: .day, value: 4, to: Date())
        ),
        BereanMentorship(
            id: "ment_002",
            mentorId: "uid_mentor",
            menteeId: "uid_mentee_2",
            mentorDisplayName: "Jordan B.",
            menteeDisplayName: "Priya S.",
            focus: "Spiritual disciplines",
            startedAt: Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date(),
            status: .active,
            sessionCount: 2,
            nextSessionDate: Calendar.current.date(byAdding: .day, value: 10, to: Date())
        )
    ]

    static let pulseItems: [BereanMentorPulseItem] = [
        BereanMentorPulseItem(
            id: "pulse_001",
            menteeId: "uid_mentee_1",
            menteeName: "Marcus T.",
            signal: .prayerRequest,
            detail: "Struggling with anxiety before a big presentation.",
            date: Calendar.current.date(byAdding: .hour, value: -2, to: Date()) ?? Date()
        ),
        BereanMentorPulseItem(
            id: "pulse_002",
            menteeId: "uid_mentee_2",
            menteeName: "Priya S.",
            signal: .openQuestion,
            detail: "Had a question about the Sermon on the Mount passage we discussed.",
            date: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        ),
        BereanMentorPulseItem(
            id: "pulse_003",
            menteeId: "uid_mentee_1",
            menteeName: "Marcus T.",
            signal: .upcomingSession,
            detail: "Session in 4 days — no prep notes yet.",
            date: Date()
        )
    ]

    static let growthPlan = BereanMenteeGrowthPlan(
        goals: [
            "Read through the book of Proverbs",
            "Practice daily 10-minute silent prayer",
            "Lead one small group discussion"
        ],
        currentStudy: "Proverbs — Wisdom for Everyday Life",
        nextSessionDate: Calendar.current.date(byAdding: .day, value: 4, to: Date()),
        suggestedResources: [
            "The Cost of Discipleship — Bonhoeffer",
            "Celebration of Discipline — Foster",
            "Mere Christianity — C.S. Lewis"
        ],
        milestones: [
            BereanMilestoneBadge(
                id: "badge_001",
                title: "First Session",
                earnedAt: Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? Date(),
                iconName: "star.circle.fill"
            ),
            BereanMilestoneBadge(
                id: "badge_002",
                title: "Month of Growth",
                earnedAt: Calendar.current.date(byAdding: .month, value: -2, to: Date()) ?? Date(),
                iconName: "leaf.circle.fill"
            ),
            BereanMilestoneBadge(
                id: "badge_003",
                title: "Six Sessions",
                earnedAt: Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date(),
                iconName: "flame.circle.fill"
            )
        ]
    )
}
#endif
