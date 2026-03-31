//
//  MediaBundleDetector.swift
//  AMENAPP
//
//  Intelligently suggests media grouping and ordering for multi-item posts.
//  Pure local heuristics based on item count, video/photo ratio, timestamps,
//  scene tags, and account type.
//
//  Design system: white background, black text (AmenColorScheme)
//  Dependencies: Foundation only.
//

import Foundation

// MARK: - BundleType

/// The detected or suggested grouping style for a multi-media post.
enum BundleType: String {
    case storySequence      = "storySequence"
    case eventRecap         = "eventRecap"
    case worshipHighlights  = "worshipHighlights"
    case sermonHighlights   = "sermonHighlights"
    case beforeAfter        = "beforeAfter"
    case behindTheScenes    = "behindTheScenes"
    case teachingCarousel   = "teachingCarousel"
    case communityMoment    = "communityMoment"
    case mixed              = "mixed"

    // MARK: Display Label

    /// Human-readable label shown in the composer bundle suggestion UI.
    var displayLabel: String {
        switch self {
        case .storySequence:     return "Story Sequence"
        case .eventRecap:        return "Event Recap"
        case .worshipHighlights: return "Worship Highlights"
        case .sermonHighlights:  return "Sermon Highlights"
        case .beforeAfter:       return "Before & After"
        case .behindTheScenes:   return "Behind the Scenes"
        case .teachingCarousel:  return "Teaching Carousel"
        case .communityMoment:   return "Community Moment"
        case .mixed:             return "Mixed Media"
        }
    }

    // MARK: Order Hint

    /// Describes the recommended ordering strategy for items in this bundle.
    var orderHint: String {
        switch self {
        case .storySequence:     return "Chronological — earliest first"
        case .eventRecap:        return "Chronological — show arrival through peak moment"
        case .worshipHighlights: return "Energy arc — quieter moments first, peak in middle"
        case .sermonHighlights:  return "Narrative — clip order mirrors message flow"
        case .beforeAfter:       return "Before first, after last"
        case .behindTheScenes:   return "Preparation first, main moment last"
        case .teachingCarousel:  return "Point 1 → Point 2 → Point 3 → Summary"
        case .communityMoment:   return "Wide group shots first, individual moments after"
        case .mixed:             return "Videos first, then photos chronologically"
        }
    }

    // MARK: Caption Template

    /// A starting-point caption template for this bundle type.
    var captionTemplate: String {
        switch self {
        case .storySequence:
            return "Here's the story in order…"
        case .eventRecap:
            return "What a night. Swipe to see how it all came together."
        case .worshipHighlights:
            return "The presence was real. These moments say it all."
        case .sermonHighlights:
            return "Clips from today's message. Which one hit home for you?"
        case .beforeAfter:
            return "Look what God did. Swipe to see the transformation."
        case .behindTheScenes:
            return "Here's what goes into making it happen."
        case .teachingCarousel:
            return "Swipe through the key points from today's teaching."
        case .communityMoment:
            return "This is what community looks like."
        case .mixed:
            return "Sharing the moment with you."
        }
    }
}

// MARK: - MediaItem

/// A single media item submitted to the bundle detector.
struct MediaItem: Identifiable {
    let id: String
    let type: MediaItemType
    /// When the media was captured, if available.
    let capturedAt: Date?
    /// Duration in seconds (video only).
    let durationSeconds: Double?
    /// Rough scene classification hint.
    /// Possible values: `"stage"`, `"outdoor"`, `"indoor"`, `"closeup"`, `"crowd"`, `"text"`, `nil`
    let estimatedScene: String?

    enum MediaItemType {
        case photo
        case video
    }
}

// MARK: - BundleDetectionResult

/// The result of a bundle detection pass.
struct BundleDetectionResult {
    /// Best-match bundle type for this collection of media.
    let suggestedType: BundleType
    /// Detection confidence 0.0–1.0.
    let confidence: Double
    /// Item IDs in the recommended display order.
    let suggestedOrder: [String]
    /// Pre-filled caption template for this bundle type.
    let captionTemplate: String
    /// `true` if the current item order differs from `suggestedOrder`.
    let reorderNeeded: Bool
}

// MARK: - MediaBundleDetector

