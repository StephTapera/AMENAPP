//
//  WorshipNowPlayingView.swift
//  AMENAPP
//
//  Full-screen "Now Playing" view for worship music in Church Notes.
//  Features:
//    - iOS 18 MeshGradient background: 4×4 grid, dual-speed warping,
//      colours extracted from album art — matches Apple Music's living background
//    - Glassmorphism (.ultraThinMaterial) controls that let mesh colours bleed through
//    - Album art with breathing scale animation
//    - Dolby Atmos + Lossless quality badges (below song title)
//    - Faith-specific "Worship" / "Church Notes" badges
//    - Adaptive contrast text readable over any gradient
//    - Integrates directly with WorshipMusicService
//

import SwiftUI
import AVFoundation
import Combine
#if canImport(MusicKit)
import MusicKit
#endif

// MARK: - Now Playing View

struct WorshipNowPlayingView: View {

    @ObservedObject private var service = WorshipNowPlayingViewModel.shared
    @Environment(\.dismiss) private var dismiss

    // Library / playlist action feedback
    @State private var addedToLibrary = false
    @State private var addedToPlaylist = false
    @State private var showingAddedToast = false
    @State private var toastMessage = ""

    // Subscription offer (shown when user has no Apple Music subscription)
    @State private var showSubscriptionOffer = false
    @State private var subscriptionItemID: String? = nil

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // ── Animated mesh background ─────────────────────────────────
                MeshBackground(colors: service.meshColors)
                    .ignoresSafeArea()

