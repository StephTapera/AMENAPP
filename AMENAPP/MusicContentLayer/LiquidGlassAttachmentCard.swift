// LiquidGlassAttachmentCard.swift
// AMENAPP — MusicContentLayer
//
// Central reusable card for any ContentAttachment.
// Modes: compact / standard / expanded / profileShelf / pulseDigest
// Accessibility: Dynamic Type, Reduced Motion, Reduced Transparency, VoiceOver

import SwiftUI

// MARK: - AttachmentCardMode

enum AttachmentCardMode: Sendable {
    case compact
    case standard
    case expanded
    case profileShelf
    case pulseDigest
}

// MARK: - LiquidGlassAttachmentCard

struct LiquidGlassAttachmentCard: View {

    let attachment: ContentAttachment
    let mode: AttachmentCardMode
    var dominantColor: Color = .clear
    var onPlay: (() -> Void)?
    var onSave: (() -> Void)?
    var onShare: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        Group {
            switch mode {
            case .compact:      compactLayout
            case .standard:     standardLayout
            case .expanded:     expandedLayout
            case .profileShelf: profileShelfLayout
            case .pulseDigest:  pulseDigestLayout
            }
        }
        .background(glassBackground)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(strokeOpacity), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.08), radius: 18, x: 0, y: 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(a11yLabel)
        .accessibilityHint(a11yHint)
    }

    // MARK: Layouts

    private var compactLayout: some View {
        HStack(spacing: 10) {
            artworkView(size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if let sub = attachment.displaySubtitle {
                    Text(sub).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            typeTagPill(fontSize: 10)
            if hasPreview { playButton(size: 28) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var standardLayout: some View {
        HStack(spacing: 12) {
            artworkView(size: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(attachment.displayTitle).font(.headline).lineLimit(2)
                if let sub = attachment.displaySubtitle {
                    Text(sub).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                HStack(spacing: 6) {
                    typeTagPill(fontSize: 11)
                    rightsBadge
                    if attachment.isVerifiedClean { verifiedBadge }
                }
            }
            Spacer(minLength: 0)
            VStack(spacing: 8) {
                if hasPreview { playButton(size: 36) }
                actionButtons(iconSize: 16)
            }
        }
        .padding(14)
    }

    private var expandedLayout: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                artworkView(size: 72)
                VStack(alignment: .leading, spacing: 6) {
                    Text(attachment.displayTitle).font(.title3.weight(.bold)).lineLimit(2)
                    if let sub = attachment.displaySubtitle {
                        Text(sub).font(.subheadline).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 6) {
                        typeTagPill(fontSize: 12)
                        rightsBadge
                        if attachment.isVerifiedClean { verifiedBadge }
                    }
                }
                Spacer(minLength: 0)
            }
            if hasPreview {
                Button { onPlay?() } label: {
                    Label("Play Preview", systemImage: "play.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 16) {
                if let save = onSave {
                    Button { save() } label: {
                        Label("Save", systemImage: "bookmark").font(.subheadline)
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                }
                if let share = onShare {
                    Button { share() } label: {
                        Label("Share", systemImage: "square.and.arrow.up").font(.subheadline)
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(16)
    }

    private var profileShelfLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            artworkView(size: 80).frame(maxWidth: .infinity)
            Text(attachment.displayTitle)
                .font(.caption.weight(.semibold))
                .lineLimit(2)
            HStack(spacing: 4) {
                typeTagPill(fontSize: 10)
                if attachment.isVerifiedClean { verifiedBadge }
            }
        }
        .padding(10)
        .frame(width: 110)
    }

    private var pulseDigestLayout: some View {
        HStack(spacing: 12) {
            artworkView(size: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text(attachment.displayTitle)
                    .font(.subheadline.weight(.semibold)).lineLimit(1)
                if let sub = attachment.displaySubtitle {
                    Text(sub).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                typeTagPill(fontSize: 10)
            }
            Spacer(minLength: 0)
            if hasPreview { playButton(size: 32) }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: Sub-views

    @ViewBuilder
    private func artworkView(size: CGFloat) -> some View {
        Group {
            if let url = attachment.displayArtworkURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().aspectRatio(contentMode: .fill)
                    default:
                        fallbackArtwork(size: size)
                    }
                }
            } else {
                fallbackArtwork(size: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous))
    }

    @ViewBuilder
    private func fallbackArtwork(size: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
            .fill(Color.secondary.opacity(0.15))
            .overlay {
                Image(systemName: fallbackIcon)
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.22)
                    .foregroundStyle(.secondary)
            }
    }

    @ViewBuilder
    private func typeTagPill(fontSize: CGFloat) -> some View {
        Text(typeTagLabel)
            .font(.system(size: fontSize, weight: .medium))
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(Color.accentColor.opacity(0.15))
            .foregroundStyle(Color.accentColor)
            .clipShape(Capsule())
    }

    @ViewBuilder
    private var rightsBadge: some View {
        let cfg = rightsBadgeConfig
        Text(cfg.label)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(cfg.color.opacity(0.15))
            .foregroundStyle(cfg.color)
            .clipShape(Capsule())
    }

    @ViewBuilder
    private var verifiedBadge: some View {
        Image(systemName: "checkmark.seal.fill")
            .font(.system(size: 12))
            .foregroundStyle(.green)
            .accessibilityLabel("Verified clean")
    }

    @ViewBuilder
    private func playButton(size: CGFloat) -> some View {
        Button { onPlay?() } label: {
            Image(systemName: "play.fill")
                .resizable().scaledToFit()
                .padding(size * 0.25)
                .frame(width: size, height: size)
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Play preview")
    }

    @ViewBuilder
    private func actionButtons(iconSize: CGFloat) -> some View {
        HStack(spacing: 12) {
            if let save = onSave {
                Button { save() } label: {
                    Image(systemName: "bookmark").font(.system(size: iconSize)).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain).accessibilityLabel("Save")
            }
            if let share = onShare {
                Button { share() } label: {
                    Image(systemName: "square.and.arrow.up").font(.system(size: iconSize)).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain).accessibilityLabel("Share")
            }
        }
    }

    // MARK: Glass background

    @ViewBuilder
    private var glassBackground: some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(.systemBackground))
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(dominantColor.opacity(0.08))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.white.opacity(0.10))
                }
        }
    }

    // MARK: Helpers

    private var cornerRadius: CGFloat {
        switch mode {
        case .compact: return 12
        case .standard: return 16
        case .expanded: return 20
        case .profileShelf, .pulseDigest: return 14
        }
    }

    private var strokeOpacity: Double { colorSchemeContrast == .increased ? 0.35 : 0.18 }
    private var hasPreview: Bool {
        attachment.musicResource?.previewURL != nil || attachment.sermonResource?.audioURL != nil
    }

    private var typeTagLabel: String {
        switch attachment.type {
        case .song: return "Song"
        case .album: return "Album"
        case .playlist: return "Playlist"
        case .sermonClip: return "Sermon"
        case .worshipSet: return "Worship"
        case .choirRecording: return "Choir"
        case .artistProfile: return "Artist"
        case .churchProfile: return "Church"
        case .orgProfile: return "Ministry"
        case .devotionalAudio: return "Devotional"
        case .podcastEpisode: return "Podcast"
        case .eventPlaylist: return "Event"
        }
    }

    private var fallbackIcon: String {
        switch attachment.type {
        case .song, .album, .playlist, .worshipSet, .choirRecording, .eventPlaylist:
            return "music.note"
        case .sermonClip: return "mic.fill"
        case .artistProfile: return "person.fill"
        case .churchProfile, .orgProfile: return "building.columns.fill"
        case .devotionalAudio: return "book.fill"
        case .podcastEpisode: return "antenna.radiowaves.left.and.right"
        }
    }

    private var rightsBadgeConfig: (label: String, color: Color) {
        switch attachment.rightsPolicy {
        case .free: return ("Free", .green)
        case .paid: return ("Paid", .orange)
        case .memberOnly: return ("Members", .blue)
        case .donationSupported: return ("Donation", .purple)
        case .licensed: return ("Licensed", .gray)
        case .streamOnly: return ("Stream", .cyan)
        case .downloadable: return ("Download", .teal)
        case .private: return ("Private", .red)
        case .unlisted: return ("Unlisted", .gray)
        case .restricted: return ("Restricted", .red)
        case .pendingReview: return ("Pending", .yellow)
        }
    }

    private var a11yLabel: String {
        var parts = [typeTagLabel, attachment.displayTitle]
        if let sub = attachment.displaySubtitle { parts.append(sub) }
        if attachment.isVerifiedClean { parts.append("verified clean") }
        parts.append(rightsBadgeConfig.label)
        return parts.joined(separator: ", ")
    }

    private var a11yHint: String { hasPreview ? "Double-tap to play preview" : "Double-tap to view details" }
}

// MARK: - Preview

#Preview {
    let music = MusicResource(
        id: "p1", title: "Way Maker", artistName: "Sinach", albumName: nil,
        artworkURL: nil, previewURL: URL(string: "https://example.com/p.mp3"),
        durationSeconds: 242, isVerifiedClean: true, rightsPolicy: .free,
        visibility: .public, moderationStatus: .approved, createdAt: "2026-06-10T00:00:00Z"
    )
    let att = ContentAttachment(
        id: "a1", type: .song, musicResource: music, sermonResource: nil,
        profileID: nil, externalURL: nil, displayTitle: "Way Maker",
        displaySubtitle: "Sinach", displayArtworkURL: nil,
        rightsPolicy: .free, visibility: .public, isVerifiedClean: true,
        createdAt: "2026-06-10T00:00:00Z"
    )
    ScrollView {
        VStack(spacing: 16) {
            LiquidGlassAttachmentCard(attachment: att, mode: .compact, onPlay: {}, onSave: {}, onShare: {})
            LiquidGlassAttachmentCard(attachment: att, mode: .standard, onPlay: {}, onSave: {}, onShare: {})
            LiquidGlassAttachmentCard(attachment: att, mode: .expanded, onPlay: {}, onSave: {}, onShare: {})
        }
        .padding()
    }
}