/// Suggests media grouping and ordering for multi-item posts.
///
/// All detection is local — no network calls.
///
/// Usage:
/// ```swift
/// let result = MediaBundleDetector.shared.detect(items: mediaItems, accountType: "church")
/// // result.suggestedType, result.suggestedOrder, result.captionTemplate
/// ```
final class MediaBundleDetector {

    static let shared = MediaBundleDetector()
    private init() {}

    // MARK: - Detect

    /// Detects the best bundle type for a set of media items.
    ///
    /// Heuristic rules applied in priority order:
    /// 1. Account type signals (church admin with video → sermonHighlights, etc.)
    /// 2. Item composition (all video, all photo, mixed)
    /// 3. Scene tags (stage, crowd, indoor)
    /// 4. Temporal span (tight window → story sequence, wide → event recap)
    /// 5. Item count (2 = beforeAfter candidate, 3-5 = carousel, 6+ = recap)
    ///
    /// - Parameters:
    ///   - items: The media items the user has attached.
    ///   - accountType: `"personal"`, `"church"`, or `"business"`.
    /// - Returns: A `BundleDetectionResult` with suggestions.
    func detect(items: [MediaItem], accountType: String) -> BundleDetectionResult {
        guard !items.isEmpty else {
            return BundleDetectionResult(
                suggestedType: .mixed,
                confidence: 0.3,
                suggestedOrder: [],
                captionTemplate: BundleType.mixed.captionTemplate,
                reorderNeeded: false
            )
        }

        let photoItems = items.filter { $0.type == .photo }
        let videoItems = items.filter { $0.type == .video }
        let photoRatio = Double(photoItems.count) / Double(items.count)
        let videoRatio = Double(videoItems.count) / Double(items.count)
        let count = items.count

        let scenes = items.compactMap { $0.estimatedScene?.lowercased() }
        let hasStage  = scenes.contains("stage")
        let hasCrowd  = scenes.contains("crowd")
        let hasCloseup = scenes.contains("closeup")
        let hasTextSlide = scenes.contains("text")

        // Compute temporal span of captured media (if timestamps are available)
        let timestamps = items.compactMap { $0.capturedAt }.sorted()
        let spanSeconds: Double
        if let first = timestamps.first, let last = timestamps.last {
            spanSeconds = last.timeIntervalSince(first)
        } else {
            spanSeconds = 0
        }

        // ── Rule 1: Church / business — video-heavy + stage scene ───────────
        if accountType == "church" && videoRatio >= 0.5 && hasStage {
            let ordered = recommendedOrder(for: items, bundleType: .sermonHighlights)
            return BundleDetectionResult(
                suggestedType: .sermonHighlights,
                confidence: 0.88,
                suggestedOrder: ordered.map(\.id),
                captionTemplate: BundleType.sermonHighlights.captionTemplate,
                reorderNeeded: ordered.map(\.id) != items.map(\.id)
            )
        }

        // ── Rule 2: Church / business — photo-heavy + crowd or indoor ────────
        if (accountType == "church" || accountType == "business")
            && photoRatio >= 0.6 && (hasCrowd || scenes.contains("indoor")) {
            let bundleType: BundleType = hasCrowd ? .worshipHighlights : .eventRecap
            let ordered = recommendedOrder(for: items, bundleType: bundleType)
            return BundleDetectionResult(
                suggestedType: bundleType,
                confidence: 0.82,
                suggestedOrder: ordered.map(\.id),
                captionTemplate: bundleType.captionTemplate,
                reorderNeeded: ordered.map(\.id) != items.map(\.id)
            )
        }

        // ── Rule 3: Exactly 2 items — before/after candidate ─────────────────
        if count == 2 {
            let ordered = recommendedOrder(for: items, bundleType: .beforeAfter)
            return BundleDetectionResult(
                suggestedType: .beforeAfter,
                confidence: 0.70,
                suggestedOrder: ordered.map(\.id),
                captionTemplate: BundleType.beforeAfter.captionTemplate,
                reorderNeeded: ordered.map(\.id) != items.map(\.id)
            )
        }

        // ── Rule 4: 3-5 photos with text slides → teaching carousel ──────────
        if count >= 3 && count <= 5 && photoRatio >= 0.8 && hasTextSlide {
            let ordered = recommendedOrder(for: items, bundleType: .teachingCarousel)
            return BundleDetectionResult(
                suggestedType: .teachingCarousel,
                confidence: 0.80,
                suggestedOrder: ordered.map(\.id),
                captionTemplate: BundleType.teachingCarousel.captionTemplate,
                reorderNeeded: ordered.map(\.id) != items.map(\.id)
            )
        }

        // ── Rule 5: Tight temporal span (<15 min) → story sequence ───────────
        if spanSeconds > 0 && spanSeconds < 900 && count >= 3 {
            let ordered = recommendedOrder(for: items, bundleType: .storySequence)
            return BundleDetectionResult(
                suggestedType: .storySequence,
                confidence: 0.75,
                suggestedOrder: ordered.map(\.id),
                captionTemplate: BundleType.storySequence.captionTemplate,
                reorderNeeded: ordered.map(\.id) != items.map(\.id)
            )
        }

        // ── Rule 6: Wide temporal span (>2 h) + many items → event recap ──────
        if spanSeconds > 7200 || count >= 6 {
            let ordered = recommendedOrder(for: items, bundleType: .eventRecap)
            return BundleDetectionResult(
                suggestedType: .eventRecap,
                confidence: 0.72,
                suggestedOrder: ordered.map(\.id),
                captionTemplate: BundleType.eventRecap.captionTemplate,
                reorderNeeded: ordered.map(\.id) != items.map(\.id)
            )
        }

        // ── Rule 7: Personal account + closeup + video → behind the scenes ────
        if accountType == "personal" && hasCloseup && videoRatio > 0 {
            let ordered = recommendedOrder(for: items, bundleType: .behindTheScenes)
            return BundleDetectionResult(
                suggestedType: .behindTheScenes,
                confidence: 0.65,
                suggestedOrder: ordered.map(\.id),
                captionTemplate: BundleType.behindTheScenes.captionTemplate,
                reorderNeeded: ordered.map(\.id) != items.map(\.id)
            )
        }

        // ── Rule 8: Photos with crowd or indoor scenes → community moment ─────
        if photoRatio >= 0.7 && (hasCrowd || scenes.contains("indoor")) {
            let ordered = recommendedOrder(for: items, bundleType: .communityMoment)
            return BundleDetectionResult(
                suggestedType: .communityMoment,
                confidence: 0.60,
                suggestedOrder: ordered.map(\.id),
                captionTemplate: BundleType.communityMoment.captionTemplate,
                reorderNeeded: ordered.map(\.id) != items.map(\.id)
            )
        }

        // ── Fallback: mixed ────────────────────────────────────────────────────
        let ordered = recommendedOrder(for: items, bundleType: .mixed)
        return BundleDetectionResult(
            suggestedType: .mixed,
            confidence: 0.40,
            suggestedOrder: ordered.map(\.id),
            captionTemplate: BundleType.mixed.captionTemplate,
            reorderNeeded: ordered.map(\.id) != items.map(\.id)
        )
    }

