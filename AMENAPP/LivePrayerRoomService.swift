//
//  LivePrayerRoomService.swift
//  AMENAPP
//
//  Feature 22: Live Prayer Rooms — real-time group prayer with live
//  reactions (amens floating up). Uses Firebase RTDB for low latency.
//

import Foundation
import FirebaseAuth
import FirebaseDatabase

@MainActor
class LivePrayerRoomService: ObservableObject {
    static let shared = LivePrayerRoomService()

    @Published var activeRooms: [PrayerRoom] = []
    @Published var currentRoom: PrayerRoom?
    @Published var liveReactions: [LiveReaction] = []
    @Published var participantCount = 0

    private let rtdb = Database.database().reference()
    private var roomListener: DatabaseHandle?
    private var reactionsListener: DatabaseHandle?

    private init() {}

    // MARK: - Models

    struct PrayerRoom: Identifiable, Codable {
        let id: String
        let hostId: String
        let hostName: String
        let title: String
        let description: String
        var participantCount: Int
        let createdAt: Date
        var isLive: Bool
    }

    struct LiveReaction: Identifiable {
        let id = UUID()
        let userId: String
        let emoji: String // "🙏", "✝️", "🔥", "❤️"
        let timestamp: Date
    }

    // MARK: - Create Room

    func createRoom(title: String, description: String) async throws -> String {
        guard let uid = Auth.auth().currentUser?.uid else { throw NSError(domain: "", code: 401) }
        let user = UserService.shared.currentUser
        let roomId = UUID().uuidString

        let roomData: [String: Any] = [
            "id": roomId,
            "hostId": uid,
            "hostName": user?.displayName ?? "Host",
            "title": title,
            "description": description,
            "participantCount": 1,
            "createdAt": ServerValue.timestamp(),
            "isLive": true,
        ]

        try await rtdb.child("prayerRooms").child(roomId).setValue(roomData)

        // Join as first participant
        try await rtdb.child("prayerRooms").child(roomId).child("participants").child(uid).setValue([
            "name": user?.displayName ?? "Unknown",
            "joinedAt": ServerValue.timestamp(),
        ])

        return roomId
    }

    // MARK: - Join Room

    func joinRoom(_ roomId: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let user = UserService.shared.currentUser

        // Add self as participant
        try? await rtdb.child("prayerRooms").child(roomId).child("participants").child(uid).setValue([
            "name": user?.displayName ?? "Unknown",
            "joinedAt": ServerValue.timestamp(),
        ])

        // Increment count atomically
        rtdb.child("prayerRooms").child(roomId).child("participantCount")
            .runTransactionBlock { data in
                let count = data.value as? Int ?? 0
                data.value = count + 1
                return .success(withValue: data)
            }

        // Listen for reactions
        startListeningToReactions(roomId: roomId)

        // Listen for participant count
        rtdb.child("prayerRooms").child(roomId).child("participantCount")
            .observe(.value) { [weak self] snapshot in
                Task { @MainActor in
                    self?.participantCount = snapshot.value as? Int ?? 0
                }
            }
    }

    // MARK: - Send Reaction

    func sendReaction(roomId: String, emoji: String) {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        rtdb.child("prayerRooms").child(roomId).child("reactions").childByAutoId().setValue([
            "userId": uid,
            "emoji": emoji,
            "timestamp": ServerValue.timestamp(),
        ])
    }

    // MARK: - Leave Room

    func leaveRoom(_ roomId: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        try? await rtdb.child("prayerRooms").child(roomId).child("participants").child(uid).removeValue()

        rtdb.child("prayerRooms").child(roomId).child("participantCount")
            .runTransactionBlock { data in
                let count = data.value as? Int ?? 1
                data.value = max(0, count - 1)
                return .success(withValue: data)
            }

        stopListening()
    }

    // MARK: - End Room (host only)

    func endRoom(_ roomId: String) async {
        try? await rtdb.child("prayerRooms").child(roomId).child("isLive").setValue(false)
        stopListening()
    }

    // MARK: - Listeners

    private func startListeningToReactions(roomId: String) {
        reactionsListener = rtdb.child("prayerRooms").child(roomId).child("reactions")
            .queryLimited(toLast: 1)
            .observe(.childAdded) { [weak self] snapshot in
                guard let data = snapshot.value as? [String: Any],
                      let emoji = data["emoji"] as? String,
                      let userId = data["userId"] as? String else { return }

                let reaction = LiveReaction(userId: userId, emoji: emoji, timestamp: Date())
                Task { @MainActor in
                    self?.liveReactions.append(reaction)
                    // Auto-remove after 3 seconds
                    Task {
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        await MainActor.run {
                            self?.liveReactions.removeAll { $0.id == reaction.id }
                        }
                    }
                }
            }
    }

    private func stopListening() {
        if let handle = reactionsListener {
            rtdb.removeObserver(withHandle: handle)
            reactionsListener = nil
        }
        if let handle = roomListener {
            rtdb.removeObserver(withHandle: handle)
            roomListener = nil
        }
    }

    // MARK: - Fetch Active Rooms

    func fetchActiveRooms() async {
        let snapshot = try? await rtdb.child("prayerRooms")
            .queryOrdered(byChild: "isLive")
            .queryEqual(toValue: true)
            .getData()

        guard let children = snapshot?.children.allObjects as? [DataSnapshot] else {
            activeRooms = []
            return
        }

        activeRooms = children.compactMap { child -> PrayerRoom? in
            guard let data = child.value as? [String: Any],
                  let title = data["title"] as? String else { return nil }
            return PrayerRoom(
                id: child.key,
                hostId: data["hostId"] as? String ?? "",
                hostName: data["hostName"] as? String ?? "Unknown",
                title: title,
                description: data["description"] as? String ?? "",
                participantCount: data["participantCount"] as? Int ?? 0,
                createdAt: Date(),
                isLive: true
            )
        }
    }
}
