//  VolunteerContracts.swift
//  AMEN — Smart Volunteer Board · Wave 0 · Swift mirror of contracts/volunteer.ts.
//  FROZEN: 2026-06-19. Source of truth is TypeScript; this mirrors it field-for-field.
//  Any change requires a contract-change note + re-freeze.
//
//  SCOPE (Wave 0): a single dated event only. NO recurrence, swaps, check-in, .ics, or SMS.
//
//  INVARIANTS (server-enforced; client re-asserts for UX only):
//    I1 No overfill · I2 Derived board · I3 Blackout respected · I4 Notes leader-only + access-logged.
//
//  NEW FILE — auto-included via the AMENAPP PBXFileSystemSynchronizedRootGroup (no pbxproj edit).

import Foundation

// MARK: - §1 ServiceEvent (single dated event; no recurrence)

struct ServiceEvent: Codable, Identifiable, Sendable {
    let id: String
    let title: String
    let startUTC: String   // ISO8601 instant (UTC); display localizes via `timezone`.
    let timezone: String   // IANA tz id — display-only in Wave 0.
    let location: String
}

// MARK: - §2 StaffingNeed

enum StaffingNeedStatus: String, Codable, Sendable {
    case open, full, needsBackup, closed
}

struct StaffingNeed: Codable, Sendable {
    let eventId: String
    let role: String
    let countNeeded: Int
    let status: StaffingNeedStatus
}

// MARK: - §3 Assignment

enum AssignmentStatus: String, Codable, Sendable {
    case signedUp, confirmed, declined, waitlisted
}

struct Assignment: Codable, Identifiable, Sendable {
    let id: String
    let eventId: String
    let role: String
    let volunteerId: String
    let status: AssignmentStatus
}

// MARK: - §4 VolunteerBoard (DERIVED read model — never a stored counter; I2)

enum BoardRoleStatus: String, Codable, Sendable {
    case open, full, needsBackup, closed
}

struct VolunteerBoardRole: Codable, Identifiable, Sendable {
    var id: String { role }
    let role: String
    let filled: Int   // counted from active assignments — derived
    let needed: Int
    let status: BoardRoleStatus
}

struct VolunteerBoard: Codable, Sendable {
    let eventId: String
    let roles: [VolunteerBoardRole]
}

// MARK: - §5 BlackoutDate (simple list in V0)

struct BlackoutDate: Codable, Sendable {
    let volunteerId: String
    let date: String   // "YYYY-MM-DD" (event-local calendar date)
}

// MARK: - §6 LeaderPrivateNote (leader-only; access-logged on every read; I4)

struct LeaderPrivateNote: Codable, Sendable {
    let volunteerId: String
    let note: String
    let leaderOnly: Bool   // always true — invariant marker; reads require leader role + audit log.
}

// MARK: - Callable result envelopes

enum SignUpDecision: String, Codable, Sendable {
    case fill, waitlist, reject_blackout, reject_duplicate
}

struct SignUpForSlotResult: Codable, Sendable {
    let decision: SignUpDecision
    let assignmentId: String?
    let resultingStatus: AssignmentStatus?
}
