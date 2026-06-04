// AmenLiveRoomGreenRoomView.swift
// AMEN Connect + Spaces — Pre-Show Green Room (Host)
// Built: 2026-06-02

import SwiftUI
import FirebaseAnalytics

struct AmenLiveRoomGreenRoomView: View {
    let room: AmenLiveRoom
    let currentUserId: String
    let onGoLive: () -> Void
    let onCancel: () -> Void

    /// Optional: pass in provider.localVideoView when the provider is available to this view.
    var localVideoView: AnyView? = nil

    @State private var showGoLiveConfirm = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isHost: Bool { room.hostUserId == currentUserId }

    var body: some View {
        ZStack {
            Color(hex: "070607").ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                ScrollView {
                    VStack(spacing: 20) {
                        cameraPreviewCard
                        techChecksRow
                        participantsCard
                        Spacer(minLength: 100)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                }

                if isHost {
                    goLiveFooter
                }
            }
        }
        .confirmationDialog(
            "Go live now?",
            isPresented: $showGoLiveConfirm,
            titleVisibility: .visible
        ) {
            Button("Go Live", role: .destructive) { onGoLive() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will start the live room for all invited participants.")
        }
        .onAppear {
            Analytics.logEvent("live_room_green_room_viewed", parameters: nil)
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button(action: onCancel) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Cancel")
                        .font(.system(size: 15, weight: .medium))
                }
                .foregroundStyle(Color(hex: "D9A441"))
            }
            .accessibilityLabel("Cancel and leave green room")

            Spacer()

            VStack(spacing: 2) {
                Text("Green Room")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                Text("Pre-show")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Balance the layout
            HStack(spacing: 6) {
                Image(systemName: "chevron.left")
                Text("Cancel")
            }
            .opacity(0)
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(alignment: .bottom) {
                    Divider().opacity(0.3)
                }
        }
    }

    // MARK: - Camera Preview Card

    private var cameraPreviewCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black)
                .frame(height: 200)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                }

            if let videoView = localVideoView {
                videoView
                    .scaledToFill()
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "video.fill")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(Color(hex: "D9A441").opacity(0.5))
                    Text("Camera Preview")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityLabel("Camera preview")
    }

    // MARK: - Tech Checks Row

    private var techChecksRow: some View {
        HStack(spacing: 12) {
            techCheckPill(
                icon: "mic.fill",
                label: "Microphone",
                statusColor: Color(hex: "D9A441")
            )
            techCheckPill(
                icon: "video.fill",
                label: "Camera",
                statusColor: room.mode == .audioOnly
                    ? Color.white.opacity(0.35)
                    : Color(hex: "D9A441")
            )
            techCheckPill(
                icon: "wifi",
                label: "Network",
                statusColor: Color(hex: "D9A441")
            )
        }
    }

    @ViewBuilder
    private func techCheckPill(icon: String, label: String, statusColor: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(statusColor)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) check")
    }

    // MARK: - Participants Card

    private var participantsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("In Green Room")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 16)

            if room.participants.isEmpty {
                Text("Waiting for participants…")
                    .font(.system(size: 14))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(room.participants) { participant in
                            participantChip(participant)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Participants in green room, \(room.participants.count) present")
    }

    @ViewBuilder
    private func participantChip(_ participant: AmenLiveRoomParticipant) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(Color(hex: "6E4BB5").opacity(0.35))
                    .frame(width: 44, height: 44)
                Text(initials(for: participant.displayName))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            }
            .overlay(alignment: .bottomTrailing) {
                if participant.isHost {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Color(hex: "D9A441"))
                        .offset(x: 2, y: 2)
                }
            }

            Text(participant.displayName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)
        }
        .frame(width: 60)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(participant.displayName)\(participant.isHost ? ", host" : "")")
    }

    // MARK: - Go Live Footer

    private var goLiveFooter: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.25)
            Button {
                showGoLiveConfirm = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 16, weight: .bold))
                    Text("Go Live")
                        .font(.system(size: 17, weight: .bold))
                }
                .foregroundStyle(Color(hex: "070607"))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(hex: "D9A441"))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .accessibilityLabel("Go live — starts the room for all participants")
        }
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    // MARK: - Helpers

    private func initials(for name: String) -> String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return String((parts[0].first ?? "?")) + String((parts[1].first ?? "?"))
        }
        return String(name.prefix(2)).uppercased()
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    AmenLiveRoomGreenRoomView(
        room: AmenLiveRoom(
            id: "r1",
            spaceId: "s1",
            eventId: nil,
            hostUserId: "u1",
            mode: .video,
            state: .greenRoom,
            participants: [
                AmenLiveRoomParticipant(id: "u1", displayName: "Pastor James", isHost: true,
                                        isMod: false, hasRaisedHand: false, isMuted: false,
                                        joinedAt: Date()),
                AmenLiveRoomParticipant(id: "u2", displayName: "Maria Lopez", isHost: false,
                                        isMod: true, hasRaisedHand: false, isMuted: false,
                                        joinedAt: Date())
            ],
            captionsEnabled: false,
            translationLocale: nil,
            recordingRef: nil,
            chapterMarkers: [],
            viewerCount: 0,
            startedAt: nil,
            endedAt: nil,
            createdAt: Date()
        ),
        currentUserId: "u1",
        onGoLive: {},
        onCancel: {}
    )
}
#endif
