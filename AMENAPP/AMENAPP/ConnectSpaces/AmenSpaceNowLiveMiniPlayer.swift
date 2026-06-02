// AmenSpaceNowLiveMiniPlayer.swift
// AMEN ConnectSpaces — Floating "now live" mini-player pill
//
// Design constraints:
//   - .thinMaterial Capsule floats above the tab bar
//   - Pulsing red LIVE dot respects @Environment(\.accessibilityReduceMotion)
//   - Entrance: slide-up + fade (reduce-motion: fade only)
//   - Dismiss: fade out via onDismiss callback; caller controls visibility
//   - No inner ZStack uses glass-on-glass; background is always .thinMaterial

import SwiftUI

// MARK: - Pulsing live dot

private struct NowLiveDot: View {
    let reduceMotion: Bool
    @State private var pulsing = false

    var body: some View {
        ZStack {
            if !reduceMotion {
                Circle()
                    .fill(Color.red.opacity(0.35))
                    .frame(width: 18, height: 18)
                    .scaleEffect(pulsing ? 1.55 : 1.0)
                    .opacity(pulsing ? 0 : 0.7)
            }

            Circle()
                .fill(Color.red)
                .frame(width: 9, height: 9)
        }
        .frame(width: 18, height: 18)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(
                .easeOut(duration: 1.1)
                .repeatForever(autoreverses: false)
            ) {
                pulsing = true
            }
        }
        .accessibilityLabel("Live")
        .accessibilityHidden(false)
    }
}

// MARK: - Mini player

struct AmenSpaceNowLiveMiniPlayer: View {
    let spaceName: String
    let liveTitle: String
    let participantCount: Int
    let onJoin: () -> Void
    let onDismiss: () -> Void

    @State private var isVisible = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var formattedParticipantCount: String {
        participantCount >= 1000
            ? String(format: "%.1fK", Double(participantCount) / 1000.0)
            : "\(participantCount)"
    }

    // Entrance animation values
    private var slideOffset: CGFloat {
        isVisible ? 0 : 80
    }

    private var opacity: Double {
        isVisible ? 1 : 0
    }

    var body: some View {
        HStack(spacing: 10) {
            // LIVE indicator
            NowLiveDot(reduceMotion: reduceMotion)

            // Title stack
            VStack(alignment: .leading, spacing: 2) {
                Text(spaceName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.60))
                    .lineLimit(1)

                Text(liveTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Participant count
            HStack(spacing: 3) {
                Image(systemName: "person.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.50))
                Text(formattedParticipantCount)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.50))
            }

            // Join button
            Button(action: onJoin) {
                Text("Join")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color(hex: "070607"))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background {
                        Capsule(style: .continuous)
                            .fill(Color(hex: "D9A441"))
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Join live session: \(liveTitle)")

            // Dismiss button
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .frame(width: 28, height: 28)
                    .background {
                        Circle()
                            .fill(Color.white.opacity(0.10))
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss live player")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            Capsule(style: .continuous)
                .fill(.thinMaterial)
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(Color.red.opacity(0.30), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.40), radius: 18, x: 0, y: 6)
        }
        .padding(.horizontal, 16)
        // Entrance animation
        .offset(y: reduceMotion ? 0 : slideOffset)
        .opacity(opacity)
        .onAppear {
            let animation: Animation = reduceMotion
                ? .easeInOut(duration: 0.18)
                : .spring(response: 0.42, dampingFraction: 0.76)
            withAnimation(animation) {
                isVisible = true
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Now live: \(liveTitle) in \(spaceName), \(formattedParticipantCount) participants")
    }
}

// MARK: - Preview host

#if DEBUG
private struct NowLivePreviewHost: View {
    @State private var shown = true

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(red: 0.027, green: 0.024, blue: 0.031)
                .ignoresSafeArea()

            VStack {
                Spacer()
                if shown {
                    AmenSpaceNowLiveMiniPlayer(
                        spaceName: "Elevation Church",
                        liveTitle: "Sunday Morning Worship",
                        participantCount: 3241,
                        onJoin: {},
                        onDismiss: {
                            withAnimation(.easeOut(duration: 0.22)) { shown = false }
                        }
                    )
                    .padding(.bottom, 90)
                } else {
                    Button("Show again") { shown = true }
                        .foregroundStyle(.white)
                        .padding(.bottom, 90)
                }
            }
        }
    }
}

#Preview("Now Live Mini Player") {
    NowLivePreviewHost()
        .preferredColorScheme(.dark)
}

#Preview("Reduce Motion") {
    NowLivePreviewHost()
        .preferredColorScheme(.dark)
}
#endif
