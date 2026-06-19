//  VolunteerBoardService.swift
//  AMEN — Smart Volunteer Board · Wave 0 · callable client.
//
//  Thin proxy over the us-east1 Cloud Functions. All decoding goes through the frozen
//  contracts (VolunteerContracts.swift). The server is authoritative for every invariant —
//  this client never decides fill/waitlist/blackout; it only renders what the server returns.

import Foundation
import Combine
import FirebaseFunctions

@MainActor
final class VolunteerBoardService: ObservableObject {

    static let shared = VolunteerBoardService()

    // Wave 0 functions deploy to us-east1 (us-central1 quota exhausted — see CLAUDE.md).
    private let functions = Functions.functions(region: "us-east1")

    private init() {}

    // MARK: - Board (I2: derived rollup)

    /// Loads the derived board for an event. Returns nil on error (caller shows a friendly empty state).
    func loadBoard(eventId: String) async -> VolunteerBoard? {
        do {
            let result = try await functions.httpsCallable("assembleVolunteerBoard")
                .call(["eventId": eventId])
            return try decode(VolunteerBoard.self, from: result.data)
        } catch {
            dlog("[VolunteerBoardService] loadBoard failed: \(error)")
            return nil
        }
    }

    // MARK: - Sign up (I1 atomic fill + I3 blackout — server enforced)

    /// One-tap sign up. The server runs the transactional atomic fill; this returns its decision.
    func signUp(eventId: String, role: String, volunteerId: String) async -> SignUpForSlotResult? {
        do {
            let result = try await functions.httpsCallable("signUpForSlot")
                .call(["eventId": eventId, "role": role, "volunteerId": volunteerId])
            return try decode(SignUpForSlotResult.self, from: result.data)
        } catch {
            dlog("[VolunteerBoardService] signUp failed: \(error)")
            return nil
        }
    }

    // MARK: - Leader actions

    /// Leader-only approval (signedUp → confirmed). Server enforces the leader check.
    func leaderApprove(assignmentId: String) async -> Bool {
        do {
            _ = try await functions.httpsCallable("leaderApprove")
                .call(["assignmentId": assignmentId])
            return true
        } catch {
            dlog("[VolunteerBoardService] leaderApprove failed: \(error)")
            return false
        }
    }

    /// Leader-only read of a private note. The server access-logs every read (I4).
    func getLeaderNote(eventId: String, volunteerId: String) async -> LeaderPrivateNote? {
        do {
            let result = try await functions.httpsCallable("getLeaderPrivateNote")
                .call(["eventId": eventId, "volunteerId": volunteerId])
            return try decode(LeaderPrivateNote.self, from: result.data)
        } catch {
            dlog("[VolunteerBoardService] getLeaderNote failed: \(error)")
            return nil
        }
    }

    /// Leader-only write of a private note. The server access-logs every write (I4).
    func setLeaderNote(eventId: String, volunteerId: String, note: String) async -> Bool {
        do {
            _ = try await functions.httpsCallable("setLeaderPrivateNote")
                .call(["eventId": eventId, "volunteerId": volunteerId, "note": note])
            return true
        } catch {
            dlog("[VolunteerBoardService] setLeaderNote failed: \(error)")
            return false
        }
    }

    /// Schedules push + email reminders for active assignees. NO SMS in Wave 0.
    func scheduleReminders(eventId: String) async -> Bool {
        do {
            _ = try await functions.httpsCallable("scheduleVolunteerReminders")
                .call(["eventId": eventId])
            return true
        } catch {
            dlog("[VolunteerBoardService] scheduleReminders failed: \(error)")
            return false
        }
    }

    // MARK: - Decoding

    /// Decodes a callable's `[String: Any]` payload into a Codable contract type via JSONSerialization.
    private func decode<T: Decodable>(_ type: T.Type, from data: Any) throws -> T {
        let json = try JSONSerialization.data(withJSONObject: data)
        return try JSONDecoder().decode(T.self, from: json)
    }
}
