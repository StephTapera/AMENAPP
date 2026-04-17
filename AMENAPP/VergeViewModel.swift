//
//  VergeViewModel.swift
//  AMENAPP
//
//  ObservableObject driving Verge rooms, creator profile, and AI summaries.
//

import SwiftUI
import Combine
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions

@MainActor
class VergeViewModel: ObservableObject {

    // MARK: - Published State

    @Published var liveRooms: [VergeRoom]     = []
    @Published var upcomingRooms: [VergeRoom] = []
    @Published var pastRooms: [VergeRoom]     = []
    @Published var isLoading                  = false
    @Published var creatorProfile: VergeCreatorProfile?

    // MARK: - Private

    private lazy var db = Firestore.firestore()
    private var roomsListener: ListenerRegistration?

    // MARK: - Rooms Listener

    func loadRooms(workspaceId: String) {
        isLoading = true
        roomsListener?.remove()

        roomsListener = db.collection("vergeRooms")
            .whereField("workspaceId", isEqualTo: workspaceId)
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if let error {
                    dlog("VergeViewModel: rooms listener error — \(error.localizedDescription)")
                    self.isLoading = false
                    return
                }
                let rooms = snapshot?.documents.compactMap {
                    try? $0.data(as: VergeRoom.self)
                } ?? []

                self.liveRooms     = rooms.filter { $0.isLive }
                self.upcomingRooms = rooms.filter { $0.isUpcoming }
                self.pastRooms     = rooms.filter { $0.status == .ended || $0.status == .archived }
                self.isLoading     = false
            }
    }

    // MARK: - Create Room

    func createRoom(
        workspaceId: String,
        title: String,
        description: String,
        type: VergeRoomType,
        scheduledAt: Date?,
        maxParticipants: Int,
        isMonetized: Bool,
        ticketPrice: Double?,
        subscribersOnly: Bool,
        isRecorded: Bool
    ) async throws -> VergeRoom {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "Verge", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }

        let status: VergeRoomStatus = scheduledAt != nil ? .waiting : .live
        let startedAt: Date?        = scheduledAt == nil  ? Date()   : nil

        var data: [String: Any] = [
            "workspaceId":     workspaceId,
            "title":           title,
            "description":     description,
            "type":            type.rawValue,
            "status":          status.rawValue,
            "hostId":          uid,
            "participantIds":  [uid],
            "maxParticipants": maxParticipants,
            "isRecorded":      isRecorded,
            "isMonetized":     isMonetized,
            "subscribersOnly": subscribersOnly,
            "createdAt":       FieldValue.serverTimestamp()
        ]
        if let sa = scheduledAt { data["scheduledAt"] = Timestamp(date: sa) }
        if let sa = startedAt   { data["startedAt"]   = Timestamp(date: sa) }
        if isMonetized, let price = ticketPrice { data["ticketPrice"] = price }

        let ref = try await db.collection("vergeRooms").addDocument(data: data)
        let snap = try await ref.getDocument()
        guard let room = try? snap.data(as: VergeRoom.self) else {
            throw NSError(domain: "Verge", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to decode created room"])
        }
        dlog("VergeViewModel: created room \(room.id ?? "?")")
        return room
    }

    // MARK: - Join Room

    func joinRoom(_ room: VergeRoom) async throws {
        guard let uid = Auth.auth().currentUser?.uid,
              let roomId = room.id else { return }

        guard !room.participantIds.contains(uid) else { return }
        guard room.participantCount < room.maxParticipants else {
            throw NSError(domain: "Verge", code: 403, userInfo: [NSLocalizedDescriptionKey: "Room is full"])
        }

        try await db.collection("vergeRooms").document(roomId).updateData([
            "participantIds": FieldValue.arrayUnion([uid])
        ])
        dlog("VergeViewModel: joined room \(roomId)")
    }

    // MARK: - End Room

    func endRoom(_ room: VergeRoom) async throws {
        guard let roomId = room.id else { return }
        try await db.collection("vergeRooms").document(roomId).updateData([
            "status":  VergeRoomStatus.ended.rawValue,
            "endedAt": FieldValue.serverTimestamp()
        ])
        dlog("VergeViewModel: ended room \(roomId)")
    }

    // MARK: - Creator Profile

    func loadCreatorProfile(userId: String) async {
        do {
            let snap = try await db.collection("vergeCreatorProfiles")
                .whereField("userId", isEqualTo: userId)
                .limit(to: 1)
                .getDocuments()
            creatorProfile = snap.documents.compactMap { try? $0.data(as: VergeCreatorProfile.self) }.first
        } catch {
            dlog("VergeViewModel: load creator profile error — \(error.localizedDescription)")
        }
    }

    // MARK: - AI Room Summary

    func generateRoomSummary(roomId: String, messages: [VergeMessage]) async -> String {
        let sample = messages.suffix(30)
        let transcript = sample.map { "[\($0.authorName)]: \($0.content)" }.joined(separator: "\n")
        let systemPrompt = """
You are Berean, an AI assistant for a faith-based live discussion platform called Verge.
Summarise the following live room transcript into 3–5 bullet points covering main themes, scripture references mentioned, and key takeaways. Be concise and spiritually grounding.
"""
        do {
            let fn = Functions.functions().httpsCallable("bereanChatProxy")
            let result = try await fn.call([
                "systemPrompt": systemPrompt,
                "userMessage":  transcript,
                "maxTokens":    400
            ] as [String: Any])
            if let data = result.data as? [String: Any],
               let text = data["text"] as? String {
                return text
            }
        } catch {
            dlog("VergeViewModel: generateRoomSummary error — \(error.localizedDescription)")
        }
        return "Summary unavailable."
    }

    // MARK: - Deinit

    deinit {
        roomsListener?.remove()
    }
}
