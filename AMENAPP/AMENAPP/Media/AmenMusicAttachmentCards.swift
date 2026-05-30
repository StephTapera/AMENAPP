// AmenMusicAttachmentCards.swift
// AMENAPP
//
// Music attachment card components for the AMEN post composer.
// Supports compact (IMG_2244), expanded/karaoke (IMG_2240, IMG_2241), and vinyl (IMG_2242) modes.
// All animations respect @Environment(\.accessibilityReduceMotion).
// Color tokens from AmenTheme — amenGold for karaoke highlight, never a generic accent.

import SwiftUI

// MARK: - AmenMusicCardContainer

/// Smart container that owns mode state and routes to the correct card variant.
/// - Tap compact → expanded
/// - Long press expanded → vinyl
/// - Chevron or X collapses back
struct AmenMusicCardContainer: View {
    let attachment: AmenMediaAttachment

    @State private var currentMode: AmenMusicCardMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(attachment: AmenMediaAttachment) {
        self.attachment = attachment
        _currentMode = State(initialValue: attachment.musicDetails?.displayMode ?? .compact)
    }

    var body: some View {
        Group {
            switch currentMode {
            case .compact:
                AmenMusicCardCompact(attachment: attachment) {
                    switchMode(to: .expanded)
                }
            case .expanded:
                AmenMusicCardExpanded(
                    attachment: attachment,
                    onCollapse: { switchMode(to: .compact) }
                )
                .onLongPressGesture(minimumDuration: 0.5) {
                    switchMode(to: .vinyl)
                }
            case .vinyl:
                AmenVinylMusicCard(
                    attachment: attachment,
                    onCollapse: { switchMode(to: .compact) }
                )
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.82), value: currentMode)
    }

    private func switchMode(to mode: AmenMusicCardMode) {
        currentMode = mode
    }
}

// MARK: - AmenMusicCardCompact

/// Horizontal compact card (~72pt tall). Matches IMG_2244.
/// Left: 52×52 album art · Center: title + subtitle · Right: glass play/pause button.
struct AmenMusicCardCompact: View {
    let attachment: AmenMediaAttachment
    let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                albumArtView(size: 52, cornerRadius: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(attachment.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                        .lineLimit(1)

                    Text(subtitleText)
                        .font(.caption)
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                AmenMusicPlayPauseButton(attachment: attachment, size: 36)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AmenTheme.Colors.surfaceCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(AmenTheme.Colors.separator, lineWidth: 1)
                    )
            )
            .shadow(color: AmenTheme.Colors.shadowCard, radius: 8, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Music: \(attachment.title). Tap to expand.")
    }

    private var subtitleText: String {
        if let details = attachment.musicDetails {
            let artists = details.artists.joined(separator: ", ")
            if let playable = attachment.playable {
                let duration = playable.durationMs ?? 0
                let mins = duration / 60_000
                let secs = (duration % 60_000) / 1_000
                return "\(artists) · \(mins):\(String(format: "%02d", secs))"
            }
            return artists
        }
        return attachment.subtitle ?? ""
    }

    private func albumArtView(size: CGFloat, cornerRadius: CGFloat) -> some View {
        Group {
            if let urlStr = attachment.musicDetails?.albumArtURL ?? attachment.thumbnailURL,
               let url = URL(string: urlStr) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        fallbackArt
                    }
                }
            } else {
                fallbackArt
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var fallbackArt: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [AmenTheme.Colors.amenGold.opacity(0.6), AmenTheme.Colors.amenPurple.opacity(0.5)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                Image(systemName: "music.note")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.9))
            )
    }
}

// MARK: - AmenMusicCardExpanded

/// Full-width card with lyrics karaoke. Matches IMG_2240, IMG_2241.
struct AmenMusicCardExpanded: View {
    let attachment: AmenMediaAttachment
    let onCollapse: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            headerRow
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 10)

            if attachment.timeline != nil {
                lyricsSection
            } else {
                noLyricsPlaceholder
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AmenTheme.Colors.surfaceCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(AmenTheme.Colors.separator, lineWidth: 1)
                )
        )
        .shadow(color: AmenTheme.Colors.shadowCard, radius: 12, x: 0, y: 3)
    }

    private var headerRow: some View {
        HStack(spacing: 12) {
            compactAlbumArt

            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .lineLimit(1)

                if let details = attachment.musicDetails {
                    Text(details.artists.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            AmenMusicPlayPauseButton(attachment: attachment, size: 36)

            collapseButton
        }
    }

    private var compactAlbumArt: some View {
        Group {
            if let urlStr = attachment.musicDetails?.albumArtURL ?? attachment.thumbnailURL,
               let url = URL(string: urlStr) {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        fallbackArt
                    }
                }
            } else {
                fallbackArt
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var fallbackArt: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [AmenTheme.Colors.amenGold.opacity(0.6), AmenTheme.Colors.amenPurple.opacity(0.5)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                Image(systemName: "music.note")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.9))
            )
    }

    private var collapseButton: some View {
        Button(action: onCollapse) {
            Image(systemName: "chevron.down")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .frame(width: 30, height: 30)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Collapse music card")
    }

    private var lyricsSection: some View {
        AmenKaraokeLyricsView(attachment: attachment)
            .frame(height: 180)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.80),
                        .init(color: .clear, location: 1.0),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .padding(.bottom, 4)
    }

    private var noLyricsPlaceholder: some View {
        Text("No lyrics available")
            .font(.caption)
            .foregroundStyle(AmenTheme.Colors.textTertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
    }
}

