// AmenLiveRoomProviderInterface.swift
// AMEN Connect + Spaces — Live Room SDK Abstraction Layer
// Built: 2026-06-02

import SwiftUI

// MARK: - Provider Protocol

/// Decouples the live room UI from any WebRTC SDK (Agora / Mux / LiveKit / etc.).
/// Conforming types must be classes so SwiftUI can hold a stable reference.
@MainActor
protocol AmenLiveRoomProvider: AnyObject {
    func joinRoom(roomId: String, userId: String, displayName: String, mode: AmenLiveRoomMode) async throws
    func leaveRoom() async
    func muteLocalAudio(_ muted: Bool)
    func muteLocalVideo(_ muted: Bool)
    func muteParticipant(userId: String) async throws

    /// The local user's own video tile (or a black placeholder when audio-only).
    var localVideoView: AnyView { get }

    /// Returns a video tile for a remote participant by userId.
    var participantVideoView: (String) -> AnyView { get }
}

// MARK: - Stub Provider

/// No-op stand-in used until a real SDK is linked.
/// Logs every call to OSLog; never throws; returns black placeholders for video.
final class AmenLiveRoomStubProvider: AmenLiveRoomProvider {
    func joinRoom(roomId: String, userId: String, displayName: String, mode: AmenLiveRoomMode) async throws {
        print("[AmenLiveRoomStubProvider] joinRoom(roomId:\(roomId) userId:\(userId) mode:\(mode))")
    }

    func leaveRoom() async {
        print("[AmenLiveRoomStubProvider] leaveRoom()")
    }

    func muteLocalAudio(_ muted: Bool) {
        print("[AmenLiveRoomStubProvider] muteLocalAudio(\(muted))")
    }

    func muteLocalVideo(_ muted: Bool) {
        print("[AmenLiveRoomStubProvider] muteLocalVideo(\(muted))")
    }

    func muteParticipant(userId: String) async throws {
        print("[AmenLiveRoomStubProvider] muteParticipant(userId:\(userId))")
    }

    var localVideoView: AnyView {
        Color.black.eraseToAnyView()
    }

    var participantVideoView: (String) -> AnyView {
        { _ in Color.black.eraseToAnyView() }
    }
}

// MARK: - View Helper

extension View {
    func eraseToAnyView() -> AnyView {
        AnyView(self)
    }
}
