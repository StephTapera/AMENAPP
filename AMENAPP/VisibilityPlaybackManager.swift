// VisibilityPlaybackManager.swift
// AMENAPP
//
// Feed viewport logic for video autoplay: plays when >70% visible,
// pauses when leaving, enforces single-video-at-a-time.

import SwiftUI

@MainActor
final class VisibilityPlaybackManager: ObservableObject {

    static let shared = VisibilityPlaybackManager()

    /// The post ID + media item ID of the currently auto-playing video.
    @Published private(set) var activeVideoKey: String?

    /// Visibility threshold for autoplay (0–1.0).
    let visibilityThreshold: CGFloat = 0.70

    private init() {}

    // MARK: - Visibility Reporting

    /// Called by video cells as they scroll. Reports what fraction of the cell is visible.
    /// If visibility crosses the threshold, triggers play/pause.
    func reportVisibility(
        postId: String,
        mediaItemId: String,
        visibleFraction: CGFloat,
        play: () -> Void,
        pause: () -> Void
    ) {
        let key = "\(postId)_\(mediaItemId)"

        if visibleFraction >= visibilityThreshold {
            // This video should play
            if activeVideoKey != key {
                // Pause previous
                activeVideoKey = key
            }
            play()
        } else if activeVideoKey == key {
            // This video is scrolling out
            pause()
            activeVideoKey = nil
        }
    }

    /// Force-pause the current video (e.g. when navigating away from feed).
    func pauseAll() {
        activeVideoKey = nil
    }
}
