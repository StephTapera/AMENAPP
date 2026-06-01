// SelahStoryViewerView.swift
// AMENAPP/SelahStories
//
// Phase 5 — Selah Stories
// Full-screen story playback viewer.
//
// Reactions: "Amen" (hands.raised) + "Praying" (hands.sparkles) — NOT likes.
// Reaction counts are AUTHOR-PRIVATE (never shown to viewers).
// 24-hour countdown timer shown in the header.
// Swipe-down to dismiss.
//
// Gate: returns EmptyView when selahStories flag is OFF.
// UI: AmenGlassKit only — no bespoke materials.
//

import SwiftUI
import AVKit

// MARK: - SelahStoryViewerView

struct SelahStoryViewerView: View {

    // MARK: Inputs

    let stories: [SelahStory]
    let initialIndex: Int
    /// The uid of the currently signed-in user (to determine author-mode).
    let currentUserUid: String

    // MARK: State

    @State private var currentIndex: Int
    @State private var progress: Double = 0
    @State private var isTimerRunning = false
    @State private var hasReacted: [SelahReactionKind: Bool] = [:]
    @State private var isDismissing = false
    @State private var dragOffset: CGSize = .zero
    @State private var showReactionConfirm: SelahReactionKind? = nil

    // MARK: Environment

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: Constants

    private let storyDurationSeconds: Double = 7.0  // per-slide display time
    private let timerInterval: Double = 0.05

    // MARK: Init

    init(stories: [SelahStory], initialIndex: Int = 0, currentUserUid: String) {
        self.stories = stories
        self.initialIndex = initialIndex
        self.currentUserUid = currentUserUid
        self._currentIndex = State(initialValue: initialIndex)
    }

    // MARK: Computed

    private var currentStory: SelahStory? {
        guard stories.indices.contains(currentIndex) else { return nil }
        return stories[currentIndex]
    }

    private var isAuthor: Bool {
        currentStory?.ownerUid == currentUserUid
    }

    // MARK: Body

    var body: some View {
        if !AMENFeatureFlags.shared.selahStories {
            EmptyView()
        } else {
            ZStack {
                viewerContent
                    .gesture(swipeDownGesture)

                // Reaction confirm toast
                if let kind = showReactionConfirm {
                    reactionConfirmToast(kind)
                        .transition(
                            reduceMotion
                                ? .opacity
                                : .scale(scale: 0.8).combined(with: .opacity)
                        )
                        .zIndex(10)
                }
            }
            .ignoresSafeArea()
            .statusBarHidden(true)
            .onAppear { startTimer() }
            .onDisappear { isTimerRunning = false }
        }
    }

    // MARK: - Viewer Content

