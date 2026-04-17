// MediaPlaybackState.swift
// AMENAPP
//
// Model for tracking video playback position across surfaces.
// Used by MediaSessionCoordinator for resume-from-where-you-left-off.

import Foundation

struct MediaPlaybackState: Codable, Identifiable {
    /// Composite ID: "{postId}_{mediaItemId}"
    var id: String { "\(postId)_\(mediaItemId)" }

    let postId: String
    let mediaItemId: String
    var positionSeconds: Double
    var durationSeconds: Double
    var completed: Bool
    var lastPlayedAt: Date

    /// Progress fraction (0–1.0) for UI display.
    var progress: Double {
        guard durationSeconds > 0 else { return 0 }
        return min(1.0, positionSeconds / durationSeconds)
    }

    /// Whether there's a meaningful position to resume from.
    /// Skip if < 3 seconds in or > 95% done.
    var isResumable: Bool {
        !completed && positionSeconds >= 3.0 && progress < 0.95
    }

    /// Formatted time string for the resume pill (e.g. "0:43", "1:22:05").
    var formattedPosition: String {
        let total = Int(positionSeconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    // MARK: - Firestore Key

    /// Document ID for Firestore: `users/{uid}/mediaResumeState/{compositeId}`
    var firestoreDocId: String { id }
}

// MARK: - Active Video Session

/// Represents the currently active video playback session.
/// Only one video can be active at a time.
enum MediaSurface: String, Codable {
    case feed
    case detail
    case fullscreen
}
