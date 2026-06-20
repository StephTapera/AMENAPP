// TeachingCard.swift
// AMEN — Creator Profiles (ministry hubs) — Wave 3
//
// One CreatorHubTeaching: title, series, speakers, topic chips, and duration. The
// thumbnail renders ONLY when the media is servable (moderation == .approved); the
// client never renders unapproved media, so an approved-less teaching shows a brand
// gradient instead. Tapping the card invokes onPlay.
//
// Conventions: black primary text; ONE glass card (flat children — no glass-on-glass);
// MEDIA-GATE enforced via media.isServable; AmenTheme.Colors.* + Color(hex:) tokens;
// Dynamic Type; VoiceOver — the whole card is one combined, tappable element.

import SwiftUI

struct TeachingCard: View {
    let teaching: CreatorHubTeaching
    var onPlay: (CreatorHubTeaching) -> Void = { _ in }

    var body: some View {
        Button {
            onPlay(teaching)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                thumbnail
                textBlock
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .amenGlassCard(cornerRadius: 18)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityHint("Plays this teaching")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Thumbnail (MEDIA-GATE enforced)

    /// The renderable media (video preferred, then audio) — only if approved.
    private var servableMedia: CreatorHubMediaRef? {
        if let video = teaching.video, video.isServable { return video }
        if let audio = teaching.audio, audio.isServable { return audio }
        return nil
    }

    @ViewBuilder
    private var thumbnail: some View {
        ZStack(alignment: .bottomTrailing) {
            if let media = servableMedia,
               media.kind == .image || media.kind == .video,
               let url = URL(string: media.storagePath) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        brandGradient
                    case .empty:
                        brandGradient.overlay { ProgressView().tint(.white) }
                    @unknown default:
                        brandGradient
                    }
                }
            } else {
                brandGradient.overlay {
                    Image(systemName: "play.circle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.white.opacity(0.85))
                }
            }

            durationBadge
                .padding(8)
        }
        .frame(height: 150)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityHidden(true)
    }

    private var brandGradient: some View {
        LinearGradient(
            colors: [
                Color(hex: "1B1B1F"),
                Color(hex: "2A2730"),
                AmenTheme.Colors.amenGold.opacity(0.30),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    @ViewBuilder
    private var durationBadge: some View {
        if teaching.durationSec > 0 {
            Text(durationLabel)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.black.opacity(0.55)))
        }
    }

    private var durationLabel: String {
        let total = Int(teaching.durationSec.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    // MARK: - Text block

    private var textBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(teaching.title)
                .font(.headline)
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if let series = teaching.series, !series.isEmpty {
                Text(series)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AmenTheme.Colors.amenGoldText)
                    .lineLimit(1)
            }

            if !teaching.speakers.isEmpty {
                Text(teaching.speakers.joined(separator: ", "))
                    .font(.subheadline)
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .lineLimit(1)
            }

            if !teaching.topics.isEmpty {
                topicChips
            }
        }
    }

    private var topicChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(teaching.topics.prefix(4), id: \.self) { topic in
                    Text(topic)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(AmenTheme.Colors.surfaceChip))
                }
            }
        }
        .padding(.top, 2)
    }

    // MARK: - Accessibility

    private var accessibilitySummary: String {
        var parts: [String] = [teaching.title]
        if let series = teaching.series, !series.isEmpty { parts.append("Series: \(series)") }
        if !teaching.speakers.isEmpty { parts.append("By \(teaching.speakers.joined(separator: ", "))") }
        if teaching.durationSec > 0 { parts.append("Duration \(durationLabel)") }
        return parts.joined(separator: ". ")
    }
}