// MARK: - AmenKaraokeLyricsView

/// Karaoke-style scrolling lyrics. amenGold highlight on the active line.
/// Word-level wipe when timeline.isWordSynced. Respects reduceMotion throughout.
struct AmenKaraokeLyricsView: View {
    let attachment: AmenMediaAttachment

    @ObservedObject private var coordinator: AmenMediaPlaybackCoordinator = .shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var engine: AmenLyricsSyncEngine? {
        guard let tl = attachment.timeline else { return nil }
        return AmenLyricsSyncEngine(timeline: tl)
    }

    private var segments: [AmenTimedSegment] {
        attachment.timeline?.segments ?? []
    }

    private var activeIndex: Int? {
        engine?.activeSegmentIndex(atMs: coordinator.currentTimeMs)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .center, spacing: 8) {
                    ForEach(Array(segments.enumerated()), id: \.element.id) { idx, segment in
                        lyricLine(segment: segment, index: idx)
                            .id(idx)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .onChange(of: activeIndex) { _, newIndex in
                guard let idx = newIndex else { return }
                if reduceMotion {
                    proxy.scrollTo(idx, anchor: .center)
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        proxy.scrollTo(idx, anchor: .center)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func lyricLine(segment: AmenTimedSegment, index: Int) -> some View {
        let isActive = activeIndex == index
        let isPast: Bool = {
            guard let active = activeIndex else { return false }
            return index < active
        }()

        Group {
            if isActive && attachment.timeline?.isWordSynced == true && !reduceMotion {
                wordWipeLine(segment: segment)
            } else {
                Text(segment.label)
                    .font(.body.weight(isActive ? .bold : .regular))
                    .foregroundStyle(isActive ? activeTextColor : (isPast ? AmenTheme.Colors.textTertiary : AmenTheme.Colors.textSecondary))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, isActive ? 12 : 0)
        .padding(.vertical, isActive ? 6 : 0)
        .background(
            Group {
                if isActive {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AmenTheme.Colors.amenGold)
                }
            }
        )
        .animation(
            reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.8),
            value: activeIndex
        )
        .accessibilityLabel(segment.label)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    /// Active text color adapts for legibility on the amenGold background.
    private var activeTextColor: Color {
        // amenGold is a mid-bright warm yellow — black text provides the best contrast.
        Color.black
    }

    @ViewBuilder
    private func wordWipeLine(segment: AmenTimedSegment) -> some View {
        let text = segment.label
        let totalChars = text.count
        let revealed: Int = {
            guard let result = engine?.wordProgress(atMs: coordinator.currentTimeMs),
                  result.segment == segment.id else {
                return totalChars
            }
            return min(result.charsRevealed, totalChars)
        }()
        let fraction: CGFloat = totalChars > 0 ? CGFloat(revealed) / CGFloat(totalChars) : 1.0

        ZStack(alignment: .leading) {
            // Unrevealed layer (gold background, gray text)
            Text(text)
                .font(.body.weight(.bold))
                .foregroundStyle(Color.black.opacity(0.35))

            // Revealed layer (clipped to fraction)
            Text(text)
                .font(.body.weight(.bold))
                .foregroundStyle(Color.black)
                .mask(
                    GeometryReader { geo in
                        Rectangle()
                            .frame(width: geo.size.width * fraction)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                )
        }
        .multilineTextAlignment(.center)
    }
}

// MARK: - AmenVinylMusicCard

/// Large vinyl + album art card (~260pt tall). Matches IMG_2242.
/// Disc spins while playing; slides in on first appear (unless reduceMotion).
struct AmenVinylMusicCard: View {
    let attachment: AmenMediaAttachment
    let onCollapse: () -> Void

    @ObservedObject private var coordinator: AmenMediaPlaybackCoordinator = .shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var vinylRotation: Double = 0
    @State private var discOffset: CGFloat = 0
    @State private var isSpinning: Bool = false

    private var isPlaying: Bool { coordinator.isActive(attachment) && coordinator.isPlaying }

    var body: some View {
        VStack(spacing: 16) {
            ZStack(alignment: .topTrailing) {
                vinylDiscView
                    .padding(.top, 8)

                collapseButton
                    .padding(.top, 8)
                    .padding(.trailing, 8)
            }

            VStack(spacing: 4) {
                Text(attachment.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .lineLimit(1)

                if let details = attachment.musicDetails {
                    Text(details.artists.joined(separator: ", "))
                        .font(.subheadline)
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 16)

            AmenMusicPlayPauseButton(attachment: attachment, size: 56)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 260)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AmenTheme.Colors.surfaceCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(AmenTheme.Colors.separator, lineWidth: 1)
                )
        )
        .shadow(color: AmenTheme.Colors.shadowCard, radius: 16, x: 0, y: 5)
        .onAppear { handleAppear() }
        .onChange(of: isPlaying) { _, playing in
            handlePlaybackChange(playing)
        }
    }

    private var vinylDiscView: some View {
        ZStack {
            // Vinyl disc (dark ring)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(white: 0.18), Color(white: 0.07)],
                        center: .center,
                        startRadius: 10,
                        endRadius: 80
                    )
                )
                .frame(width: 160, height: 160)
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                )

            // Album art clipped to circle on top of disc
            Group {
                if let urlStr = attachment.musicDetails?.albumArtURL ?? attachment.thumbnailURL,
                   let url = URL(string: urlStr) {
                    AsyncImage(url: url) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFill()
                        } else {
                            vinylFallbackArt
                        }
                    }
                } else {
                    vinylFallbackArt
                }
            }
            .frame(width: 120, height: 120)
            .clipShape(Circle())
            .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 2)

            // Center spindle dot
            Circle()
                .fill(Color(white: 0.25))
                .frame(width: 10, height: 10)
        }
        .rotationEffect(.degrees(vinylRotation))
        .offset(x: discOffset)
        .accessibilityHidden(true)
    }

    private var vinylFallbackArt: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [AmenTheme.Colors.amenGold.opacity(0.7), AmenTheme.Colors.amenPurple.opacity(0.6)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                Image(systemName: "music.note")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.9))
            )
    }

    private var collapseButton: some View {
        Button(action: onCollapse) {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .frame(width: 30, height: 30)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close vinyl view")
    }

    private func handleAppear() {
        guard !reduceMotion else { return }
        discOffset = 80
        withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) {
            discOffset = 0
        }
        if isPlaying {
            startSpin()
        }
    }

    private func handlePlaybackChange(_ playing: Bool) {
        if playing {
            startSpin()
        } else {
            stopSpin()
        }
    }

    private func startSpin() {
        guard !reduceMotion, !isSpinning else { return }
        isSpinning = true
        withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) {
            vinylRotation += 360
        }
    }

    private func stopSpin() {
        guard isSpinning else { return }
        isSpinning = false
        // Capture current rotation to avoid a jump when animation stops
        withAnimation(.linear(duration: 0)) {
            vinylRotation = vinylRotation.truncatingRemainder(dividingBy: 360)
        }
    }
}

