// AmenLyricsSyncEngine.swift
// AMENAPP
//
// Pure, side-effect-free engine for driving timed-text animations from a
// playback position (in milliseconds). Used by music lyric wipe animations,
// podcast chapter highlighting, and video caption overlays.
//
// No UI, no networking, no AVFoundation dependency — safe to unit-test directly.
//
// Usage:
//   let engine = AmenLyricsSyncEngine(timeline: attachment.timeline!)
//   let idx = engine.activeSegmentIndex(atMs: player.currentTimeMs)
//   if let (seg, chars) = engine.wordProgress(atMs: player.currentTimeMs) { … }

import Foundation

// MARK: - AmenLyricsSyncEngine

/// Stateless engine that answers positional queries against an `AmenMediaTimeline`.
/// All methods are O(log n) via binary search where possible, with linear fallbacks.
struct AmenLyricsSyncEngine: Sendable {

    let timeline: AmenMediaTimeline

    // MARK: - Active Segment

    /// Returns the index into `timeline.segments` of the segment that is active at
    /// the given `ms` timestamp, or `nil` if the timestamp is before the first
    /// segment's start or after all segments have ended.
    ///
    /// A segment is "active" when `startMs <= ms` and either `endMs` is nil (open-
    /// ended) or `ms < endMs`.
    func activeSegmentIndex(atMs ms: Int) -> Int? {
        let segments = timeline.segments
        guard !segments.isEmpty else { return nil }

        // Fast-path: before the first segment starts.
        if ms < segments[0].startMs { return nil }

        // Binary search for the last segment whose startMs <= ms.
        var lo = 0
        var hi = segments.count - 1
        var candidate = -1

        while lo <= hi {
            let mid = lo + (hi - lo) / 2
            if segments[mid].startMs <= ms {
                candidate = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }

        guard candidate >= 0 else { return nil }

        // Verify the candidate has not yet ended.
        let seg = segments[candidate]
        if let endMs = seg.endMs, ms >= endMs {
            return nil
        }
        return candidate
    }

    // MARK: - Word-Level Progress

    /// For word-synced timelines, returns the active segment index and the number
    /// of characters that should be revealed by the wipe animation at `ms`.
    ///
    /// - Returns: `(segment: Int, charsRevealed: Int)` when word timing data is
    ///   available for the active segment, or `nil` otherwise.
    func wordProgress(atMs ms: Int) -> (segment: Int, charsRevealed: Int)? {
        guard timeline.isWordSynced else { return nil }
        guard let segIdx = activeSegmentIndex(atMs: ms) else { return nil }

        let seg = timeline.segments[segIdx]
        guard let words = seg.words, !words.isEmpty else { return nil }

        // Sum characters of every word whose startMs has passed.
        // A word contributes its full text length plus a trailing space separator
        // (except the last word) to match the visual label character count.
        var revealedChars = 0
        for (wordIdx, word) in words.enumerated() {
            guard ms >= word.startMs else { break }

            if ms < word.endMs {
                // Partially inside this word: interpolate progress within it.
                let elapsed = ms - word.startMs
                let duration = max(1, word.endMs - word.startMs)
                let fraction = Double(elapsed) / Double(duration)
                let partialChars = Int((Double(word.text.count) * fraction).rounded())
                revealedChars += partialChars
                break
            } else {
                // Word has fully elapsed.
                revealedChars += word.text.count
                // Add separator space between words (not after the last word).
                if wordIdx < words.count - 1 {
                    revealedChars += 1
                }
            }
        }

        return (segment: segIdx, charsRevealed: revealedChars)
    }

    // MARK: - Chapter List

    /// Returns all segments whose kind is `.chapter` (from a podcast or video timeline).
    /// The result preserves the original segment order from the timeline.
    func chapters() -> [AmenTimedSegment] {
        guard timeline.segmentKind == .chapter else { return [] }
        return timeline.segments
    }

    // MARK: - Nearest Segment (Seek / Jump)

    /// Returns the index of the segment whose `startMs` is closest to `ms`.
    /// Ties are broken in favor of the earlier segment.
    ///
    /// Returns `nil` when the timeline has no segments.
    func nearestSegment(toMs ms: Int) -> Int? {
        let segments = timeline.segments
        guard !segments.isEmpty else { return nil }

        var bestIndex = 0
        var bestDistance = abs(segments[0].startMs - ms)

        for idx in 1 ..< segments.count {
            let distance = abs(segments[idx].startMs - ms)
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = idx
            }
        }

        return bestIndex
    }
}
