// AmenFirebaseLiveRoomProvider.swift
// AMEN Connect — Firebase-backed live room provider
//
// Implements AmenLiveRoomProvider using Firebase Realtime Database for room
// state and presence. AVCaptureSession is used for local camera/mic preview.
//
// For production multi-party A/V transport: replace the stub
// `participantVideoView` and `localVideoView` implementations with a real
// WebRTC SFU SDK (Agora, Livekit, Mux). The SPM package to add:
//   Agora:   https://github.com/AgoraIO/AgoraRtcEngine_iOS
//   Livekit: https://github.com/livekit/client-sdk-swift
// Then create an `AmenAgoraLiveRoomProvider` or `AmenLivekitLiveRoomProvider`
// that also conforms to `AmenLiveRoomProvider`.

import Foundation
import SwiftUI
import AVFoundation
import FirebaseFunctions
import FirebaseDatabase

// MARK: - Firebase Live Room Provider

@MainActor
final class AmenFirebaseLiveRoomProvider: NSObject, AmenLiveRoomProvider, ObservableObject {

    // MARK: State

    private let db = Database.database().reference()
    private var roomRef: DatabaseReference?
    private var roomId: String?
    private var spaceId: String?
    private var currentUserId: String?

    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let sessionQueue = DispatchQueue(label: "com.amen.capture", qos: .userInitiated)

    @Published var participants: [AmenLiveRoomParticipant] = []
    @Published var isLocalAudioMuted = false
    @Published var isLocalVideoOff = false

    // MARK: AmenLiveRoomProvider conformance

    func joinRoom(roomId: String, userId: String, displayName: String, mode: AmenLiveRoomMode) async throws {
        self.roomId = roomId
        self.currentUserId = userId

        guard let spaceId = self.spaceId else { return }
        let ref = db.child("liveRooms").child(spaceId).child(roomId)
        self.roomRef = ref

        let participantData: [String: Any] = [
            "id": userId,
            "displayName": displayName,
            "isHost": false,
            "isMod": false,
            "hasRaisedHand": false,
            "isMuted": false,
            "joinedAt": ServerValue.timestamp()
        ]

        try await ref.child("participants").child(userId).setValue(participantData)
        try await ref.child("viewerCount").setValue(ServerValue.increment(1))

        observeParticipants(ref: ref)

        if mode == .video {
            setupCaptureSession(audio: true, video: true)
        } else {
            setupCaptureSession(audio: true, video: false)
        }
    }

    func leaveRoom() async {
        guard let roomRef, let userId = currentUserId else { return }
        try? await roomRef.child("participants").child(userId).removeValue()
        try? await roomRef.child("viewerCount").setValue(ServerValue.increment(-1))
        roomRef.removeAllObservers()
        stopCaptureSession()
        self.roomRef = nil
        self.roomId = nil
        self.currentUserId = nil
    }

    func muteLocalAudio(_ muted: Bool) {
        isLocalAudioMuted = muted
        sessionQueue.async { [weak self] in
            self?.captureSession?.inputs
                .compactMap { $0 as? AVCaptureDeviceInput }
                .filter { $0.device.hasMediaType(.audio) }
                .forEach { input in
                    do {
                        try input.device.lockForConfiguration()
                        // Mute by stopping the audio input rather than disabling microphone
                        self?.captureSession?.removeInput(input)
                        if !muted {
                            // Re-add the audio input when unmuting
                            if let audioDevice = AVCaptureDevice.default(for: .audio),
                               let audioInput = try? AVCaptureDeviceInput(device: audioDevice) {
                                self?.captureSession?.addInput(audioInput)
                            }
                        }
                        input.device.unlockForConfiguration()
                    } catch {
                        // Mute state written to Firebase for other participants to read
                    }
                }
        }
        guard let roomRef, let userId = currentUserId else { return }
        Task {
            try? await roomRef.child("participants").child(userId).child("isMuted").setValue(muted)
        }
    }

    func muteLocalVideo(_ muted: Bool) {
        isLocalVideoOff = muted
    }