    // MARK: - Caption Suggestion

    /// Generates a contextual caption template based on bundle type and post intent.
    ///
    /// Combines the bundle's template with intent-specific language when there's
    /// a strong pairing (e.g., sermonHighlights + sermonClip intent).
    ///
    /// - Parameters:
    ///   - bundle: The detected or user-selected bundle type.
    ///   - postIntent: The detected post intent from `PostIntentDetector`.
    func suggestCaption(for bundle: BundleType, postIntent: PostIntent) -> String {
        switch (bundle, postIntent) {
        case (.sermonHighlights, .sermonClip):
            return "Clips from today's message. Which moment spoke to you? Full sermon in bio."
        case (.sermonHighlights, .teaching):
            return "Breaking down the key points. Swipe through and follow along."
        case (.worshipHighlights, .testimony):
            return "The Spirit moved. These moments capture what happened."
        case (.eventRecap, .eventRecap):
            return "Look back at everything God did. What a night."
        case (.eventRecap, .announcement):
            return "We did it. Thank you to everyone who came out."
        case (.teachingCarousel, .teaching):
            return "Swipe through today's teaching points. Save this for your notes."
        case (.teachingCarousel, .resource):
            return "Key takeaways in carousel form. Share with someone who needs it."
        case (.communityMoment, .gratitude):
            return "Grateful for every face in these photos. This is community."
        case (.beforeAfter, .testimony):
            return "Swipe to see what God did. Before → After."
        case (.storySequence, .missionUpdate):
            return "Follow the thread. Here's how the day unfolded on the ground."
        case (.behindTheScenes, .missionUpdate):
            return "The work behind the scenes. This is what it takes."
        default:
            return bundle.captionTemplate
        }
    }

