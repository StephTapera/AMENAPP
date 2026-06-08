// MUSIC FEATURE — Agent B
// MusicRowView.swift
// AMENAPP
//
// Single track row for the music browse sheet. Tapping the main body selects
// the track; tapping the circular play button previews it without selecting.

import SwiftUI

struct MusicRowView: View {
    let track: MusicAttachment
    let isCurrentlyPlaying: Bool
    let onSelect: () -> Void
    let onPreview: () -> Void

    @State private var isPressed = false

    var body: some View {
        HStack(spacing: 12) {
            // Album art
            albumArt

            // Title + artist
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.headline)
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .lineLimit(1)

                Text(track.artists.joined(separator: ", "))
                    .font(.subheadline)
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Duration + preview button
            HStack(spacing: 8) {
                Text(formatDuration(track.durationMs))
                    .font(.caption)
                    .foregroundStyle(AmenTheme.Colors.textTertiary)

                previewButton
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .animation(Motion.adaptive(Motion.springPress), value: isPressed)
        .onTapGesture {
            onSelect()
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(Motion.springPress) { isPressed = true }
                }
                .onEnded { _ in
                    withAnimation(Motion.springRelease) { isPressed = false }
                }
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(track.title) by \(track.artists.joined(separator: ", ")), \(formatDuration(track.durationMs))")
        .accessibilityHint("Double tap to attach. Use the play button to preview.")
    }

    // MARK: - Subviews

    private var albumArt: some View {
        Group {
            if let url = track.albumArtURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure, .empty:
                        artFallback
                    @unknown default:
                        artFallback
                    }
                }
            } else {
                artFallback
            }
        }
        .frame(width: 48, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var artFallback: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(AmenTheme.Colors.glassStroke, lineWidth: 0.5)
                )
            Image(systemName: "music.note")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
        }
        .frame(width: 48, height: 48)
    }

    private var previewButton: some View {
        Button {
            onPreview()
        } label: {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Circle()
                            .strokeBorder(AmenTheme.Colors.glassStroke, lineWidth: 0.5)
                    )
                Image(systemName: isCurrentlyPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .reactionPop(isActive: isCurrentlyPlaying)
            }
            .frame(width: 32, height: 32)
            // Ensure 44pt minimum tap target around the 32pt circle
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isCurrentlyPlaying ? "Pause preview" : "Play preview")
    }

    // MARK: - Helpers

    private func formatDuration(_ ms: Int) -> String {
        let totalSec = ms / 1000
        return String(format: "%d:%02d", totalSec / 60, totalSec % 60)
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    VStack(spacing: 0) {
        MusicRowView(
            track: .sample,
            isCurrentlyPlaying: false,
            onSelect: {},
            onPreview: {}
        )
        Divider().padding(.leading, 76)
        MusicRowView(
            track: .sample,
            isCurrentlyPlaying: true,
            onSelect: {},
            onPreview: {}
        )
    }
    .background(AmenTheme.Colors.backgroundPrimary)
}
#endif
