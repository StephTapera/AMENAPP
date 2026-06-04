// AmenLiveQAQueueView.swift
// AMEN Connect + Spaces — Live Q&A Moderation Panel
// Built: 2026-06-02

import SwiftUI
import FirebaseAnalytics

struct AmenLiveQAQueueView: View {
    let participants: [AmenLiveRoomParticipant]
    let isHost: Bool
    let onAllowToSpeak: (String) -> Void
    let onMute: (String) -> Void
    let onDismiss: () -> Void

    private var raisedHands: [AmenLiveRoomParticipant] {
        participants.filter { $0.hasRaisedHand }
    }

    private var allParticipants: [AmenLiveRoomParticipant] {
        participants.sorted { $0.isHost && !$1.isHost }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "070607").ignoresSafeArea()

                List {
                    if !raisedHands.isEmpty {
                        Section {
                            ForEach(raisedHands) { participant in
                                ParticipantRow(
                                    participant: participant,
                                    isHost: isHost,
                                    onAllowToSpeak: onAllowToSpeak,
                                    onMute: onMute
                                )
                            }
                        } header: {
                            sectionHeader("Raised Hands", count: raisedHands.count)
                        }
                    }

                    Section {
                        ForEach(allParticipants) { participant in
                            ParticipantRow(
                                participant: participant,
                                isHost: isHost,
                                onAllowToSpeak: onAllowToSpeak,
                                onMute: onMute
                            )
                        }
                    } header: {
                        sectionHeader("All Participants", count: allParticipants.count)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Q&A Queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done", action: onDismiss)
                        .foregroundStyle(Color(hex: "D9A441"))
                        .fontWeight(.semibold)
                }

                // Mute All — host only
                if isHost {
                    ToolbarItem(placement: .bottomBar) {
                        muteAllButton
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if isHost {
                    muteAllFooter
                }
            }
            .onAppear {
                Analytics.logEvent("live_qa_queue_viewed", parameters: nil)
            }
        }
    }

    // MARK: - Section Header

    @ViewBuilder
    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("\(count)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.45))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background {
                    Capsule().fill(Color.white.opacity(0.10))
                }
        }
        .textCase(nil)
    }

    // MARK: - Mute All Footer

    private var muteAllFooter: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.25)
            Button {
                let nonHosts = participants.filter { !$0.isHost }
                nonHosts.forEach { onMute($0.id) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "mic.slash.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Mute All")
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(hex: "6E4BB5").opacity(0.85))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea(edges: .bottom)
            }
            .accessibilityLabel("Mute all participants")
        }
    }

    private var muteAllButton: some View {
        EmptyView()
    }
}

// MARK: - Participant Row

private struct ParticipantRow: View {
    let participant: AmenLiveRoomParticipant
    let isHost: Bool
    let onAllowToSpeak: (String) -> Void
    let onMute: (String) -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            ZStack {
                Circle()
                    .fill(Color(hex: "245B8F").opacity(0.35))
                    .frame(width: 40, height: 40)
                Text(initials(for: participant.displayName))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }

            // Name + badges
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(participant.displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)

                    if participant.isHost {
                        badgePill("Host", color: Color(hex: "D9A441"))
                    }
                    if participant.isMod {
                        badgePill("Mod", color: Color(hex: "6E4BB5"))
                    }
                }
                if participant.isMuted {
                    HStack(spacing: 4) {
                        Image(systemName: "mic.slash.fill")
                            .font(.system(size: 9))
                        Text("Muted")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Raised hand indicator
            if participant.hasRaisedHand {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color(hex: "D9A441"))
                    .accessibilityLabel("Hand raised")
            }

            // Host/mod action buttons
            if isHost && !participant.isHost {
                HStack(spacing: 8) {
                    if participant.hasRaisedHand {
                        actionButton(
                            icon: "person.wave.2.fill",
                            tint: Color(hex: "D9A441"),
                            label: "Allow to speak"
                        ) {
                            onAllowToSpeak(participant.id)
                        }
                    }
                    actionButton(
                        icon: participant.isMuted ? "mic.fill" : "mic.slash.fill",
                        tint: participant.isMuted ? .white : Color(hex: "6E4BB5"),
                        label: participant.isMuted ? "Unmute participant" : "Mute participant"
                    ) {
                        onMute(participant.id)
                    }
                }
            }
        }
        .listRowBackground(Color.white.opacity(0.05))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rowAccessibilityLabel)
    }

    private var rowAccessibilityLabel: String {
        var parts = [participant.displayName]
        if participant.isHost { parts.append("host") }
        if participant.isMod { parts.append("moderator") }
        if participant.hasRaisedHand { parts.append("hand raised") }
        if participant.isMuted { parts.append("muted") }
        return parts.joined(separator: ", ")
    }

    @ViewBuilder
    private func badgePill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .kerning(0.3)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background {
                Capsule()
                    .fill(color.opacity(0.18))
                    .overlay { Capsule().strokeBorder(color.opacity(0.35), lineWidth: 1) }
            }
    }

    @ViewBuilder
    private func actionButton(icon: String, tint: Color, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background {
                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .overlay { Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1) }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

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
    AmenLiveQAQueueView(
        participants: [
            AmenLiveRoomParticipant(id: "u1", displayName: "Pastor James", isHost: true,
                                    isMod: false, hasRaisedHand: false, isMuted: false,
                                    joinedAt: Date()),
            AmenLiveRoomParticipant(id: "u2", displayName: "Maria Lopez", isHost: false,
                                    isMod: true, hasRaisedHand: true, isMuted: false,
                                    joinedAt: Date()),
            AmenLiveRoomParticipant(id: "u3", displayName: "David Chen", isHost: false,
                                    isMod: false, hasRaisedHand: false, isMuted: true,
                                    joinedAt: Date()),
            AmenLiveRoomParticipant(id: "u4", displayName: "Sarah Williams", isHost: false,
                                    isMod: false, hasRaisedHand: true, isMuted: false,
                                    joinedAt: Date())
        ],
        isHost: true,
        onAllowToSpeak: { _ in },
        onMute: { _ in },
        onDismiss: {}
    )
}
#endif
