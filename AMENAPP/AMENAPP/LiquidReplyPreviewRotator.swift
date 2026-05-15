import SwiftUI

// MARK: - LiquidReplyPreviewRotator

/// Manages client-side rotation between server-approved reply preview candidates.
///
/// Rotation rules:
///   - Rotates every 8–15 s (randomised per post to avoid synchronised feed animation)
///   - Pauses when the view leaves screen (onDisappear)
///   - Pauses when Reduce Motion is enabled (shows highest-ranked candidate only)
///   - Clients rotate between server-approved candidates only — no text is generated here
///   - Timer is cancelled and deallocated on disappear to prevent battery drain
struct LiquidReplyPreviewRotator: View {
    let candidates: [DynamicReplyPreview]
    let onOpenReplies: (DynamicReplyPreview) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var currentIndex = 0
    @State private var isVisible = false
    @State private var timerTask: Task<Void, Never>?

    // MARK: - Derived

    private var safeCandidates: [DynamicReplyPreview] {
        candidates
            .filter { $0.isSafe && !$0.isExpired }
            .sorted { $0.score > $1.score }
    }

    private var current: DynamicReplyPreview? {
        guard !safeCandidates.isEmpty else { return nil }
        return safeCandidates[currentIndex % safeCandidates.count]
    }

    private var shouldRotate: Bool {
        isVisible && !reduceMotion && safeCandidates.count > 1
    }

    // MARK: - Body

    var body: some View {
        Group {
            if let preview = current {
                LiquidReplyPreviewChip(preview: preview) {
                    onOpenReplies(preview)
                }
                .id(preview.id)
                .transition(
                    .opacity.combined(with: .scale(scale: 0.986, anchor: .leading))
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(
            reduceMotion ? .none : .easeInOut(duration: LiquidGlassTokens.motionFast),
            value: current?.id
        )
        .onAppear {
            isVisible = true
            updateRotationState()
        }
        .onDisappear {
            isVisible = false
            stopRotation()
        }
        .onChange(of: candidates) { _, _ in
            currentIndex = 0
            updateRotationState()
        }
        .onChange(of: reduceMotion) { _, _ in
            updateRotationState()
        }
    }

    // MARK: - Rotation Control

    private func updateRotationState() {
        if shouldRotate {
            startRotationIfNeeded()
        } else {
            stopRotation()
        }
    }

    private func startRotationIfNeeded() {
        guard shouldRotate, timerTask == nil else { return }

        timerTask = Task {
            while !Task.isCancelled {
                // Randomise interval per post so all cards don't flip at the same moment
                let delayNs = UInt64(Int.random(in: 8...15)) * 1_000_000_000
                try? await Task.sleep(nanoseconds: delayNs)
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    guard shouldRotate else { return }
                    withAnimation(.easeInOut(duration: LiquidGlassTokens.motionFast)) {
                        currentIndex = (currentIndex + 1) % max(1, safeCandidates.count)
                    }
                }
            }
        }
    }

    private func stopRotation() {
        timerTask?.cancel()
        timerTask = nil
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Rotator – 4 candidates") {
    LiquidReplyPreviewRotator(
        candidates: [
            .previewTopReply,
            .previewPrayer,
            .previewBerean,
            .previewPulse
        ]
    ) { _ in }
    .padding()
    .background(Color(.systemBackground))
}

#Preview("Rotator – no safe candidates") {
    LiquidReplyPreviewRotator(candidates: []) { _ in }
        .padding()
        .background(Color(.systemBackground))
}
#endif