    @ViewBuilder
    private var viewerContent: some View {
        if let story = currentStory {
            ZStack(alignment: .top) {
                // LAYER 0: Full-screen media background
                mediaBackground(for: story)
                    .ignoresSafeArea()

                // LAYER 1: Gradient scrim for text legibility
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.55), location: 0.0),
                        .init(color: .clear,               location: 0.35),
                        .init(color: .clear,               location: 0.65),
                        .init(color: .black.opacity(0.60), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)

                // LAYER 2: UI chrome
                VStack(spacing: 0) {
                    progressHeader(story: story)
                    Spacer()
                    overlayContent(story: story)
                    bottomBar(story: story)
                }

                // LAYER 3: Swipe-tap regions
                tapRegions
            }
            .offset(y: dragOffset.height > 0 ? dragOffset.height : 0)
            .scaleEffect(dragScale)
            .opacity(dragOpacity)
            .animation(
                reduceMotion ? .easeInOut(duration: 0.12) : Motion.liquidSpring,
                value: dragOffset
            )
        } else {
            Color.black.ignoresSafeArea()
                .onAppear { dismiss() }
        }
    }

    // MARK: - Progress Header

    private func progressHeader(story: SelahStory) -> some View {
        VStack(spacing: 8) {
            // Progress bars (one per story in the current user's stack)
            HStack(spacing: 4) {
                ForEach(stories.indices, id: \.self) { idx in
                    storyProgressBar(index: idx)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 54)  // safe-area top

            // Header row: avatar, name, countdown, close
            HStack(spacing: 10) {
                // Close button
                AmenFloatingGlassBackButton { dismiss() }
                    .accessibilityLabel("Close story")

                Spacer()

                // Countdown timer badge
                if let expiresAt = story.expiresAt {
                    countdownBadge(expiresAt: expiresAt)
                }

                // Story kind badge
                storyKindBadge(kind: story.kind)
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)
        }
    }

    @ViewBuilder
    private func storyProgressBar(index: Int) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.35))
                    .frame(height: 3)

                Capsule()
                    .fill(Color.white)
                    .frame(
                        width: geo.size.width * progressFraction(for: index),
                        height: 3
                    )
                    .animation(
                        index == currentIndex && isTimerRunning
                            ? .linear(duration: timerInterval)
                            : .none,
                        value: progress
                    )
            }
        }
        .frame(height: 3)
    }

    private func progressFraction(for index: Int) -> Double {
        if index < currentIndex { return 1.0 }
        if index > currentIndex { return 0.0 }
        return progress
    }

    private func countdownBadge(expiresAt: Date) -> some View {
        let remaining = expiresAt.timeIntervalSinceNow
        let hours = max(0, Int(remaining / 3600))
        let label = hours > 0 ? "\(hours)h left" : "< 1h left"

        return Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .amenGlass(.thin, cornerRadius: 10)
            .accessibilityLabel("Story expires in \(label)")
    }

    private func storyKindBadge(kind: StoryKind) -> some View {
        HStack(spacing: 4) {
            Image(systemName: kind.icon)
                .font(.system(size: 11, weight: .semibold))
            Text(kind.displayName)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .amenGlass(.thin, cornerRadius: 10)
        .accessibilityLabel("Story type: \(kind.displayName)")
    }

    // MARK: - Overlay Content (scripture cards, stickers)

    @ViewBuilder
    private func overlayContent(story: SelahStory) -> some View {
        VStack(spacing: 10) {
            ForEach(story.overlays) { overlay in
                storyOverlayCard(overlay)
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 8)
    }

    private func storyOverlayCard(_ overlay: StoryOverlay) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let ref = overlay.scriptureRef {
                Text("\(ref.book) \(ref.chapter)\(ref.verse.map { ":\($0)" } ?? "")")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AmenTheme.Colors.amenGold)
            }
            Text(overlay.text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .amenGlass(.regular, cornerRadius: 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(overlayAccessibilityLabel(overlay))
    }

    private func overlayAccessibilityLabel(_ overlay: StoryOverlay) -> String {
        if let ref = overlay.scriptureRef {
            return "\(ref.book) chapter \(ref.chapter): \(overlay.text)"
        }
        return overlay.text
    }

    // MARK: - Bottom Bar (caption + reactions)

    private func bottomBar(story: SelahStory) -> some View {
        VStack(spacing: 12) {
            // Caption
            if let caption = story.caption, !caption.isEmpty {
                captionView(caption)
            }

            // Season tag
            if let season = story.liturgicalSeason {
                seasonTagView(season)
            }

            // Reaction row
            HStack(spacing: 16) {
                reactionButton(kind: .amen, story: story)
                reactionButton(kind: .praying, story: story)
                Spacer()

                // Author sees private reaction count; viewers see nothing.
                if isAuthor {
                    authorReactionSummary(story: story)
                }
            }
            .padding(.horizontal, 18)
        }
        .padding(.bottom, 40)
    }

    private func captionView(_ caption: String) -> some View {
        Text(caption)
            .font(.subheadline)
            .foregroundStyle(.white)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .amenGlassScrim()
            .accessibilityLabel("Caption: \(caption)")
    }

    private func seasonTagView(_ season: LiturgicalSeasonKind) -> some View {
        HStack(spacing: 5) {
            Image(systemName: season.icon)
                .font(.system(size: 11))
            Text(season.displayName)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .amenGlass(.thin, cornerRadius: 10)
        .padding(.leading, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("Season: \(season.displayName)")
    }

    // MARK: Reaction Buttons

    private func reactionButton(kind: SelahReactionKind, story: SelahStory) -> some View {
        let reacted = hasReacted[kind] == true

        return Button {
            withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : Motion.liquidSpring) {
                hasReacted[kind] = !reacted
            }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            showReactionConfirm = kind
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                withAnimation { showReactionConfirm = nil }
            }
            Task { await sendReaction(kind: kind, storyId: story.id, reacted: !reacted) }
        } label: {
            HStack(spacing: 6) {
                Group {
                    if #available(iOS 17, *) {
                        Image(systemName: kind.icon)
                            .font(.system(size: 22, weight: .semibold))
                            .symbolEffect(.bounce, value: reacted)
                    } else {
                        Image(systemName: kind.icon)
                            .font(.system(size: 22, weight: .semibold))
                    }
                }
                Text(kind.displayLabel)
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(reacted ? kind.activeColor : .white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .amenGlass(.thin, cornerRadius: 22)
            .scaleEffect(reacted ? (reduceMotion ? 1 : 1.06) : 1)
        }
        .buttonStyle(GlassKitPressStyle(reduceMotion: reduceMotion))
        .accessibilityLabel(kind.displayLabel)
        .accessibilityHint(reacted ? "You reacted. Double tap to remove." : "Double tap to react.")
        .accessibilityAddTraits(reacted ? [.isSelected] : [])
    }

    /// Author-only private reaction summary pill. Never shown to viewers.
    @ViewBuilder
    private func authorReactionSummary(story: SelahStory) -> some View {
        // We only show a static summary since we're not maintaining a live count in this
        // view model (the count comes from Firestore sub-collection reads in a future pass).
        // For now we render a placeholder that signals "private metric" to the author.
        HStack(spacing: 4) {
            Image(systemName: "eye.slash")
                .font(.system(size: 11))
            Text("Only you see this")
                .font(.caption2)
        }
        .foregroundStyle(.white.opacity(0.65))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .amenGlass(.thin, cornerRadius: 8)
        .accessibilityLabel("Reaction counts are private and visible only to you")
    }

    // MARK: - Reaction Toast

    private func reactionConfirmToast(_ kind: SelahReactionKind) -> some View {
        VStack {
            Spacer()
            HStack(spacing: 8) {
                Image(systemName: kind.icon)
                    .font(.system(size: 18))
                    .foregroundStyle(kind.activeColor)
                Text(kind.toastMessage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .amenGlass(.regular, cornerRadius: 22)
            .padding(.bottom, 110)
        }
    }

    // MARK: - Tap Regions (advance/rewind)

    private var tapRegions: some View {
        HStack(spacing: 0) {
            // Left tap → previous story
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { goToPrevious() }
                .accessibilityLabel("Previous story")
                .accessibilityHint("Double tap to go to the previous story")

            // Right tap → next story
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { goToNext() }
                .accessibilityLabel("Next story")
                .accessibilityHint("Double tap to advance to the next story")
        }
    }

    // MARK: - Media Background

    @ViewBuilder
    private func mediaBackground(for story: SelahStory) -> some View {
        if let media = story.media.first {
            if media.mediaType == "video" {
                // Placeholder: real implementation would use AVPlayer.
                Color.black
                    .overlay(
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.white.opacity(0.5))
                    )
            } else {
                // Photo — load from URL or show placeholder.
                AsyncImage(url: URL(string: media.url)) { phase in
                    switch phase {
                    case .empty:
                        Color(uiColor: .systemGray6)
                            .overlay(ProgressView().tint(.white))
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        Color(uiColor: .systemGray5)
                            .overlay(
                                Image(systemName: "photo")
                                    .font(.system(size: 48))
                                    .foregroundStyle(.white.opacity(0.4))
                            )
                    @unknown default:
                        Color.black
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            }
        } else {
            // No media — solid AMEN background
            LinearGradient(
                colors: [AmenTheme.Colors.amenPurple.opacity(0.8), AmenTheme.Colors.amenBlue.opacity(0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    // MARK: - Swipe Down to Dismiss

    private var swipeDownGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                if value.translation.height > 0 {
                    dragOffset = value.translation
                    isTimerRunning = false
                }
            }
            .onEnded { value in
                if value.translation.height > 120 {
                    isDismissing = true
                    withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.35, dampingFraction: 0.7)) {
                        dragOffset = CGSize(width: 0, height: UIScreen.main.bounds.height)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { dismiss() }
                } else {
                    withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : Motion.liquidSpring) {
                        dragOffset = .zero
                    }
                    startTimer()
                }
            }
    }

    private var dragScale: CGFloat {
        guard dragOffset.height > 0, !reduceMotion else { return 1.0 }
        let fraction = max(0, min(1, dragOffset.height / 300))
        return 1.0 - 0.1 * fraction
    }

    private var dragOpacity: Double {
        guard dragOffset.height > 0 else { return 1.0 }
        let fraction = max(0, min(1, dragOffset.height / 200))
        return 1.0 - 0.35 * fraction
    }

    // MARK: - Timer

    private func startTimer() {
        progress = 0
        isTimerRunning = true
        advanceTimer()
    }

    private func advanceTimer() {
        guard isTimerRunning else { return }
        let increment = timerInterval / storyDurationSeconds
        DispatchQueue.main.asyncAfter(deadline: .now() + timerInterval) {
            guard self.isTimerRunning else { return }
            self.progress = min(self.progress + increment, 1.0)
            if self.progress >= 1.0 {
                self.goToNext()
            } else {
                self.advanceTimer()
            }
        }
    }

    // MARK: - Navigation

    private func goToNext() {
        isTimerRunning = false
        if currentIndex < stories.count - 1 {
            withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : Motion.liquidSpring) {
                currentIndex += 1
            }
            startTimer()
        } else {
            dismiss()
        }
    }

    private func goToPrevious() {
        isTimerRunning = false
        if currentIndex > 0 {
            withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : Motion.liquidSpring) {
                currentIndex -= 1
            }
            startTimer()
        } else {
            // Restart the current story.
            startTimer()
        }
    }

    // MARK: - Reaction persistence

    private func sendReaction(kind: SelahReactionKind, storyId: String, reacted: Bool) async {
        // Writes to selahStories/{storyId}/reactions/{uid} in Firestore.
        // Author-private: Firestore security rules enforce that only ownerUid can read
        // the reactions sub-collection.
        guard let uid = FirebaseAuth.Auth.auth().currentUser?.uid else { return }
        let db = Firestore.firestore()
        let ref = db
            .collection("selahStories").document(storyId)
            .collection("reactions").document(uid)

        do {
            if reacted {
                try await ref.setData([
                    "reactorUid": uid,
                    "kind": kind.rawValue,
                    "createdAt": FieldValue.serverTimestamp()
                ])
            } else {
                try await ref.delete()
            }
        } catch {
            // Reaction writes are best-effort — don't surface an alert for this.
        }
    }
}

// MARK: - SelahReactionKind Display Helpers

extension SelahReactionKind {
    /// SF Symbol name for this reaction.
    var icon: String {
        switch self {
        case .amen:    return "hands.raised"
        case .praying: return "hands.sparkles"
        }
    }

    /// The display label shown on the reaction button.
    var displayLabel: String {
        switch self {
        case .amen:    return "Amen"
        case .praying: return "Praying"
        }
    }

    /// Accent color for the active (reacted) state.
    var activeColor: Color {
        switch self {
        case .amen:    return AmenTheme.Colors.amenGold
        case .praying: return AmenTheme.Colors.amenPurple
        }
    }

    /// Short confirmation message shown in the toast when a user reacts.
    var toastMessage: String {
        switch self {
        case .amen:    return "Amen!"
        case .praying: return "Praying"
        }
    }
}

// MARK: - Firestore import shim (used inside the view)
// SelahStoryViewerView calls Firestore directly for reaction persistence.
// Import is already provided transitively through SelahStoryService.swift
// which is in the same module. Re-importing here is safe.
import FirebaseFirestore
import FirebaseAuth
