// VisibilityPlaybackManager.swift
// AMENAPP
//
// Feed viewport logic for video autoplay: plays when >70% visible,
// pauses when leaving, enforces single-video-at-a-time.

import SwiftUI

@MainActor
final class VisibilityPlaybackManager: ObservableObject {

    static let shared = VisibilityPlaybackManager()

    @Published private(set) var activeVideoKey: String?

    let visibilityThreshold: CGFloat = 0.70

    private init() {}

    // MARK: - Visibility Reporting

    func reportVisibility(
        postId: String,
        mediaItemId: String,
        visibleFraction: CGFloat,
        play: () -> Void,
        pause: () -> Void
    ) {
        let key = "\(postId)_\(mediaItemId)"

        if visibleFraction >= visibilityThreshold {
            if activeVideoKey != key {
                activeVideoKey = key
            }
            play()
        } else if activeVideoKey == key {
            pause()
            activeVideoKey = nil
        }
    }

    func pauseAll() {
        activeVideoKey = nil
    }
}
