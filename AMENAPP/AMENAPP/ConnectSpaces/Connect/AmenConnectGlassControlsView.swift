// AmenConnectGlassControlsView.swift
// AMEN Connect
//
// Glass floating controls overlay on the video player.
// Aegis rules enforced:
//   - syntheticMediaLabelsNonRemovable: provenance badge is non-removable, non-dismissable
//   - Controls auto-hide after 4 s; if reduce-motion → instant show/hide (no fade)

import SwiftUI
import AVKit
import FirebaseAnalytics

// MARK: - ViewModel

@MainActor
final class AmenConnectGlassControlsViewModel: ObservableObject {
    // MARK: Playback state
    @Published private(set) var isPlaying = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 1
    @Published private(set) var currentChapterIndex = 0

    // MARK: UI state
    @Published var isVisible = true
    @Published var showTranscript = false
    @Published var showContextSheet = false

    // MARK: Provenance summary (set externally)
    var provenanceSummary: String = "Unknown"

    private let player: AVPlayer
    private var timeObserverToken: Any?
    private var hideTask: Task<Void, Never>?

    init(player: AVPlayer) {
        self.player = player
    }

    deinit {
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
        }
        hideTask?.cancel()
    }

    func startObserving() {
        // Time observer
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            Task { @MainActor in
                self.currentTime = time.seconds
                if let item = self.player.currentItem {
                    let dur = item.duration.seconds
                    if dur.isFinite && dur > 0 {
                        self.duration = dur
                    }
                }
            }
        }
    }

    func togglePlayPause() {
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
        resetHideTimer()
    }

    func seek(to fraction: Double) {
        let target = CMTime(seconds: fraction * duration, preferredTimescale: 600)
        player.seek(to: target)
        resetHideTimer()
    }

    func seekChapterForward(chapterCount: Int) {
        guard currentChapterIndex < chapterCount - 1 else { return }
        currentChapterIndex += 1
        resetHideTimer()
    }

    func seekChapterBack() {
        guard currentChapterIndex > 0 else { return }
        currentChapterIndex -= 1
        resetHideTimer()
    }

    func onTap() {
        if isVisible {
            resetHideTimer()
        } else {
            showControls()
        }
    }

    func showControls() {
        isVisible = true
        resetHideTimer()
    }

    func toggleTranscript() {
        showTranscript.toggle()
        resetHideTimer()
    }

    func toggleContextSheet() {
        showContextSheet.toggle()
        resetHideTimer()
    }

    // MARK: Auto-hide
    private func resetHideTimer() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000) // 4 seconds
            if !Task.isCancelled {
                self.isVisible = false
            }
        }
    }

    var formattedCurrentTime: String { format(currentTime) }
    var formattedDuration: String    { format(duration) }
    var seekFraction: Double         { duration > 0 ? min(max(currentTime / duration, 0), 1) : 0 }

    private func format(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - View

struct AmenConnectGlassControlsView: View {
    let player: AVPlayer
    let chapterCount: Int
    let provenanceSummary: String
    var onTranscriptToggle: ((Bool) -> Void)?
    var onContextSheetToggle: ((Bool) -> Void)?

    @StateObject private var vm: AmenConnectGlassControlsViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Designated init so we can inject chapterCount / provenanceSummary into the vm
    init(player: AVPlayer,
         chapterCount: Int = 4,
         provenanceSummary: String = "Unknown",
         onTranscriptToggle: ((Bool) -> Void)? = nil,
         onContextSheetToggle: ((Bool) -> Void)? = nil) {
        self.player = player
        self.chapterCount = chapterCount
        self.provenanceSummary = provenanceSummary
        self.onTranscriptToggle = onTranscriptToggle
        self.onContextSheetToggle = onContextSheetToggle
        _vm = StateObject(wrappedValue: AmenConnectGlassControlsViewModel(player: player))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Invisible tap region to restore controls
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { vm.onTap() }

            // Glass controls overlay
            controlsBar
                .opacity(vm.isVisible ? 1 : 0)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: vm.isVisible)
        }
        .onAppear {
            vm.provenanceSummary = provenanceSummary
            vm.startObserving()
            vm.showControls()
            Analytics.logEvent("connect_glass_controls_viewed", parameters: nil)
        }
    }

    // MARK: Glass controls bar

    @ViewBuilder
    private var controlsBar: some View {
        VStack(spacing: 10) {
            // MARK: Provenance badge — NON-REMOVABLE, NON-DISMISSABLE (syntheticMediaLabelsNonRemovable)
            HStack {
                provenancePill
                Spacer()
            }

            // MARK: Seek bar (accentColor track)
            seekBar

            // MARK: Main controls row
            HStack(spacing: 12) {
                // Chapter back
                controlButton(icon: "backward.end.fill") { vm.seekChapterBack() }
                    .accessibilityLabel("Previous chapter")

                // Play / pause (accentColor circle)
                Button {
                    vm.togglePlayPause()
                } label: {
                    Image(systemName: vm.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color(.systemBackground))
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color.accentColor))
                }
                .accessibilityLabel(vm.isPlaying ? "Pause" : "Play")

                // Chapter forward
                controlButton(icon: "forward.end.fill") {
                    vm.seekChapterForward(chapterCount: chapterCount)
                }
                .accessibilityLabel("Next chapter")

                Spacer()

                // Time display (matte text)
                Text("\(vm.formattedCurrentTime) / \(vm.formattedDuration)")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.white.opacity(0.75))
                    .accessibilityLabel("Time: \(vm.formattedCurrentTime) of \(vm.formattedDuration)")
            }

            // MARK: Toggle row
            HStack(spacing: 8) {
                // Transcript toggle (amenBlue glass pill)
                togglePill(
                    label: "Transcript",
                    systemImage: "text.alignleft",
                    isActive: vm.showTranscript,
                    color: Color(hex: "245B8F")
                ) {
                    vm.toggleTranscript()
                    onTranscriptToggle?(vm.showTranscript)
                }

                // Source panel toggle
                togglePill(
                    label: "Context",
                    systemImage: "info.circle",
                    isActive: vm.showContextSheet,
                    color: Color.amenPurple
                ) {
                    vm.toggleContextSheet()
                    onContextSheetToggle?(vm.showContextSheet)
                }

                Spacer()
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.07))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                }
        }
        .shadow(color: .black.opacity(0.45), radius: 20, x: 0, y: 8)
    }

    // MARK: Seek bar

    @ViewBuilder
    private var seekBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Track background
                Capsule()
                    .fill(Color.white.opacity(0.20))
                    .frame(height: 4)

                // Filled track — accentColor
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: geo.size.width * vm.seekFraction, height: 4)

                // Thumb
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 14, height: 14)
                    .offset(x: geo.size.width * vm.seekFraction - 7)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let fraction = max(0, min(value.location.x / geo.size.width, 1))
                        vm.seek(to: fraction)
                    }
            )
        }
        .frame(height: 14)
        .accessibilityLabel("Seek bar")
        .accessibilityValue("\(vm.formattedCurrentTime) of \(vm.formattedDuration)")
    }

    // MARK: Provenance pill — NON-REMOVABLE

    @ViewBuilder
    private var provenancePill: some View {
        HStack(spacing: 5) {
            Image(systemName: "shield.fill")
                .font(.system(size: 9, weight: .bold))
            Text(provenanceSummary)
                .font(.system(size: 10, weight: .bold))
                .kerning(0.4)
        }
        .foregroundStyle(Color.white.opacity(0.85))
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background {
            Capsule()
                .fill(Color.white.opacity(0.12))
                .overlay {
                    Capsule().strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                }
        }
        .accessibilityLabel("Provenance: \(provenanceSummary)")
        .accessibilityAddTraits(.isStaticText)
    }

    // MARK: Reusable helpers

    @ViewBuilder
    private func controlButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.85))
                .frame(width: 36, height: 36)
                .background {
                    Circle()
                        .fill(Color.white.opacity(0.12))
                        .overlay { Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1) }
                }
        }
    }

    @ViewBuilder
    private func togglePill(label: String, systemImage: String, isActive: Bool, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))
                Text(label)
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(isActive ? color : Color.white.opacity(0.60))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                Capsule()
                    .fill(isActive ? color.opacity(0.20) : Color.white.opacity(0.08))
                    .overlay {
                        Capsule().strokeBorder(
                            isActive ? color.opacity(0.45) : Color.white.opacity(0.14),
                            lineWidth: 1
                        )
                    }
            }
        }
        .accessibilityLabel("\(label): \(isActive ? "on" : "off")")
    }
}

// MARK: - Preview

// Hex color helper — private, file-scoped
#if DEBUG
#Preview {
    ZStack {
        Color(.systemGroupedBackground).ignoresSafeArea()

        AmenConnectGlassControlsView(
            player: AVPlayer(),
            chapterCount: 4,
            provenanceSummary: "Human · AI-Edited"
        )
        .padding()
    }
}
#endif
