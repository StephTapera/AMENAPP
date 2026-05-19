// SpatialMessagesService.swift
// AMENAPP
//
// Phase 5 — Spatial Social OS: shared viewing rooms + anchored replies.
//
// Thin wrapper over the four Cloud Function callables that own the lifecycle
// of a /sharedViewingRoom + the presenceSessions that pair with it. The
// client never writes those collections directly — membership transitions
// flow through these calls so that participant caps, host transitions, and
// presence cleanup all run server-side.
//
// All callables are App Check-enforced. Errors surface as `NSError` from
// the FirebaseFunctions layer; consumers should handle the standard
// `FunctionsErrorCode` set (.permissionDenied, .resourceExhausted, etc.)
// and present user-facing messaging accordingly.

import Foundation
import FirebaseFunctions

@MainActor
final class SpatialMessagesService: ObservableObject {

    static let shared = SpatialMessagesService()

    private let functions: Functions

    private init(functions: Functions = Functions.functions()) {
        self.functions = functions
    }

    // MARK: - Create

    struct CreateRoomResult: Decodable {
        let roomId: String
    }

    /// Host opens a new shared viewing room around a given media item.
    /// Server creates the /sharedViewingRooms doc + a presenceSession.
    func createSharedViewingRoom(postId: String, mediaId: String) async throws -> CreateRoomResult {
        let result = try await functions
            .httpsCallable("createSharedViewingRoom")
            .call([
                "postId": postId,
                "mediaId": mediaId,
            ])
        let decoded = try decode(CreateRoomResult.self, from: result.data)
        TrustSpineAnalytics.track(.sharedRoomCreated, params: [
            "room_id": decoded.roomId,
            "post_id": postId,
            "media_id": mediaId,
        ])
        return decoded
    }

    // MARK: - Join

    struct JoinRoomResult: Decodable {
        let roomId: String
        let joined: Bool
    }

    /// Join an existing room. Idempotent — repeating the call from the same
    /// uid does not duplicate membership but does NOT count as a new join.
    func joinSharedViewingRoom(roomId: String) async throws -> JoinRoomResult {
        let result = try await functions
            .httpsCallable("joinSharedViewingRoom")
            .call(["roomId": roomId])
        let decoded = try decode(JoinRoomResult.self, from: result.data)
        if decoded.joined {
            TrustSpineAnalytics.track(.sharedRoomJoined, params: ["room_id": decoded.roomId])
        }
        return decoded
    }

    // MARK: - Leave

    struct LeaveRoomResult: Decodable {
        let roomId: String
        let left: Bool
    }

    /// Leave a room. If the caller is the host the room is closed; otherwise
    /// participantUids is updated and the caller's presenceSession is ended.
    func leaveSharedViewingRoom(roomId: String) async throws -> LeaveRoomResult {
        let result = try await functions
            .httpsCallable("leaveSharedViewingRoom")
            .call(["roomId": roomId])
        return try decode(LeaveRoomResult.self, from: result.data)
    }

    // MARK: - Anchored Reply

    struct AnchoredReplyResult: Decodable {
        let replyId: String
        let roomId: String
    }

    /// Posts an anchored reply against the media timeline. The server
    /// validates the caller is a participant in the room and stamps a
    /// server timestamp; the client never writes /anchoredReplies directly.
    func postAnchoredReply(
        roomId: String,
        postId: String,
        anchorTimestampMs: Int,
        message: String
    ) async throws -> AnchoredReplyResult {
        let result = try await functions
            .httpsCallable("postAnchoredReply")
            .call([
                "roomId": roomId,
                "postId": postId,
                "anchorTimestampMs": anchorTimestampMs,
                "message": message,
            ])
        let decoded = try decode(AnchoredReplyResult.self, from: result.data)
        TrustSpineAnalytics.track(.anchoredReplyPosted, params: [
            "room_id": decoded.roomId,
            "post_id": postId,
        ])
        return decoded
    }

    // MARK: - Decoding helper

    private func decode<T: Decodable>(_ type: T.Type, from data: Any?) throws -> T {
        guard let data else {
            throw SpatialMessagesError.emptyResponse
        }
        let json = try JSONSerialization.data(withJSONObject: data)
        return try JSONDecoder().decode(T.self, from: json)
    }

    // MARK: - Errors

    enum SpatialMessagesError: Error, LocalizedError {
        case emptyResponse

        var errorDescription: String? {
            switch self {
            case .emptyResponse:
                return "Spatial messages service returned an empty response."
            }
        }
    }
}
