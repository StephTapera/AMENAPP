// AmenAutoClipBrowserView.swift
// AMEN Connect + Spaces — Auto Clip Browser
// Built 2026-06-02

import SwiftUI

// MARK: - Duration formatter

private func formatDuration(_ secs: TimeInterval) -> String {
    let totalSeconds = Int(secs)
    let minutes = totalSeconds / 60
    let seconds = totalSeconds % 60
    return String(format: "%d:%02d", minutes, seconds)
}

// MARK: - Clip cell

private struct AmenAutoClipCell: View {
    let clip: AmenAutoClip
    let onPlay: (AmenAutoClip) -> Void
    let onShare: (AmenAutoClip) -> Void

    @State private var isPressed: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Thumbnail area — matte dark card, content rule
            ZStack(alignment: .bottomLeading) {
                thumbnailPlaceholder

                // Duration badge — glass control
                Text(formatDuration(clip.durationSecs))
                    .font(.systemScaled(10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background {
                        Capsule().fill(Color.black.opacity(0.65))
                    }
                    .padding(8)
                    .accessibilityHidden(true)

                // Play button overlay
                HStack {
                    Spacer()
                    Button {
                        onPlay(clip)
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.systemScaled(18))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background {
                                Circle().fill(Color(hex: "6E4BB5").opacity(0.85))
                                    .overlay {
                                        Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                                    }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Play \(clip.title)")
                    .padding(10)
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 110)
            .clipped()

            // Clip info
            VStack(alignment: .leading, spacing: 4) {
                Text(clip.title)
                    .font(.systemScaled(13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(formatDuration(clip.durationSecs))
                    .font(.systemScaled(11))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
        }
        .background(Color(hex: "0D0D0D"))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.09), lineWidth: 1)
        }
        .scaleEffect(isPressed ? 0.96 : 1.0)
        .animation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.7), value: isPressed)
        .onTapGesture {
            onPlay(clip)
        }
        .onLongPressGesture(minimumDuration: 0.4, pressing: { pressing in
            isPressed = pressing
        }, perform: {
            onShare(clip)
        })
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(clip.title), \(formatDuration(clip.durationSecs))")
        .accessibilityHint("Tap to play, hold to share")
    }

    private var thumbnailPlaceholder: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(hex: "6E4BB5").opacity(0.5),
                        Color(hex: "245B8F").opacity(0.35),
                        Color(hex: "070607")
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }
}

// MARK: - Main view

struct AmenAutoClipBrowserView: View {
    let clips: [AmenAutoClip]
    let onShareClip: (AmenAutoClip) -> Void
    let onPlayClip: (AmenAutoClip) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        Group {
            if clips.isEmpty {
                emptyState
            } else {
                clipGrid
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: "070607"))
    }

    // MARK: - Grid

    private var clipGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(clips) { clip in
                    AmenAutoClipCell(
                        clip: clip,
                        onPlay: onPlayClip,
                        onShare: onShareClip
                    )
                }
            }
            .padding(16)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "film.stack")
                .font(.systemScaled(44))
                .foregroundStyle(Color.white.opacity(0.2))
                .accessibilityHidden(true)
            Text("No clips yet")
                .font(.systemScaled(16, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("Clips are generated automatically after recordings are processed.")
                .font(.systemScaled(13))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No clips available. Clips are generated automatically after recordings are processed.")
    }
}

// MARK: - Preview

#Preview("With clips") {
    AmenAutoClipBrowserView(
        clips: [
            AmenAutoClip(
                id: "c1", sourceRef: "v1",
                title: "The Foundation of Faith",
                startSecs: 0, durationSecs: 47,
                thumbnailRef: nil, shareUrl: nil,
                generatedAt: Date()
            ),
            AmenAutoClip(
                id: "c2", sourceRef: "v1",
                title: "Walking in Obedience",
                startSecs: 300, durationSecs: 63,
                thumbnailRef: nil, shareUrl: nil,
                generatedAt: Date()
            ),
            AmenAutoClip(
                id: "c3", sourceRef: "v1",
                title: "Community & Accountability",
                startSecs: 720, durationSecs: 38,
                thumbnailRef: nil, shareUrl: nil,
                generatedAt: Date()
            ),
            AmenAutoClip(
                id: "c4", sourceRef: "v1",
                title: "Closing Prayer",
                startSecs: 2700, durationSecs: 120,
                thumbnailRef: nil, shareUrl: nil,
                generatedAt: Date()
            )
        ],
        onShareClip: { _ in },
        onPlayClip: { _ in }
    )
    .preferredColorScheme(.dark)
}

#Preview("Empty") {
    AmenAutoClipBrowserView(
        clips: [],
        onShareClip: { _ in },
        onPlayClip: { _ in }
    )
    .preferredColorScheme(.dark)
}