    // MARK: - Ordering

    /// Returns items in the recommended display order for a given bundle type.
    ///
    /// Ordering strategies:
    /// - `storySequence` / `eventRecap`: Chronological by `capturedAt`.
    /// - `beforeAfter`: Earlier timestamp first.
    /// - `sermonHighlights`: Videos before photos; within videos, shortest first
    ///   (allows a quick hook clip to lead).
    /// - `worshipHighlights`: Photos first (atmosphere), then videos (peak moments).
    /// - `teachingCarousel`: Text slides before non-text; otherwise preserve user order.
    /// - `communityMoment`: Group/crowd shots before closeups.
    /// - `mixed` / others: Videos first, then photos chronologically.
    ///
    /// Items without a `capturedAt` timestamp retain their original relative order.
    func recommendedOrder(for items: [MediaItem], bundleType: BundleType) -> [MediaItem] {
        switch bundleType {

        case .storySequence, .eventRecap, .beforeAfter:
            return items.sorted { lhs, rhs in
                switch (lhs.capturedAt, rhs.capturedAt) {
                case let (l?, r?): return l < r
                default: return false
                }
            }

        case .sermonHighlights:
            // Short video clips first (hook), then longer clips, then photos
            return items.sorted { lhs, rhs in
                if lhs.type == .video && rhs.type == .photo { return true }
                if lhs.type == .photo && rhs.type == .video { return false }
                if lhs.type == .video && rhs.type == .video {
                    let ld = lhs.durationSeconds ?? .greatestFiniteMagnitude
                    let rd = rhs.durationSeconds ?? .greatestFiniteMagnitude
                    return ld < rd
                }
                // Both photos — chronological
                switch (lhs.capturedAt, rhs.capturedAt) {
                case let (l?, r?): return l < r
                default: return false
                }
            }

        case .worshipHighlights:
            // Photos first (ambient/atmosphere), then videos (peak moments)
            return items.sorted { lhs, rhs in
                if lhs.type == .photo && rhs.type == .video { return true }
                if lhs.type == .video && rhs.type == .photo { return false }
                switch (lhs.capturedAt, rhs.capturedAt) {
                case let (l?, r?): return l < r
                default: return false
                }
            }

        case .teachingCarousel:
            // Text slides before photos/videos; otherwise chronological
            return items.sorted { lhs, rhs in
                let lIsText = lhs.estimatedScene?.lowercased() == "text"
                let rIsText = rhs.estimatedScene?.lowercased() == "text"
                if lIsText && !rIsText { return true }
                if !lIsText && rIsText { return false }
                switch (lhs.capturedAt, rhs.capturedAt) {
                case let (l?, r?): return l < r
                default: return false
                }
            }

        case .communityMoment:
            // Crowd/group shots before closeups
            return items.sorted { lhs, rhs in
                let lIsCrowd = lhs.estimatedScene?.lowercased() == "crowd"
                let rIsCrowd = rhs.estimatedScene?.lowercased() == "crowd"
                if lIsCrowd && !rIsCrowd { return true }
                if !lIsCrowd && rIsCrowd { return false }
                switch (lhs.capturedAt, rhs.capturedAt) {
                case let (l?, r?): return l < r
                default: return false
                }
            }

        case .behindTheScenes:
            // Preserve user order — behind-the-scenes is intentionally curated
            return items

        case .mixed:
            // Videos first, then photos, each group chronological
            let videos = items
                .filter { $0.type == .video }
                .sorted { ($0.capturedAt ?? .distantPast) < ($1.capturedAt ?? .distantPast) }
            let photos = items
                .filter { $0.type == .photo }
                .sorted { ($0.capturedAt ?? .distantPast) < ($1.capturedAt ?? .distantPast) }
            return videos + photos
        }
    }
}
