//
//  VergeRoomCardView.swift
//  AMENAPP
//
//  Glass card summarising a single Verge room. Used in lists and horizontal scrolls.
//

import SwiftUI

struct VergeRoomCardView: View {

    let room: VergeRoom
    let onJoin: () -> Void

    private let Color.accentColor = Color(hex: "6B48FF")
    private let amenViolet = Color(hex: "C084FC")
    private let Color.accentColor   = Color(hex: "F59E0B")
    private let vergeGradient = LinearGradient(
        colors: [Color(hex: "06B6D4"), Color(hex: "6B48FF")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            leftContent
            Spacer(minLength: 8)
            joinButton
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(minHeight: 120)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Left Content

    private var leftContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Status / schedule indicator
            statusBadge

            // Title
            Text(room.title)
                .font(AMENFont.bold(15))
                .foregroundStyle(.white)
                .lineLimit(2)

            // Host placeholder
            Text("Host")
                .font(AMENFont.regular(12))
                .foregroundStyle(.white.opacity(0.45))

            // Footer chips
            HStack(spacing: 8) {
                participantChip
                typeBadge
                if room.isMonetized { monetizationBadge }
            }
        }
    }

    // MARK: - Status Badge

    @ViewBuilder
    private var statusBadge: some View {
        if room.isLive {
            HStack(spacing: 5) {
                PulsingDot(color: .red)
                Text("LIVE")
                    .font(AMENFont.bold(11))
                    .foregroundStyle(.white)
                    .tracking(1.0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.red.opacity(0.2)))
        } else if let label = room.startsInLabel {
            Text(label)
                .font(AMENFont.semiBold(11))
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.accentColor.opacity(0.15)))
        } else if room.status == .ended {
            Text("Ended")
                .font(AMENFont.semiBold(11))
                .foregroundStyle(.white.opacity(0.4))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.white.opacity(0.06)))
        }
    }

    // MARK: - Participant Chip

    private var participantChip: some View {
        HStack(spacing: 4) {
            Image(systemName: "person.2.fill")
                .font(.systemScaled(10, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white.opacity(0.5))
            Text("\(room.participantCount)")
                .font(AMENFont.regular(11))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    // MARK: - Type Badge

    private var typeBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: room.type.icon)
                .font(.systemScaled(9, weight: .medium))
                .foregroundStyle(amenViolet.opacity(0.8))
            Text(room.type.label)
                .font(AMENFont.regular(10))
                .foregroundStyle(amenViolet.opacity(0.8))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(amenViolet.opacity(0.1)))
    }

    // MARK: - Monetization Badge

    @ViewBuilder
    private var monetizationBadge: some View {
        if room.subscribersOnly {
            Text("Subscribers only")
                .font(AMENFont.regular(10))
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.accentColor.opacity(0.15)))
        } else if let price = room.ticketPrice {
            Text(String(format: "$%.0f to join", price))
                .font(AMENFont.regular(10))
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.accentColor.opacity(0.12)))
        }
    }

    // MARK: - Join Button

    @ViewBuilder
    private var joinButton: some View {
        if room.status == .ended || room.status == .archived {
            EmptyView()
        } else {
            Button(action: onJoin) {
                Text(room.isLive ? "Join" : "RSVP")
                    .font(AMENFont.bold(13))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .frame(height: 36)
                    .background(
                        Capsule()
                            .fill(room.isLive ? vergeGradient : LinearGradient(
                                colors: [Color.accentColor.opacity(0.8), Color.accentColor],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .shadow(color: Color.accentColor.opacity(room.isLive ? 0.4 : 0), radius: 10, y: 4)
                    )
            }
            .buttonStyle(CoCreationPressStyle())
        }
    }
}

// MARK: - PulsingDot

struct PulsingDot: View {
    let color: Color
    @State private var pulsing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.3))
                .frame(width: pulsing ? 14 : 8, height: pulsing ? 14 : 8)
                .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: pulsing)
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
        }
        .onAppear { pulsing = true }
    }
}