    func muteParticipant(userId: String) async throws {
        guard let roomRef else { throw LiveRoomError.notInRoom }
        try await roomRef.child("participants").child(userId).child("isMuted").setValue(true)
        // Also issue Firebase callable to signal the server
        let _ = try await Functions.functions().httpsCallable("muteParticipant").call([
            "spaceId": spaceId ?? "",
            "roomId": roomId ?? "",
            "targetUserId": userId
        ])
    }

    var localVideoView: AnyView {
        AnyView(LocalCapturePreview(session: captureSession))
    }

    var participantVideoView: (String) -> AnyView {
        { participantId in
            AnyView(
                // Remote participant placeholder — replace with WebRTC SDK renderer
                // when Agora/Livekit SDK is added.
                ParticipantPlaceholderView(
                    participant: self.participants.first(where: { $0.id == participantId })
                )
            )
        }
    }

    // MARK: - Configuration helper

    func configure(spaceId: String) {
        self.spaceId = spaceId
    }

    // MARK: - Private

    private func observeParticipants(ref: DatabaseReference) {
        ref.child("participants").observe(.value) { [weak self] snapshot in
            guard let self else { return }
            var updated: [AmenLiveRoomParticipant] = []
            for child in snapshot.children {
                guard let snap = child as? DataSnapshot,
                      let dict = snap.value as? [String: Any] else { continue }
                let p = AmenLiveRoomParticipant(
                    id: dict["id"] as? String ?? snap.key,
                    displayName: dict["displayName"] as? String ?? "Participant",
                    isHost: dict["isHost"] as? Bool ?? false,
                    isMod: dict["isMod"] as? Bool ?? false,
                    hasRaisedHand: dict["hasRaisedHand"] as? Bool ?? false,
                    isMuted: dict["isMuted"] as? Bool ?? false,
                    joinedAt: Date(timeIntervalSince1970: (dict["joinedAt"] as? TimeInterval ?? 0) / 1000)
                )
                updated.append(p)
            }
            Task { @MainActor in self.participants = updated }
        }
    }

    private func setupCaptureSession(audio: Bool, video: Bool) {
        sessionQueue.async { [weak self] in
            let session = AVCaptureSession()
            session.beginConfiguration()
            session.sessionPreset = video ? .medium : .inputPriority

            if audio, let audioDevice = AVCaptureDevice.default(for: .audio),
               let audioInput = try? AVCaptureDeviceInput(device: audioDevice),
               session.canAddInput(audioInput) {
                session.addInput(audioInput)
            }

            if video,
               let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
               let videoInput = try? AVCaptureDeviceInput(device: videoDevice),
               session.canAddInput(videoInput) {
                session.addInput(videoInput)
            }

            let videoOutput = AVCaptureVideoDataOutput()
            if session.canAddOutput(videoOutput) {
                session.addOutput(videoOutput)
            }

            session.commitConfiguration()
            session.startRunning()
            Task { @MainActor in self?.captureSession = session }
        }
    }

    private func stopCaptureSession() {
        sessionQueue.async { [weak self] in
            self?.captureSession?.stopRunning()
            self?.captureSession = nil
        }
    }
}

// MARK: - Error

private enum LiveRoomError: LocalizedError {
    case notInRoom
    var errorDescription: String? { "Not currently in a live room." }
}

// MARK: - Local camera preview

private struct LocalCapturePreview: UIViewRepresentable {
    let session: AVCaptureSession?

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        if let session {
            view.previewLayer.session = session
            view.previewLayer.videoGravity = .resizeAspectFill
        }
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        if let session { uiView.previewLayer.session = session }
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer {
            guard let pl = layer as? AVCaptureVideoPreviewLayer else {
                fatalError("PreviewView: layer is not AVCaptureVideoPreviewLayer — layerClass override broken")
            }
            return pl
        }
    }
}

// MARK: - Remote participant placeholder (replace with WebRTC renderer)

private struct ParticipantPlaceholderView: View {
    let participant: AmenLiveRoomParticipant?

    var body: some View {
        ZStack {
            Color(red: 0.08, green: 0.08, blue: 0.10)
            if let participant {
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(Color(hex: "6E4BB5").opacity(0.35))
                            .frame(width: 64, height: 64)
                        Text(initials(from: participant.displayName))
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    Text(participant.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                    if participant.isMuted {
                        Image(systemName: "mic.slash.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.50))
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func initials(from name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first.map { String($0) } }.joined().uppercased()
    }
}
