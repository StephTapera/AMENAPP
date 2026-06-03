// AmenLivekitLiveRoomProvider.swift
// AMEN Connect — LiveKit-backed live room provider
//
// Targets LiveKit client-sdk-swift >= 2.0.0 (LiveKit, LiveKitWebRTC, LiveKitUniFFI)
// Token + server URL come from the getLivekitToken Firebase callable.
//
// Firebase secrets required:
//   firebase functions:secrets:set LIVEKIT_API_KEY
//   firebase functions:secrets:set LIVEKIT_API_SECRET
//   firebase functions:secrets:set LIVEKIT_URL   (e.g. wss://myproject.livekit.cloud)

import SwiftUI
import LiveKit
import FirebaseFunctions

// MARK: - LiveKit Live Room Provider

@MainActor
final class AmenLivekitLiveRoomProvider: NSObject, AmenLiveRoomProvider, ObservableObject {

    // MARK: State

    private let room = Room()
    private var spaceId: String?

    @Published var participants: [AmenLiveRoomParticipant] = []
    @Published var isLocalAudioMuted = false
    @Published var isLocalVideoOff = false

    // MARK: Configuration

    func configure(spaceId: String) {
        self.spaceId = spaceId
        room.add(delegate: self)
    }

    // MARK: AmenLiveRoomProvider

    func joinRoom(roomId: String, userId: String, displayName: String, mode: AmenLiveRoomMode) async throws {
        let result = try await Functions.functions()
            .httpsCallable("getLivekitToken")
            .call(["spaceId": spaceId ?? "", "roomId": roomId, "displayName": displayName])

        guard let data = result.data as? [String: Any],
              let token = data["token"] as? String,
              let serverURL = data["url"] as? String else {
            throw AmenLivekitError.tokenFetchFailed
        }

        let connectOptions = ConnectOptions(autoSubscribe: true)
        try await room.connect(url: serverURL, token: token, connectOptions: connectOptions)

        try await room.localParticipant.setMicrophone(enabled: true)
        if mode == .video {
            try await room.localParticipant.setCamera(enabled: true)
        }
        refreshParticipants()
    }

    func leaveRoom() async {
        await room.disconnect()
        participants = []
    }

    func muteLocalAudio(_ muted: Bool) {
        isLocalAudioMuted = muted
        Task { try? await room.localParticipant.setMicrophone(enabled: !muted) }
    }

    func muteLocalVideo(_ muted: Bool) {
        isLocalVideoOff = muted
        Task { try? await room.localParticipant.setCamera(enabled: !muted) }
    }

    func muteParticipant(userId: String) async throws {
        // LiveKit server-side mute requires the server SDK.
        // We write the signal through Firebase; the participant's device honours it.
        let _ = try await Functions.functions()
            .httpsCallable("muteParticipant")
            .call(["spaceId": spaceId ?? "", "roomId": room.name ?? "", "targetUserId": userId])
    }

    // MARK: Video Views

    var localVideoView: AnyView {
        AnyView(LocalLivekitVideoView(room: room))
    }

    var participantVideoView: (String) -> AnyView {
        { [weak self] identity in
            AnyView(RemoteLivekitVideoView(room: self?.room, identity: identity))
        }
    }

    // MARK: Private

    private func refreshParticipants() {
        participants = room.remoteParticipants.values.map { p in
            AmenLiveRoomParticipant(
                id: p.identity.stringValue,
                displayName: p.name ?? p.identity.stringValue,
                isHost: false,
                isMod: false,
                hasRaisedHand: false,
                isMuted: !p.isMicrophoneEnabled,
                joinedAt: Date()
            )
        }
    }
}

// MARK: - RoomDelegate

extension AmenLivekitLiveRoomProvider: @preconcurrency RoomDelegate {

    func room(_ room: Room, participantDidConnect participant: RemoteParticipant) {
        refreshParticipants()
    }

    func room(_ room: Room, participantDidDisconnect participant: RemoteParticipant) {
        refreshParticipants()
    }

    func room(_ room: Room,
              participant: RemoteParticipant,
              trackPublished publication: RemoteTrackPublication) {
        refreshParticipants()
    }

    func room(_ room: Room,
              participant: RemoteParticipant,
              trackUnpublished publication: RemoteTrackPublication) {
        refreshParticipants()
    }

    func room(_ room: Room,
              participant: RemoteParticipant,
              didSubscribeTrack publication: RemoteTrackPublication,
              track: Track) {
        refreshParticipants()
    }
}

// MARK: - Local Video View

private struct LocalLivekitVideoView: View {
    let room: Room

    var body: some View {
        Group {
            if let track = room.localParticipant.firstCameraVideoTrack {
                SwiftUIVideoView(track, layoutMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                Color(red: 0.08, green: 0.08, blue: 0.10)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        Image(systemName: "video.slash.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.white.opacity(0.4))
                    )
            }
        }
    }
}

// MARK: - Remote Video View

private struct RemoteLivekitVideoView: View {
    let room: Room?
    let identity: String

    private var remoteParticipant: RemoteParticipant? {
        room?.remoteParticipants.values.first { $0.identity.stringValue == identity }
    }

    var body: some View {
        Group {
            if let participant = remoteParticipant,
               let track = participant.firstCameraVideoTrack {
                SwiftUIVideoView(track, layoutMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                RemoteParticipantPlaceholder(identity: identity)
            }
        }
    }
}

private struct RemoteParticipantPlaceholder: View {
    let identity: String

    var body: some View {
        ZStack {
            Color(red: 0.08, green: 0.08, blue: 0.10)
            Circle()
                .fill(Color(red: 0.43, green: 0.29, blue: 0.71).opacity(0.35))
                .frame(width: 64, height: 64)
                .overlay(
                    Text(initials(from: identity))
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func initials(from name: String) -> String {
        name.split(separator: " ").prefix(2)
            .compactMap { $0.first.map(String.init) }
            .joined()
            .uppercased()
    }
}

// MARK: - Error

private enum AmenLivekitError: LocalizedError {
    case tokenFetchFailed
    var errorDescription: String? { "Failed to fetch LiveKit session token from server." }
}