                // ── Subtle vignette so controls stay readable ─────────────────
                LinearGradient(
                    colors: [.clear, .black.opacity(0.35)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                // ── Content stack ────────────────────────────────────────────
                VStack(spacing: 0) {
                    // Dismiss handle
                    dismissHandle

                    Spacer()

                    // Album art — breathing scale, dramatic shadow
                    albumArtSection(geo: geo)

                    Spacer(minLength: 36)

                    // Song info + quality badges + faith badges
                    songInfoSection

                    Spacer(minLength: 28)

                    // Progress bar
                    progressSection

                    Spacer(minLength: 28)

                    // Frosted glass playback controls
                    controlsSection

                    Spacer(minLength: 20)

                    // Secondary actions: Open in Music, Library, Playlist
                    secondaryActionsSection

                    Spacer(minLength: 36)
                }
                .padding(.horizontal, 28)

                // Toast overlay
                if showingAddedToast {
                    VStack {
                        Spacer()
                        Text(toastMessage)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(.ultraThinMaterial))
                            .padding(.bottom, 110)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { service.startMonitoring() }
        .onDisappear { service.stopMonitoring() }
        .onReceive(NotificationCenter.default.publisher(for: .worshipMusicSubscriptionRequired)) { note in
            subscriptionItemID = note.userInfo?["itemID"] as? String
            showSubscriptionOffer = true
        }
        #if canImport(MusicKit)
        .musicSubscriptionOffer(isPresented: $showSubscriptionOffer, options: subscriptionOfferOptions)
        #endif
    }

    #if canImport(MusicKit)
    private var subscriptionOfferOptions: MusicSubscriptionOffer.Options {
        var opts = MusicSubscriptionOffer.Options()
        if let id = subscriptionItemID {
            opts.itemID = MusicItemID(id)
        }
        opts.messageIdentifier = .playMusic
        return opts
    }
    #endif

    // MARK: - Sub-views

    private var dismissHandle: some View {
        Capsule()
            .fill(Color.white.opacity(0.3))
            .frame(width: 36, height: 4)
            .padding(.top, 14)
    }

    @ViewBuilder
    private func albumArtSection(geo: GeometryProxy) -> some View {
        let artSize = geo.size.width * 0.80
        ZStack {
            if let urlStr = service.currentSong?.albumArtURL, let url = URL(string: urlStr) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(1, contentMode: .fill)
                            .onAppear { service.extractColors(from: image) }
                    default:
                        defaultAlbumArt
                    }
                }
            } else {
                defaultAlbumArt
            }
        }
        .frame(width: artSize, height: artSize)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        // Dramatic tinted shadow that changes with album colors
        .shadow(
            color: (service.meshColors.first ?? .purple).opacity(0.65),
            radius: 50, y: 20
        )
        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        // Breathing scale: large when playing, shrinks on pause
        .scaleEffect(service.isPlaying ? 1.0 : 0.90)
        .animation(.spring(response: 0.6, dampingFraction: 0.72), value: service.isPlaying)
    }

    private var defaultAlbumArt: some View {
        ZStack {
            LinearGradient(
                colors: [Color.purple.opacity(0.6), Color.indigo.opacity(0.8)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            VStack(spacing: 8) {
                Image(systemName: "music.note")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(.white.opacity(0.8))
                Text("Worship")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    private var songInfoSection: some View {
        VStack(spacing: 10) {
            // Title + heart button in same row (Apple Music style)
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(service.currentSong?.title ?? "No Song Playing")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .shadow(color: .black.opacity(0.3), radius: 4)

                    Text(service.currentSong?.artist ?? "")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                }

                Spacer()

                // Heart (placeholder — Apple Music style)
                Image(systemName: "heart")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.top, 2)
            }

            // Quality + faith badges row
            HStack(spacing: 8) {
                // Dolby Atmos badge
                QualityBadge(label: "Dolby Atmos", color: .blue.opacity(0.8))
                // Lossless badge
                QualityBadge(label: "Lossless", color: .green.opacity(0.8))

                Spacer()

                // Faith badges
                FaithBadge(label: "Worship", icon: "music.note.list")
                if service.currentSong?.churchNoteId != nil {
                    FaithBadge(label: "Church Notes", icon: "note.text")
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var progressSection: some View {
        VStack(spacing: 8) {
            // Progress track
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.2))
                        .frame(height: 4)
                    Capsule()
                        .fill(Color.white)
                        .frame(width: g.size.width * service.progress, height: 4)
                }
            }
            .frame(height: 4)

            // Time labels
            HStack {
                Text(formatTime(service.elapsed))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                Text(formatTime(service.duration))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    private var controlsSection: some View {
        // Frosted glass pill — mesh colours bleed through ultraThinMaterial
        HStack(spacing: 0) {
            // Backward (restart for previews)
            ControlButton(icon: "backward.fill", size: 22) {
                // restart — no-op for preview tracks
            }

            Spacer()

            // Play / Pause — large, centred
            ControlButton(icon: service.isPlaying ? "pause.fill" : "play.fill", size: 40) {
                service.togglePlayback()
            }

            Spacer()

            // Stop
            ControlButton(icon: "stop.fill", size: 22) {
                service.stop()
                dismiss()
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 22)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                )
        )
    }

    // MARK: - Secondary actions

    private var secondaryActionsSection: some View {
        HStack(spacing: 24) {
            secondaryButton(icon: "arrow.up.right.circle.fill", label: "Apple Music") {
                WorshipMusicService.shared.openInAppleMusic()
            }

            secondaryButton(
                icon: addedToLibrary ? "checkmark.circle.fill" : "plus.circle.fill",
                label: addedToLibrary ? "Saved" : "Library"
            ) {
                guard !addedToLibrary else { return }
                Task {
                    let ok = await WorshipMusicService.shared.addToLibrary()
                    if ok {
                        addedToLibrary = true
                        showToast("Added to library")
                    }
                }
            }

            secondaryButton(
                icon: addedToPlaylist ? "checkmark.circle.fill" : "music.note.list",
                label: addedToPlaylist ? "Added" : "Playlist"
            ) {
                guard !addedToPlaylist else { return }
                Task {
                    let ok = await WorshipMusicService.shared.addCurrentSongToWorshipPlaylist()
                    if ok {
                        addedToPlaylist = true
                        showToast("Added to AMEN Worship playlist")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func secondaryButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundStyle(.white.opacity(0.85))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
            }
        }
        .buttonStyle(.plain)
    }

    private func showToast(_ message: String) {
        toastMessage = message
        withAnimation(.spring(response: 0.35)) { showingAddedToast = true }
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            withAnimation(.easeOut) { showingAddedToast = false }
        }
    }

    // MARK: - Helpers

    private func formatTime(_ secs: Int) -> String {
        let m = secs / 60
        let s = secs % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Animated Mesh Background (4×4, dual-speed warp)

/// A 4×4 MeshGradient with 16 control points.
/// Two independent oscillators — slow drift + faster micro-shimmer — create
/// the organic, "breathing lava-lamp" effect seen in Apple Music on iOS 18.
private struct MeshBackground: View {
    let colors: [Color]

    // 16 colors for a 4×4 mesh
    private var meshColors: [Color] {
        let base = colors.isEmpty ? MeshPalette.faith : colors
        return (0..<16).map { base[$0 % base.count] }
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            MeshGradient(
                width: 4,
                height: 4,
                points: warpedPoints(t: t),
                colors: meshColors,
                smoothsColors: true,
                colorSpace: .perceptual   // smoother colour blending
            )
        }
    }

    /// 16 SIMD2<Float> points on a 4×4 grid, each animated by:
    ///  - A slow, large-amplitude drift (macro warp, ~22-second cycle)
    ///  - A fast, small-amplitude shimmer (micro warp, ~7-second cycle)
    /// The superposition of the two frequencies gives the Apple Music feel.
    private func warpedPoints(t: Double) -> [SIMD2<Float>] {
        // Base 4×4 grid positions
        let grid: [SIMD2<Float>] = [
            [0.0,   0.0  ], [0.333, 0.0  ], [0.667, 0.0  ], [1.0,   0.0  ],
            [0.0,   0.333], [0.333, 0.333], [0.667, 0.333], [1.0,   0.333],
            [0.0,   0.667], [0.333, 0.667], [0.667, 0.667], [1.0,   0.667],
            [0.0,   1.0  ], [0.333, 1.0  ], [0.667, 1.0  ], [1.0,   1.0  ]
        ]

        // Per-point phase offsets (unique so no two points move in lockstep)
        let phases: [Double] = [
            0.00, 1.31, 2.73, 0.85,
            3.41, 1.68, 0.29, 2.94,
            2.15, 3.57, 1.04, 0.52,
            0.76, 2.38, 1.92, 3.14
        ]

        // Macro warp: slow & large
        let slowSpeed = 0.14
        let slowAmp: Float = 0.10

        // Micro shimmer: fast & tiny
        let fastSpeed = 0.48
        let fastAmp: Float = 0.025

        return zip(grid, phases).map { point, phase in
            // Slow component — elliptical drift
            let slowX = Float(sin((t + phase) * slowSpeed) * Double(slowAmp))
            let slowY = Float(cos((t + phase * 0.73) * slowSpeed) * Double(slowAmp))

            // Fast component — perpendicular shimmer
            let fastX = Float(cos((t + phase * 1.4) * fastSpeed) * Double(fastAmp))
            let fastY = Float(sin((t + phase * 0.6) * fastSpeed) * Double(fastAmp))

            let px = point.x + slowX + fastX
            let py = point.y + slowY + fastY

            // Clamp: keep corner points within a tight margin so the view fills edge-to-edge
            return SIMD2<Float>(
                min(max(px, 0), 1),
                min(max(py, 0), 1)
            )
        }
    }
}

// MARK: - Quality Badge (Dolby Atmos / Lossless)

private struct QualityBadge: View {
    let label: String
    let color: Color

    var body: some View {
        Text(label)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().strokeBorder(color.opacity(0.5), lineWidth: 0.8))
            )
    }
}

// MARK: - Faith Badge

private struct FaithBadge: View {
    let label: String
    let icon: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
            Text(label)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(.white.opacity(0.85))
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 0.8))
        )
    }
}

