// BereanPrayerRoomView.swift
// AMEN App — Berean realtime prayer room view
//
// Joins a live prayer room via PrayerRoomRealtimeCoordinator and shows
// live captions from BereanLiveTranscriptService.
// Gated by bereanPrayerRoomsEnabled feature flag.

import SwiftUI

struct BereanPrayerRoomView: View {
    let prayerRoomId: String

    @StateObject private var coordinator = PrayerRoomRealtimeCoordinator()
    @StateObject private var manager = BereanRealtimeSessionManager.shared
    @StateObject private var transcriptService = BereanLiveTranscriptService()
    @ObservedObject private var flags = AMENFeatureFlags.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isJoined = false
    @State private var errorMessage: String?
    @State private var pulseScale: CGFloat = 1.0

    // Show last 5 caption lines
    private var recentCaptions: [BereanCaptionChunk] {
        Array(transcriptService.captions.suffix(5))
    }

    var body: some View {
        if !flags.bereanPrayerRoomsEnabled {
            ContentUnavailableView("Prayer Rooms not available", systemImage: "ear.slash")
        } else {
            content
        }
    }

    // MARK: - Main content

    private var content: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header status card
                headerCard
                    .padding(.horizontal, 18)
                    .padding(.top, 18)
                    .padding(.bottom, 14)

                Divider().padding(.horizontal, 18)

                // Live captions
                captionsSection

                Divider()

                // Controls
                controlsBar
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
            }
            .navigationTitle("Prayer Room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Header card

    private var headerCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 52, height: 52)
                    .scaleEffect(isJoined ? pulseScale : 1)

                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.orange)
            }
            .onAppear { startPulse() }

            VStack(alignment: .leading, spacing: 3) {
                Text("Prayer Room")
                    .font(.headline)
                Text(statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Spacer()

            // Active indicator
            if isJoined {
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 7, height: 7)
                    Text("Live")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.green.opacity(0.12)))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(reduceTransparency
                      ? Color(.secondarySystemBackground)
                      : Color(.secondarySystemBackground).opacity(0.9))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.orange.opacity(0.18), lineWidth: 0.8)
                )
        )
    }

    // MARK: - Captions section

    private var captionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Live Captions", systemImage: "captions.bubble")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)

            if recentCaptions.isEmpty {
                HStack {
                    Spacer()
                    Text(isJoined ? "Listening for speech…" : "Join to see live captions")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .padding(.vertical, 28)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(recentCaptions) { chunk in
                            captionRow(chunk)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 12)
                }
                .frame(maxHeight: 200)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func captionRow(_ chunk: BereanCaptionChunk) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(chunk.isFinal ? Color.accentColor : Color.secondary)
                .frame(width: 6, height: 6)
                .padding(.top, 5)

            Text(chunk.text)
                .font(.body)
                .foregroundStyle(chunk.isFinal ? .primary : .secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .accessibilityLabel(chunk.text)
    }

    // MARK: - Controls bar

    private var controlsBar: some View {
        VStack(spacing: 10) {
            if manager.isConnecting {
                ProgressView("Joining…")
                    .font(.subheadline)
            }

            Button(action: toggleJoin) {
                Label(
                    isJoined ? "Leave Room" : "Join Room",
                    systemImage: isJoined ? "arrow.left.circle.fill" : "hand.raised.fill"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Capsule().fill(isJoined ? Color.red : Color.orange))
            }
            .buttonStyle(.plain)
            .disabled(manager.isConnecting)
            .accessibilityLabel(isJoined ? "Leave prayer room" : "Join prayer room")
        }
    }

    // MARK: - Helpers

    private var statusText: String {
        if manager.isConnecting { return "Connecting…" }
        if isJoined { return "You are in the room" }
        return "Not joined"
    }

    private func toggleJoin() {
        if isJoined {
            Task {
                if let sessionId = manager.currentSession?.id {
                    await manager.pause(sessionId: sessionId)
                }
                await coordinator.endPrayerRoom()
                transcriptService.stop()
                isJoined = false
            }
        } else {
            errorMessage = nil
            Task {
                do {
                    let secret = try await manager.createSession(
                        type: .livePrayerRoom,
                        prayerRoomId: prayerRoomId
                    )
                    transcriptService.start(sessionId: secret.sessionId, language: .english)
                    isJoined = true
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func startPulse() {
        guard !reduceMotion else { return }
        withAnimation(
            .easeInOut(duration: 1.4).repeatForever(autoreverses: true)
        ) {
            pulseScale = 1.18
        }
    }
}
