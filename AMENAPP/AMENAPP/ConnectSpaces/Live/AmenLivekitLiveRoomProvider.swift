// AmenLivekitLiveRoomProvider.swift
// AMEN Connect — LiveKit-backed live room provider (stub)
//
// LiveKit SPM package is not yet linked.
// To activate: add https://github.com/livekit/client-sdk-swift via Xcode → File → Add Packages,
// then replace this file with the full implementation in the git history.
//
// Firebase secrets required when activating:
//   firebase functions:secrets:set LIVEKIT_API_KEY
//   firebase functions:secrets:set LIVEKIT_API_SECRET
//   firebase functions:secrets:set LIVEKIT_URL

import SwiftUI
import FirebaseFunctions

// MARK: - LiveKit Live Room Provider (Stub — LiveKit not linked)

@MainActor
final class AmenLivekitLiveRoomProvider: NSObject, AmenLiveRoomProvider, ObservableObject {

    @Published var participants: [AmenLiveRoomParticipant] = []
    @Published var isLocalAudioMuted = false
    @Published var isLocalVideoOff = false

    func configure(spaceId: String) {}

    func joinRoom(roomId: String, userId: String, displayName: String, mode: AmenLiveRoomMode) async throws {
        dlog("⚠️ LiveKit not linked — joinRoom is a no-op. Add LiveKit SPM package to activate.")
    }

    func leaveRoom() async {
        participants = []
    }

    func muteLocalAudio(_ muted: Bool) {
        isLocalAudioMuted = muted
    }

    func muteLocalVideo(_ muted: Bool) {
        isLocalVideoOff = muted
    }

    func muteParticipant(userId: String) async throws {
        dlog("⚠️ LiveKit not linked — muteParticipant is a no-op.")
    }

    var localVideoView: AnyView {
        AnyView(
            Color(.systemBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    Image(systemName: "video.slash.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                )
        )
    }

    var participantVideoView: (String) -> AnyView {
        { participantId in
            AnyView(
                ZStack {
                    Color(.secondarySystemBackground)
                    Text(String(participantId.prefix(2)).uppercased())
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            )
        }
    }
}