// MARK: - Control Button

private struct ControlButton: View {
    let icon: String
    let size: CGFloat
    let action: () -> Void

    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: size + 24, height: size + 24)
                .contentShape(Circle())
                .scaleEffect(pressed ? 0.86 : 1.0)
                .animation(.spring(response: 0.2, dampingFraction: 0.55), value: pressed)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in pressed = true }
            .onEnded   { _ in pressed = false }
        )
    }
}

// MARK: - Default Mesh Palettes

private enum MeshPalette {
    /// AMEN faith palette — deep purples + gold + midnight blue
    static let faith: [Color] = [
        Color(red: 0.08, green: 0.04, blue: 0.22),  // near-black violet
        Color(red: 0.14, green: 0.06, blue: 0.38),  // deep violet
        Color(red: 0.28, green: 0.10, blue: 0.50),  // royal purple
        Color(red: 0.18, green: 0.08, blue: 0.40),  // mid-purple
        Color(red: 0.06, green: 0.10, blue: 0.34),  // midnight indigo
        Color(red: 0.52, green: 0.34, blue: 0.08),  // warm gold
        Color(red: 0.10, green: 0.16, blue: 0.42),  // deep navy
    ]

    static let prayer: [Color] = [
        Color(red: 0.06, green: 0.06, blue: 0.28),
        Color(red: 0.18, green: 0.08, blue: 0.42),
        Color(red: 0.48, green: 0.18, blue: 0.66),
        Color(red: 0.10, green: 0.04, blue: 0.20),
        Color(red: 0.32, green: 0.12, blue: 0.52),
    ]
}

