// AmenLiveRoomShellView.swift
// AMEN Connect + Spaces — Fullscreen Live Room Shell
// Built: 2026-06-02

import SwiftUI
import FirebaseAnalytics
import FirebaseFunctions

// MARK: - Shell View

struct AmenLiveRoomShellView: View {
    let room: AmenLiveRoom
    let currentUserId: String
    let provider: any AmenLiveRoomProvider
    let onEnd: () -> Void

    @StateObject private var entitlements = AmenAccountEntitlementService.shared
    @State private var showPaywall = false
    @State private var isMicMuted = false
    @State private var isCameraOff = false
    @State private var showQAQueue = false
    @State private var showEndConfirm = false
    @State private var captions: [AmenCaptionLine] = []
    @State private var showCatchMeUp = false
    @State private var showAskStream = false
    @State private var joinedLateMinutes: Int = 0
    @State private var handRaised: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let functions = Functions.functions()

    private var isHost: Bool { room.hostUserId == currentUserId }

    var body: some View {
        ZStack {
            Color(hex: "070607").ignoresSafeArea()

            if room.state == .greenRoom {
                AmenLiveRoomGreenRoomView(
                    room: room,
                    currentUserId: currentUserId,
                    onGoLive: { /* Host triggers via green room */ },
                    onCancel: onEnd
                )
            } else {
                mainLiveContent
            }

            // Host AI assistant — renders EmptyView when isHost == false
            AmenAIHostAssistantPanel(streamId: room.id, isHost: isHost)
        }
        .onAppear {
            // Gate: hosts must have a live-eligible tier
            if isHost && !entitlements.currentTier.canGoLive {
                showPaywall = true
                return
            }
            Analytics.logEvent("live_room_viewed", parameters: [
                "room_id": room.id,
                "mode": room.mode == .video ? "video" : "audio"
            ])
            Task {
                try? await provider.joinRoom(
                    roomId: room.id,
                    userId: currentUserId,
                    displayName: room.participants.first(where: { $0.id == currentUserId })?.displayName ?? "",
                    mode: room.mode
                )
                try? await functions.httpsCallable(AmenSpacesPhase1Callable.joinLiveRoom.rawValue)
                    .call(["roomId": room.id, "userId": currentUserId])
            }
            // Calculate join latency for catch-me-up
            if let startedAt = room.startedAt {
                let elapsed = Int(Date().timeIntervalSince(startedAt) / 60)
                if elapsed > 2 {
                    joinedLateMinutes = elapsed
                    showCatchMeUp = true
                }
            }
        }
        .onDisappear {
            Task { await provider.leaveRoom() }
        }
        .sheet(isPresented: $showQAQueue) {
            AmenLiveQAQueueView(
                participants: room.participants,
                isHost: isHost,
                onAllowToSpeak: { _ in },
                onMute: { userId in
                    Task { try? await provider.muteParticipant(userId: userId) }
                },
                onDismiss: { showQAQueue = false }
            )
        }
        .sheet(isPresented: $showCatchMeUp) {
            AmenCatchMeUpSheet(
                streamId: room.id,
                streamTitle: room.participants.first(where: { $0.id == room.hostUserId })?.displayName ?? "Live Room",
                minutesElapsed: joinedLateMinutes,
                onDismiss: { showCatchMeUp = false }
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showAskStream) {
            AmenAskTheStreamView(streamId: room.id, streamTitle: "Stream Recap")
        }
        .sheet(isPresented: $showPaywall) {
            AmenAccountPaywallView(
                requiredTier: .creatorPro,
                feature: "Live Streaming"
            ) {
                showPaywall = false
                onEnd()
            }
        }
        .confirmationDialog(
            isHost ? "End the live room for everyone?" : "Leave the live room?",
            isPresented: $showEndConfirm,
            titleVisibility: .visible
        ) {
            Button(isHost ? "End for Everyone" : "Leave", role: .destructive) {
                Task { await handleEndOrLeave() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Main Live Layout

    private var mainLiveContent: some View {
        ZStack(alignment: .bottom) {
            // Video content area — matte, fills screen
            videoArea
                .ignoresSafeArea()

            // Live captions overlay — directly above controls bar
            if room.captionsEnabled && !captions.isEmpty {
                AmenLiveCaptionsOverlay(captions: captions)
                    .padding(.bottom, 100)
            }

            // Floating glass controls bar
            controlsBar
                .padding(.horizontal, 20)
                .padding(.bottom, 36)

            // LIVE pill — top right
            VStack {
                HStack {
                    Spacer()
                    livePill
                        .padding(.top, 56)
                        .padding(.trailing, 20)
                }
                Spacer()
            }
        }
    }

    // MARK: - Video Area

    private var videoArea: some View {
        ZStack {
            Color(hex: "070607")
            if room.mode == .video {
                provider.localVideoView
                    .scaledToFill()
                    .clipped()
            } else {
                // Audio-only placeholder
                VStack(spacing: 16) {
                    Image(systemName: "waveform")
                        .font(.systemScaled(52, weight: .ultraLight))
                        .foregroundStyle(Color(hex: "D9A441").opacity(0.6))
                    Text("Audio Only")
                        .font(.systemScaled(15, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - LIVE Pill

    private var livePill: some View {
        HStack(spacing: 6) {
            liveDot
            Text("LIVE")
                .font(.systemScaled(11, weight: .bold))
                .kerning(0.8)
            Text("•")
                .font(.systemScaled(8))
                .foregroundStyle(.white.opacity(0.5))
            Text("\(room.viewerCount)")
                .font(.systemScaled(11, weight: .semibold).monospacedDigit())
            Image(systemName: "eye.fill")
                .font(.systemScaled(9))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background {
            Capsule()
                .fill(.thinMaterial)
                .overlay {
                    Capsule().strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Live, \(room.viewerCount) viewers")
    }

    @ViewBuilder
    private var liveDot: some View {
        if reduceMotion {
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
        } else {
            LiveRoomPulsingDot()
        }
    }

    // MARK: - Controls Bar

    private var controlsBar: some View {
        HStack(spacing: 0) {
            // Mic
            controlButton(
                icon: isMicMuted ? "mic.slash.fill" : "mic.fill",
                tint: isMicMuted ? Color(hex: "6E4BB5") : .white,
                label: isMicMuted ? "Unmute microphone" : "Mute microphone"
            ) {
                isMicMuted.toggle()
                provider.muteLocalAudio(isMicMuted)
            }

            Spacer()

            // Camera (hidden when audio-only)
            if room.mode == .video {
                controlButton(
                    icon: isCameraOff ? "video.slash.fill" : "video.fill",
                    tint: isCameraOff ? Color(hex: "6E4BB5") : .white,
                    label: isCameraOff ? "Turn camera on" : "Turn camera off"
                ) {
                    isCameraOff.toggle()
                    provider.muteLocalVideo(isCameraOff)
                }
                Spacer()
            }

            // Raise hand
            controlButton(
                icon: handRaised ? "hand.raised.fill" : "hand.raised",
                tint: handRaised ? Color(hex: "D9A441") : .white,
                label: handRaised ? "Lower hand" : "Raise hand"
            ) {
                handRaised.toggle()
                // Call raiseHand CF to broadcast state to host
                Task {
                    let functions = Functions.functions()
                    try? await functions.httpsCallable("raiseHandInLiveRoom").call([
                        "roomId": room.id,
                        "userId": currentUserId,
                        "raised": handRaised
                    ])
                }
            }

            Spacer()

            // Q&A queue
            controlButton(
                icon: "questionmark.bubble.fill",
                tint: Color(hex: "245B8F"),
                label: "Open Q&A queue"
            ) {
                showQAQueue = true
            }

            Spacer()

            // Ask the stream
            Button {
                showAskStream = true
            } label: {
                Image(systemName: "magnifyingglass.circle.fill")
                    .font(.systemScaled(22))
                    .foregroundStyle(Color.white.opacity(0.85))
            }
            .accessibilityLabel("Ask AI about this stream")

            Spacer()

            // End / Leave
            Button {
                showEndConfirm = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: isHost ? "xmark.circle.fill" : "arrow.right.circle.fill")
                        .font(.systemScaled(14, weight: .semibold))
                    Text(isHost ? "End" : "Leave")
                        .font(.systemScaled(13, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background {
                    Capsule()
                        .fill(isHost ? Color.red.opacity(0.85) : Color.white.opacity(0.14))
                        .overlay {
                            Capsule().strokeBorder(
                                isHost ? Color.red.opacity(0.5) : Color.white.opacity(0.25),
                                lineWidth: 1
                            )
                        }
                }
            }
            .accessibilityLabel(isHost ? "End live room" : "Leave live room")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background {
            Capsule()
                .fill(.thinMaterial)
                .overlay {
                    Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                }
        }
        .shadow(color: .black.opacity(0.4), radius: 18, x: 0, y: 6)
    }

    @ViewBuilder
    private func controlButton(icon: String, tint: Color, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.systemScaled(18, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background {
                    Circle()
                        .fill(Color.white.opacity(0.10))
                        .overlay { Circle().strokeBorder(Color.white.opacity(0.15), lineWidth: 1) }
                }
        }
        .accessibilityLabel(label)
    }

    // MARK: - End / Leave

    private func handleEndOrLeave() async {
        await provider.leaveRoom()
        if isHost {
            try? await functions.httpsCallable(AmenSpacesPhase1Callable.endLiveRoom.rawValue)
                .call(["roomId": room.id])
        }
        onEnd()
    }
}

// MARK: - Pulsing Dot (reduce-motion already guarded at call site)

private struct LiveRoomPulsingDot: View {
    @State private var scale: CGFloat = 1.0

    var body: some View {
        Circle()
            .fill(Color.red)
            .frame(width: 8, height: 8)
            .scaleEffect(scale)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                ) { scale = 1.45 }
            }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    let room = AmenLiveRoom(
        id: "r1",
        spaceId: "s1",
        eventId: nil,
        hostUserId: "u1",
        mode: .video,
        state: .live,
        participants: [
            AmenLiveRoomParticipant(id: "u1", displayName: "Pastor James", isHost: true,
                                    isMod: false, hasRaisedHand: false, isMuted: false,
                                    joinedAt: Date())
        ],
        captionsEnabled: false,
        translationLocale: nil,
        recordingRef: nil,
        chapterMarkers: [],
        viewerCount: 142,
        startedAt: Date(),
        endedAt: nil,
        createdAt: Date()
    )
    AmenLiveRoomShellView(
        room: room,
        currentUserId: "u1",
        provider: AmenLiveRoomStubProvider(),
        onEnd: {}
    )
}
#endif
