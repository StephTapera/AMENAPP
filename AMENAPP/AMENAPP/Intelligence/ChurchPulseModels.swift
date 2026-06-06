// ChurchPulseModels.swift
// AMENAPP — Church Pulse Models
//
// All models mirror the server-side ChurchPulse contract written by
// functions/intelligence/churchPulse.js.
//
// Contract invariants:
//   - `finite` is always true
//   - `spectacleCounters` is always false
//   - `pulseScore` is 0–100, derived from real Firestore data — never fabricated
//   - Raw member count is NEVER included (privacy)

import Foundation

// MARK: - MemberEngagement

enum MemberEngagement: String, Codable {
    case high    = "HIGH"
    case medium  = "MEDIUM"
    case low     = "LOW"
    case unknown = "UNKNOWN"

    /// Qualitative label for display — never exposes raw counts.
    var displayLabel: String {
        switch self {
        case .high:    return "Active community"
        case .medium:  return "Growing together"
        case .low:     return "Getting started"
        case .unknown: return "Building"
        }
    }
}

// MARK: - UpcomingEventsSnapshot

struct UpcomingEventsSnapshot: Codable {
    let count: Int
    let nextEventTitle: String?
    let nextEventDate: Double?   // epoch ms — nil if no upcoming events

    /// Returns a displayable date string for the next event, or nil.
    var formattedNextEventDate: String? {
        guard let ms = nextEventDate else { return nil }
        let date = Date(timeIntervalSince1970: ms / 1000)
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - ActivePrayerRequestsSnapshot

struct ActivePrayerRequestsSnapshot: Codable {
    let count: Int
}

// MARK: - VolunteerNeedsSnapshot

struct VolunteerNeedsSnapshot: Codable {
    let count: Int
    let roles: [String]
}

// MARK: - ChurchPulse

/// Server-computed church health snapshot.
/// All fields are derived from real Firestore documents — never fabricated.
struct ChurchPulse: Codable, Identifiable {
    let churchId: String
    let computedAt: Double           // epoch ms

    // Real-data snapshots
    let upcomingEvents: UpcomingEventsSnapshot
    let activePrayerRequests: ActivePrayerRequestsSnapshot
    let volunteerNeeds: VolunteerNeedsSnapshot
    let recentTeachingTopic: String?

    // Derived indicators (no raw member count)
    let memberEngagement: MemberEngagement
    let pulseScore: Int              // 0–100, ALWAYS derived
    let pulseReasons: [String]       // legible: "3 events this month", etc.

    // Formation invariants — always these values from the server
    let finite: Bool                 // always true
    let spectacleCounters: Bool      // always false

    // Identifiable
    var id: String { churchId }

    // MARK: - Derived helpers

    /// Qualitative health label for the pulse score.
    var healthLabel: String {
        switch pulseScore {
        case 90...100: return "Thriving"
        case 70...89:  return "Engaged"
        case 50...69:  return "Active"
        default:       return "Growing"
        }
    }

    /// Elapsed time since pulse was computed, as a human-readable string.
    var lastUpdatedLabel: String {
        let ageMs = Date().timeIntervalSince1970 * 1000 - computedAt
        let ageHours = ageMs / (1000 * 60 * 60)

        if ageHours < 1 {
            return "Updated just now"
        } else if ageHours < 2 {
            return "Updated 1 hour ago"
        } else {
            return "Updated \(Int(ageHours)) hours ago"
        }
    }
}

// MARK: - CodingKeys

extension ChurchPulse {
    enum CodingKeys: String, CodingKey {
        case churchId
        case computedAt
        case upcomingEvents
        case activePrayerRequests
        case volunteerNeeds
        case recentTeachingTopic
        case memberEngagement
        case pulseScore
        case pulseReasons
        case finite
        case spectacleCounters
    }
}