// MARK: - AmenMusicPlayPauseButton

/// Reusable Liquid Glass play/pause button.
/// Symbol morphs play↔pause unless reduceMotion.
/// Enforces a 44pt minimum tap target regardless of visual size.
struct AmenMusicPlayPauseButton: View {
    let attachment: AmenMediaAttachment
    let size: CGFloat

    @ObservedObject var coordinator: AmenMediaPlaybackCoordinator = .shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isActive: Bool { coordinator.isActive(attachment) }
    private var isPlaying: Bool { isActive && coordinator.isPlaying }

    var body: some View {
        Button {
            coordinator.togglePlay(attachment)
        } label: {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                Circle()
                    .fill(Color.white.opacity(0.15))

                Group {
                    if reduceMotion {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: size * 0.38, weight: .semibold))
                            .foregroundStyle(AmenTheme.Colors.textPrimary)
                    } else {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: size * 0.38, weight: .semibold))
                            .foregroundStyle(AmenTheme.Colors.textPrimary)
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
            }
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.10), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityLabel(isPlaying ? "Pause \(attachment.title)" : "Play \(attachment.title)")
    }
}

// MARK: - Sample data for Previews

extension AmenMediaAttachment {
    static let sampleMusic: AmenMediaAttachment = {
        let goalSegments = [
            AmenTimedSegment(id: 0, startMs: 0,     endMs: 3000,  label: "Yeah, let's go",           words: nil, thumbnailURL: nil),
            AmenTimedSegment(id: 1, startMs: 3000,  endMs: 7000,  label: "Goals, goals, goals",       words: nil, thumbnailURL: nil),
            AmenTimedSegment(id: 2, startMs: 7000,  endMs: 11000, label: "Yes, I'm",                  words: nil, thumbnailURL: nil),
            AmenTimedSegment(id: 3, startMs: 11000, endMs: 15000, label: "Goals, goals, goals (goals)", words: nil, thumbnailURL: nil),
            AmenTimedSegment(id: 4, startMs: 15000, endMs: 19000, label: "Running up the score",       words: nil, thumbnailURL: nil),
            AmenTimedSegment(id: 5, startMs: 19000, endMs: 23000, label: "We came to win",             words: nil, thumbnailURL: nil),
        ]
        let timeline = AmenMediaTimeline(
            segmentKind: .lyricLine,
            segments: goalSegments,
            isWordSynced: false
        )
        return AmenMediaAttachment(
            id: "sample-goals-001",
            kind: .music,
            sourceURL: nil,
            title: "Goals",
            subtitle: "LISA, Anitta, Rema",
            thumbnailURL: nil,
            accentHex: "#D4B038",
            playable: AmenPlayableInfo(
                transport: .nativeAudio,
                mediaURL: "https://example.com/goals.m4a",
                durationMs: 195_000,
                startMs: 0
            ),
            timeline: timeline,
            musicDetails: AmenMusicDetails(
                artists: ["LISA", "Anitta", "Rema"],
                albumArtURL: nil,
                displayMode: .compact
            )
        )
    }()

