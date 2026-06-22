// MusicPreviewCardView.swift
// AMENAPP — Smart Comments Wave 3
//
// Music preview card. NEVER autoplays — opens in the platform app only.
//
// INVARIANT: No audio playback occurs anywhere in this view or its subviews.
//            The preview URL opens the platform app via URL scheme / universal link.
//
// Liquid Glass rules:
//   - Opaque white card (no glass behind music metadata text)
//   - Reduce-transparency fallback: solid systemBackground

import SwiftUI
import Foundation

struct MusicPreviewCardView: View {

    let preview: MusicPreview

    // MARK: - Guard

    var body: some View {
        guard AMENFeatureFlags.shared.commentMusicPreviewEnabled else {
            return AnyView(EmptyView())
        }
        return AnyView(cardContent)
    }

    // MARK: - Card Content

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                // Album art placeholder + platform icon overlay
                albumArtPlaceholder

                VStack(alignment: .leading, spacing: 4) {
                    // Title
                    if let title = preview.title {
                        Text(title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }

                    // Artist
                    if let artist = preview.artist {
                        Text(artist)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    // Platform label
                    Text(platformName)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 0)

                // Safety badge
                safetyBadge
            }
            .padding(14)

            Divider()
                .padding(.horizontal, 14)

            // "Open in [Platform]" button
            Button(action: openInPlatform) {
                HStack(spacing: 6) {
                    Image(systemName: platformSystemIcon)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                    Text("Open in \(platformName)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(
                    Capsule().fill(platformTintColor)
                )
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            // No-autoplay caption — always visible
            Text("Music opens in the platform app")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 10)
        }
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
    }

    // MARK: - Album Art Placeholder

    private var albumArtPlaceholder: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(uiColor: .systemGray5))
                .frame(width: 52, height: 52)
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(.secondary)
                )

            // Platform icon overlay
            Circle()
                .fill(platformTintColor)
                .frame(width: 18, height: 18)
                .overlay(
                    Image(systemName: platformSystemIcon)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                )
                .offset(x: 4, y: 4)
        }
    }

    // MARK: - Safety Badge

    @ViewBuilder
    private var safetyBadge: some View {
        switch preview.safetyVerdict {
        case .safe:
            verdictBadge(icon: "checkmark.shield.fill", color: .green)
        case .unknown, .suspicious:
            verdictBadge(icon: "exclamationmark.shield", color: .orange)
        case .phishing, .malware, .adult, .extremist:
            verdictBadge(icon: "xmark.shield.fill", color: .red)
        }
    }

    private func verdictBadge(icon: String, color: Color) -> some View {
        Image(systemName: icon)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(color)
    }

    // MARK: - Card Background

    @ViewBuilder
    private var cardBackground: some View {
        if UIAccessibility.isReduceTransparencyEnabled {
            Color(uiColor: .systemBackground)
        } else {
            Color(uiColor: .systemBackground)
        }
    }

    // MARK: - Platform Helpers

    private var platformName: String {
        switch preview.platform {
        case .appleMusic: return "Apple Music"
        case .spotify:    return "Spotify"
        case .other:      return "Music"
        }
    }

    private var platformSystemIcon: String {
        switch preview.platform {
        case .appleMusic: return "music.note"
        case .spotify:    return "music.note.list"
        case .other:      return "music.note"
        }
    }

    private var platformTintColor: Color {
        switch preview.platform {
        case .appleMusic: return Color(red: 0.99, green: 0.27, blue: 0.40) // Apple Music red
        case .spotify:    return Color(red: 0.12, green: 0.72, blue: 0.38) // Spotify green
        case .other:      return .blue
        }
    }

    // MARK: - Navigation — opens platform app; never plays audio inline

    private func openInPlatform() {
        guard let url = URL(string: preview.previewUrl) else { return }
        UIApplication.shared.open(url)
    }
}