// MARK: - ViewModel (Observable wrapper over WorshipMusicService)

/// Wraps the non-`ObservableObject` `WorshipMusicService` so SwiftUI can react.
@MainActor
final class WorshipNowPlayingViewModel: ObservableObject {
    static let shared = WorshipNowPlayingViewModel()
    private init() {}

    @Published var currentSong: WorshipMusicService.SongInfo? = nil
    @Published var isPlaying: Bool = false
    @Published var elapsed: Int = 0
    @Published var duration: Int = 0
    @Published var meshColors: [Color] = MeshPalette.faith

    var progress: CGFloat {
        guard duration > 0 else { return 0 }
        return CGFloat(elapsed) / CGFloat(duration)
    }

    private var pollTask: Task<Void, Never>?

    // MARK: - Lifecycle

    func startMonitoring() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await MainActor.run { self?.sync() }
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            }
        }
    }

    func stopMonitoring() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func sync() {
        let svc = WorshipMusicService.shared
        currentSong = svc.currentSong
        isPlaying   = svc.isPlaying
        duration    = svc.currentSong?.durationSeconds ?? 0
    }

    // MARK: - Controls

    func togglePlayback() {
        WorshipMusicService.shared.pauseResume()
        isPlaying = WorshipMusicService.shared.isPlaying
    }

    func stop() {
        WorshipMusicService.shared.stopPlayback()
        isPlaying   = false
        currentSong = nil
    }

    // MARK: - Color extraction from album art

    /// Extracts 5–7 dominant colors from the album image and feeds them to the mesh.
    /// Uses UIKit pixel-sampling — no Vision entitlement needed.
    func extractColors(from image: Image) {
        Task.detached(priority: .utility) {
            guard let uiImage = await Self.renderToUIImage(image) else { return }
            let colors = await Self.dominantColors(from: uiImage, count: 7)
            await MainActor.run { [weak self] in
                if !colors.isEmpty { self?.meshColors = colors }
            }
        }
    }

    @MainActor
    private static func renderToUIImage(_ swiftUIImage: Image) async -> UIImage? {
        let renderer = ImageRenderer(content: swiftUIImage.resizable().frame(width: 80, height: 80))
        renderer.scale = 1
        return renderer.uiImage
    }

    /// Pixel-based dominant colour sampler.
    /// Samples a 16×16 grid, darkens each pixel by 55% so colours read as a moody background.
    private static func dominantColors(from image: UIImage, count: Int) async -> [Color] {
        guard let cgImage = image.cgImage else { return [] }

        let width = 16, height = 16
        var rawData = [UInt8](repeating: 0, count: width * height * 4)

        guard let ctx = CGContext(
            data: &rawData,
            width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return [] }

        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var colors: [Color] = []
        for i in 0..<(width * height) {
            let r = Double(rawData[i * 4 + 0]) / 255
            let g = Double(rawData[i * 4 + 1]) / 255
            let b = Double(rawData[i * 4 + 2]) / 255
            // Darken to keep background moody, skip near-white/grey pixels
            let brightness = (r + g + b) / 3
            if brightness < 0.85 {
                colors.append(Color(red: r * 0.45, green: g * 0.45, blue: b * 0.45))
            }
        }

        guard !colors.isEmpty else { return MeshPalette.faith }

        let step = max(1, colors.count / count)
        return stride(from: 0, to: colors.count, by: step).prefix(count).map { colors[$0] }
    }
}