    static let sampleMusicExpanded: AmenMediaAttachment = {
        var a = AmenMediaAttachment.sampleMusic
        var details = a.musicDetails!
        let updatedDetails = AmenMusicDetails(
            artists: details.artists,
            albumArtURL: details.albumArtURL,
            displayMode: .expanded
        )
        return AmenMediaAttachment(
            id: a.id,
            kind: a.kind,
            sourceURL: a.sourceURL,
            title: a.title,
            subtitle: a.subtitle,
            thumbnailURL: a.thumbnailURL,
            accentHex: a.accentHex,
            playable: a.playable,
            timeline: a.timeline,
            musicDetails: updatedDetails
        )
    }()

    static let sampleMusicVinyl: AmenMediaAttachment = {
        var a = AmenMediaAttachment.sampleMusic
        let updatedDetails = AmenMusicDetails(
            artists: a.musicDetails!.artists,
            albumArtURL: a.musicDetails!.albumArtURL,
            displayMode: .vinyl
        )
        return AmenMediaAttachment(
            id: a.id,
            kind: a.kind,
            sourceURL: a.sourceURL,
            title: a.title,
            subtitle: a.subtitle,
            thumbnailURL: a.thumbnailURL,
            accentHex: a.accentHex,
            playable: a.playable,
            timeline: a.timeline,
            musicDetails: updatedDetails
        )
    }()
}

// MARK: - Previews

#Preview("Compact Card") {
    AmenMusicCardCompact(attachment: .sampleMusic, onTap: {})
        .padding(16)
        .background(AmenTheme.Colors.backgroundPrimary)
}

#Preview("Expanded Card with Lyrics") {
    AmenMusicCardExpanded(
        attachment: .sampleMusicExpanded,
        onCollapse: {}
    )
    .padding(16)
    .background(AmenTheme.Colors.backgroundPrimary)
}

#Preview("Karaoke Lyrics View") {
    AmenKaraokeLyricsView(attachment: .sampleMusicExpanded)
        .frame(height: 220)
        .padding(16)
        .background(AmenTheme.Colors.backgroundPrimary)
}

#Preview("Vinyl Card") {
    AmenVinylMusicCard(
        attachment: .sampleMusicVinyl,
        onCollapse: {}
    )
    .padding(16)
    .background(AmenTheme.Colors.backgroundPrimary)
}

#Preview("Play/Pause Button — 36pt") {
    AmenMusicPlayPauseButton(attachment: .sampleMusic, size: 36)
        .padding(20)
        .background(AmenTheme.Colors.backgroundSecondary)
}

#Preview("Play/Pause Button — 56pt") {
    AmenMusicPlayPauseButton(attachment: .sampleMusic, size: 56)
        .padding(20)
        .background(AmenTheme.Colors.backgroundSecondary)
}

#Preview("Container — All Modes") {
    VStack(spacing: 24) {
        AmenMusicCardContainer(attachment: .sampleMusic)
        AmenMusicCardContainer(attachment: .sampleMusicExpanded)
        AmenMusicCardContainer(attachment: .sampleMusicVinyl)
    }
    .padding(16)
    .background(AmenTheme.Colors.backgroundPrimary)
}