// MARK: - WorshipSongCard "open now playing" upgrade

/// Drop-in replacement that adds a tap-to-expand Now Playing sheet on the existing WorshipSongCard.
struct WorshipSongCardExpanding: View {
    let title: String
    let artist: String
    var churchNoteId: String? = nil

    @State private var showNowPlaying = false

    var body: some View {
        WorshipSongCard(title: title, artist: artist, churchNoteId: churchNoteId)
            .onTapGesture(count: 2) { showNowPlaying = true }
            .overlay(alignment: .topTrailing) {
                // Mini "expand" hint badge when this song is playing
                if WorshipNowPlayingViewModel.shared.isPlaying &&
                   WorshipNowPlayingViewModel.shared.currentSong?.title == title {
                    Button { showNowPlaying = true } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(5)
                            .background(Circle().fill(.ultraThinMaterial))
                    }
                    .offset(x: 6, y: -6)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .fullScreenCover(isPresented: $showNowPlaying) {
                WorshipNowPlayingView()
            }
    }
}

// MARK: - NoteWorshipSection

/// Shown in ChurchNoteDetailView when a worship song is actively playing for this note.
struct NoteWorshipSection: View {
    let noteId: String?

    @ObservedObject private var vm = WorshipNowPlayingViewModel.shared

    private var matchingSong: WorshipMusicService.SongInfo? {
        guard let song = vm.currentSong,
              let noteId = noteId,
              song.churchNoteId == noteId else { return nil }
        return song
    }

    var body: some View {
        if let song = matchingSong {
            VStack(alignment: .leading, spacing: 16) {
                Label("Now Playing", systemImage: "music.note")
                    .font(.custom("OpenSans-Bold", size: 18))
                    .foregroundStyle(.white.opacity(0.9))

                WorshipSongCardExpanding(
                    title: song.title,
                    artist: song.artist,
                    churchNoteId: noteId
                )
            }
            .padding(24)
            .glassEffect(GlassEffectStyle.regular.tint(.purple), in: RoundedRectangle(cornerRadius: 24))
            .transition(.scale(scale: 0.95).combined(with: .opacity))
        }
    }
}

// MARK: - Preview

#Preview("Worship Now Playing") {
    let _ = {
        let vm = WorshipNowPlayingViewModel.shared
        vm.currentSong = WorshipMusicService.SongInfo(
            title: "Way Maker",
            artist: "Sinach",
            albumArtURL: nil,
            appleMusicURL: nil,
            previewURL: nil,
            churchNoteId: "note123",
            durationSeconds: 210,
            musicKitID: nil
        )
        vm.isPlaying = true
        vm.elapsed = 64
    }()
    WorshipNowPlayingView()
}

#Preview("Mesh Background — Faith") {
    MeshBackground(colors: MeshPalette.faith)
        .ignoresSafeArea()
}
