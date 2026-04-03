//
//  AMENShareCardSystem.swift
//  AMENAPP
//
//  Premium branded external share cards for AMEN.
//  When a user shares a post to Instagram Stories, iMessage, WhatsApp, or
//  any app, the output is a beautifully branded AMEN share card — not a
//  generic screenshot. The AMEN identity is present on every card but
//  feels like a luxury signature, not a watermark.
//
//  Design philosophy: white base · black typography · subtle grayscale
//  layering · Liquid Glass translucent panels · soft depth · spacious
//  editorial composition — "luxury minimal".
//
//  Card target size: 390 × 693 pt (1080×1920 story ratio).
//  Export: ImageRenderer at @3x → 1170 × 2079 px.
//
//  Dependencies: SwiftUI, UIKit, Foundation only. No Firebase.
//  Requires iOS 16+ for ImageRenderer.
//

import Foundation
import SwiftUI
import Combine
import UIKit

// MARK: - Glass Style Constants

private enum ShareGlass {
    /// Standard liquid-glass background: ultra-thin material + white wash + hairline border.
    static func capsuleBackground() -> some View {
        Capsule()
            .fill(.ultraThinMaterial)
            .overlay(Capsule().fill(Color.white.opacity(0.55)))
            .overlay(Capsule().strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5))
    }

    static func roundedBackground(radius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Color.white.opacity(0.55)))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5))
    }

    static func circleBackground() -> some View {
        Circle()
            .fill(.ultraThinMaterial)
            .overlay(Circle().fill(Color.white.opacity(0.55)))
            .overlay(Circle().strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5))
    }
}

// MARK: - Card Dimensions

private enum ShareCardDimensions {
    static let width: CGFloat  = 390
    static let height: CGFloat = 693
    static let horizontalPad: CGFloat = 28
    static let topPad: CGFloat = 36
    static let bottomPad: CGFloat = 28
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - Part 1 · Data Models
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

enum AMENSharePostType: String {
    case text
    case photo
    case video
    case carousel
    case testimony
    case prayer
    case verse
    case churchNote
    case announcement

    var displayLabel: String {
        switch self {
        case .text:         return "Post"
        case .photo:        return "Photo"
        case .video:        return "Video"
        case .carousel:     return "Carousel"
        case .testimony:    return "Testimony"
        case .prayer:       return "Prayer"
        case .verse:        return "Verse"
        case .churchNote:   return "Church Note"
        case .announcement: return "Announcement"
        }
    }

    var icon: String {
        switch self {
        case .text:         return "text.bubble"
        case .photo:        return "photo"
        case .video:        return "video"
        case .carousel:     return "rectangle.stack"
        case .testimony:    return "person.wave.2"
        case .prayer:       return "hands.sparkles"
        case .verse:        return "book"
        case .churchNote:   return "book.fill"
        case .announcement: return "megaphone"
        }
    }
}

struct AMENSharePayload {
    let postType: AMENSharePostType
    let authorName: String
    let authorInitials: String
    let captionText: String
    let verseReference: String?
    let categoryLabel: String?
    let imageData: Data?
    let thumbnailData: Data?
    let churchName: String?
    let timestamp: Date
    let deepLinkURL: String
    /// Optional carousel page count
    var carouselCount: Int = 1
    /// Optional video duration string e.g. "1:24"
    var videoDuration: String?
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - Part 5 · AMENBrandedWatermark  (defined early — used by all cards)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct AMENBrandedWatermark: View {

    enum Style {
        /// Horizontal tracked small-caps line at top of card
        case topMark
        /// Small square glass pill for top-right corner overlay
        case cornerStamp
        /// Full glass pill "AMEN · amen.community" — default bottom signature
        case bottomSignature
        /// Rotated 90° vertical seal for verse cards
        case verticalSeal
    }

    var style: Style = .bottomSignature

    var body: some View {
        switch style {
        case .topMark:
            topMarkView
        case .cornerStamp:
            cornerStampView
        case .bottomSignature:
            bottomSignatureView
        case .verticalSeal:
            verticalSealView
        }
    }

    // "A M E N" tracked small caps horizontal
    private var topMarkView: some View {
        Text("A M E N")
            .font(AMENFont.semiBold(11))
            .foregroundColor(Color(white: 0.50))
            .tracking(4.0)
    }

    // Small square glass pill — top-right
    private var cornerStampView: some View {
        HStack(spacing: 4) {
            Image(systemName: "seal.fill")
                .font(.systemScaled(9, weight: .bold))
                .foregroundColor(.black.opacity(0.7))
            Text("AMEN")
                .font(AMENFont.bold(10))
                .foregroundColor(.black)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(ShareGlass.capsuleBackground())
    }

    // Full glass pill "AMEN · amen.community"
    private var bottomSignatureView: some View {
        HStack(spacing: 6) {
            Image(systemName: "seal.fill")
                .font(.systemScaled(12, weight: .bold))
                .foregroundColor(.black)
            Text("AMEN")
                .font(AMENFont.bold(13))
                .foregroundColor(.black)
            Text("·")
                .font(AMENFont.regular(13))
                .foregroundColor(Color(white: 0.60))
            Text("amen.community")
                .font(AMENFont.regular(12))
                .foregroundColor(Color(white: 0.50))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(ShareGlass.capsuleBackground())
    }

    // "A M E N" rotated 90° — very subtle
    private var verticalSealView: some View {
        Text("A M E N")
            .font(AMENFont.semiBold(10))
            .foregroundColor(Color(white: 0.75))
            .tracking(4.0)
            .rotationEffect(.degrees(-90))
            .fixedSize()
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - Part 4 · AMENDeepLinkStrip
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct AMENDeepLinkStrip: View {
    var deepLinkURL: String = "amen://feed"

    var body: some View {
        VStack(spacing: 6) {
            Text("Join the conversation")
                .font(AMENFont.regular(12))
                .foregroundColor(Color(white: 0.55))
            AMENBrandedWatermark(style: .bottomSignature)
        }
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - Shared Sub-components
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Author row used across multiple card types.
private struct ShareAuthorRow: View {
    let authorName: String
    let authorInitials: String
    var subtitleOverride: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            // Initials circle
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(Circle().fill(Color.white.opacity(0.55)))
                    .overlay(Circle().strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5))
                    .frame(width: 36, height: 36)
                Text(authorInitials)
                    .font(AMENFont.semiBold(13))
                    .foregroundColor(.black.opacity(0.75))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(authorName)
                    .font(AMENFont.semiBold(14))
                    .foregroundColor(.black)
                Text(subtitleOverride ?? "on AMEN")
                    .font(AMENFont.regular(12))
                    .foregroundColor(Color(white: 0.55))
            }

            Spacer()
        }
    }
}

/// Generic post-type pill label.
private struct PostTypePill: View {
    let label: String
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.systemScaled(10, weight: .medium))
                    .foregroundColor(Color(white: 0.45))
            }
            Text(label)
                .font(AMENFont.semiBold(11))
                .foregroundColor(Color(white: 0.45))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(ShareGlass.capsuleBackground())
    }
}

/// Thin hairline rule.
private struct HairlineRule: View {
    var body: some View {
        Rectangle()
            .fill(Color(white: 0.88))
            .frame(height: 0.5)
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - Part 2 · Share Card Views
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

// MARK: AMENTextShareCard

/// For text-only posts: openTable, general, announcement.
struct AMENTextShareCard: View {
    let payload: AMENSharePayload

    private let W = ShareCardDimensions.width
    private let H = ShareCardDimensions.height
    private let hPad = ShareCardDimensions.horizontalPad

    var body: some View {
        ZStack {
            Color.white
                .frame(width: W, height: H)

            VStack(alignment: .leading, spacing: 0) {

                // ── TOP: AMEN signature mark + post type pill ──────────
                HStack(alignment: .center) {
                    AMENBrandedWatermark(style: .topMark)
                    Spacer()
                    PostTypePill(
                        label: payload.categoryLabel ?? payload.postType.displayLabel,
                        icon: payload.postType.icon
                    )
                }
                .padding(.horizontal, hPad)
                .padding(.top, ShareCardDimensions.topPad)

                Spacer()

                // ── CONTENT ZONE — center-weighted ─────────────────────
                VStack(alignment: .leading, spacing: 20) {
                    HairlineRule()

                    Text(payload.captionText)
                        .font(AMENFont.regular(22))
                        .foregroundColor(.black)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(6)
                        .lineLimit(12)
                        .fixedSize(horizontal: false, vertical: true)

                    HairlineRule()

                    ShareAuthorRow(
                        authorName: payload.authorName,
                        authorInitials: payload.authorInitials
                    )
                }
                .padding(.horizontal, hPad)

                Spacer()

                // ── BOTTOM: CTA strip ───────────────────────────────────
                VStack(spacing: 8) {
                    AMENDeepLinkStrip(deepLinkURL: payload.deepLinkURL)
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, ShareCardDimensions.bottomPad)
            }
        }
        .frame(width: W, height: H)
        .clipped()
    }
}

// MARK: AMENTestimonyShareCard

/// Elevated, sacred tone for Testimony posts.
struct AMENTestimonyShareCard: View {
    let payload: AMENSharePayload

    private let W = ShareCardDimensions.width
    private let H = ShareCardDimensions.height
    private let hPad = ShareCardDimensions.horizontalPad

    var body: some View {
        ZStack {
            Color.white
                .frame(width: W, height: H)

            VStack(spacing: 0) {

                // ── TOP ────────────────────────────────────────────────
                HStack {
                    AMENBrandedWatermark(style: .topMark)
                    Spacer()
                    PostTypePill(label: "Testimony", icon: "person.wave.2")
                }
                .padding(.horizontal, hPad)
                .padding(.top, ShareCardDimensions.topPad)

                Spacer()

                // ── CONTENT ZONE ───────────────────────────────────────
                VStack(alignment: .center, spacing: 16) {
                    // Opening quotation mark
                    Text("\u{275D}")
                        .font(.systemScaled(52, weight: .ultraLight))
                        .foregroundColor(Color(white: 0.82))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, hPad)

                    Text(payload.captionText)
                        .font(AMENFont.regular(20))
                        .foregroundColor(.black)
                        .multilineTextAlignment(.center)
                        .lineSpacing(7)
                        .lineLimit(12)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, hPad)

                    // Closing quotation mark
                    Text("\u{275E}")
                        .font(.systemScaled(52, weight: .ultraLight))
                        .foregroundColor(Color(white: 0.82))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.horizontal, hPad)
                }

                Spacer()

                // ── AUTHOR + RULE ──────────────────────────────────────
                VStack(spacing: 14) {
                    HairlineRule()
                        .padding(.horizontal, hPad)

                    ShareAuthorRow(
                        authorName: payload.authorName,
                        authorInitials: payload.authorInitials
                    )
                    .padding(.horizontal, hPad)
                }

                Spacer(minLength: 20)

                // ── BOTTOM SEAL ────────────────────────────────────────
                VStack(spacing: 4) {
                    Text("View on AMEN")
                        .font(AMENFont.regular(12))
                        .foregroundColor(Color(white: 0.55))

                    Text("\u{2736} AMEN")
                        .font(AMENFont.semiBold(11))
                        .foregroundColor(Color(white: 0.50))
                        .tracking(3.5)
                }
                .padding(.bottom, ShareCardDimensions.bottomPad)
            }
        }
        .frame(width: W, height: H)
        .clipped()
    }
}

// MARK: AMENPrayerShareCard

/// Intimate, reverent tone for Prayer posts.
struct AMENPrayerShareCard: View {
    let payload: AMENSharePayload

    private let W = ShareCardDimensions.width
    private let H = ShareCardDimensions.height
    private let hPad = ShareCardDimensions.horizontalPad

    var body: some View {
        ZStack {
            // Very subtle warm tint
            Color(red: 0.99, green: 0.98, blue: 0.96)
                .frame(width: W, height: H)

            VStack(spacing: 0) {

                // ── TOP ────────────────────────────────────────────────
                HStack {
                    AMENBrandedWatermark(style: .topMark)
                    Spacer()
                    PostTypePill(label: "Prayer", icon: "hands.sparkles")
                }
                .padding(.horizontal, hPad)
                .padding(.top, ShareCardDimensions.topPad)

                Spacer()

                // ── CONTENT ZONE ───────────────────────────────────────
                VStack(spacing: 20) {
                    Image(systemName: "hands.sparkles")
                        .font(.systemScaled(32, weight: .light))
                        .foregroundColor(Color(white: 0.45))

                    Text(payload.captionText)
                        .font(AMENFont.regular(18))
                        .foregroundColor(.black)
                        .multilineTextAlignment(.center)
                        .lineSpacing(7)
                        .lineLimit(10)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, hPad)
                }

                Spacer()

                // ── AUTHOR ROW (small, bottom-left) ───────────────────
                ShareAuthorRow(
                    authorName: payload.authorName,
                    authorInitials: payload.authorInitials
                )
                .padding(.horizontal, hPad)

                Spacer(minLength: 16)

                // ── BOTTOM SEAL ────────────────────────────────────────
                Text("Lifted in prayer on AMEN")
                    .font(AMENFont.regular(11))
                    .foregroundColor(Color(white: 0.50))
                    .tracking(1.5)
                    .padding(.bottom, ShareCardDimensions.bottomPad)
            }
        }
        .frame(width: W, height: H)
        .clipped()
    }
}

// MARK: AMENVerseShareCard

/// Editorial, beautiful layout for Verse / Scripture posts.
struct AMENVerseShareCard: View {
    let payload: AMENSharePayload

    private let W = ShareCardDimensions.width
    private let H = ShareCardDimensions.height
    private let hPad = ShareCardDimensions.horizontalPad

    var body: some View {
        ZStack {
            Color.white
                .frame(width: W, height: H)

            // Subtle dot-grid texture
            Canvas { context, size in
                let spacing: CGFloat = 24
                let dotRadius: CGFloat = 0.5
                var x: CGFloat = spacing
                while x < size.width {
                    var y: CGFloat = spacing
                    while y < size.height {
                        let rect = CGRect(x: x - dotRadius, y: y - dotRadius,
                                         width: dotRadius * 2, height: dotRadius * 2)
                        context.fill(Path(ellipseIn: rect), with: .color(Color(white: 0.94)))
                        y += spacing
                    }
                    x += spacing
                }
            }
            .frame(width: W, height: H)
            .allowsHitTesting(false)

            // TOP-RIGHT vertical "A M E N" seal
            VStack {
                HStack {
                    Spacer()
                    AMENBrandedWatermark(style: .verticalSeal)
                        .padding(.top, 60)
                        .padding(.trailing, 16)
                }
                Spacer()
            }
            .frame(width: W, height: H)
            .allowsHitTesting(false)

            // Main content column
            VStack(spacing: 0) {
                Spacer()

                // Large open-quote
                Text("\u{201C}")
                    .font(.systemScaled(64, weight: .thin))
                    .foregroundColor(Color(white: 0.82))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, hPad)

                Spacer(minLength: 4)

                // Verse text
                Text(payload.captionText)
                    .font(AMENFont.regular(24))
                    .foregroundColor(.black)
                    .multilineTextAlignment(.center)
                    .lineSpacing(8)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, hPad + 8)

                Spacer(minLength: 16)

                // Verse reference
                if let ref = payload.verseReference {
                    Text(ref)
                        .font(AMENFont.semiBold(14))
                        .foregroundColor(Color(white: 0.45))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, hPad)
                }

                Spacer()

                // Bottom rule + CTA
                VStack(spacing: 10) {
                    HairlineRule()
                        .padding(.horizontal, hPad)

                    Text("Explore Scripture on AMEN")
                        .font(AMENFont.regular(12))
                        .foregroundColor(Color(white: 0.50))

                    AMENBrandedWatermark(style: .bottomSignature)
                }
                .padding(.bottom, ShareCardDimensions.bottomPad)
            }
            .frame(width: W, height: H)
        }
        .frame(width: W, height: H)
        .clipped()
    }
}

// MARK: AMENPhotoShareCard

/// For photo posts — full-bleed image top, white content zone below.
struct AMENPhotoShareCard: View {
    let payload: AMENSharePayload

    private let W = ShareCardDimensions.width
    private let H = ShareCardDimensions.height
    private let hPad = ShareCardDimensions.horizontalPad
    private let photoHeight: CGFloat = 420
    private let whiteZoneHeight: CGFloat = 273

    var body: some View {
        ZStack(alignment: .top) {
            Color.white
                .frame(width: W, height: H)

            VStack(spacing: 0) {

                // ── PHOTO ZONE ─────────────────────────────────────────
                ZStack(alignment: .bottom) {
                    if let data = payload.imageData, let uiImage = UIImage(data: data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: W, height: photoHeight)
                            .clipped()
                    } else {
                        // Placeholder gradient
                        LinearGradient(
                            colors: [Color(white: 0.92), Color(white: 0.85)],
                            startPoint: .top, endPoint: .bottom
                        )
                        .frame(width: W, height: photoHeight)
                    }

                    // Subtle bottom vignette
                    LinearGradient(
                        colors: [.clear, Color.black.opacity(0.25)],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 100)
                }
                .frame(width: W, height: photoHeight)
                .overlay(
                    // AMEN corner stamp top-right
                    VStack {
                        HStack {
                            Spacer()
                            AMENBrandedWatermark(style: .cornerStamp)
                                .padding(.top, 16)
                                .padding(.trailing, 16)
                        }
                        Spacer()
                    }
                )

                // ── WHITE CONTENT ZONE ─────────────────────────────────
                VStack(alignment: .leading, spacing: 14) {
                    if !payload.captionText.isEmpty {
                        Text(payload.captionText)
                            .font(AMENFont.regular(16))
                            .foregroundColor(.black)
                            .multilineTextAlignment(.leading)
                            .lineSpacing(5)
                            .lineLimit(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    ShareAuthorRow(
                        authorName: payload.authorName,
                        authorInitials: payload.authorInitials
                    )

                    Spacer()

                    HairlineRule()

                    AMENDeepLinkStrip(deepLinkURL: payload.deepLinkURL)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, hPad)
                .padding(.top, 20)
                .padding(.bottom, ShareCardDimensions.bottomPad)
                .frame(width: W, height: whiteZoneHeight)
            }
        }
        .frame(width: W, height: H)
        .clipped()
    }
}

// MARK: AMENVideoShareCard

/// Poster-style card for video posts.
struct AMENVideoShareCard: View {
    let payload: AMENSharePayload

    private let W = ShareCardDimensions.width
    private let H = ShareCardDimensions.height
    private let hPad = ShareCardDimensions.horizontalPad
    private let videoZoneHeight: CGFloat = 420
    private let whiteZoneHeight: CGFloat = 273

    var body: some View {
        ZStack(alignment: .top) {
            Color.white
                .frame(width: W, height: H)

            VStack(spacing: 0) {

                // ── VIDEO ZONE ─────────────────────────────────────────
                ZStack {
                    // Thumbnail or placeholder
                    if let data = payload.thumbnailData, let uiImage = UIImage(data: data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: W, height: videoZoneHeight)
                            .clipped()
                    } else {
                        LinearGradient(
                            colors: [Color(white: 0.92), Color(white: 0.85)],
                            startPoint: .top, endPoint: .bottom
                        )
                        .frame(width: W, height: videoZoneHeight)
                    }

                    // Bottom vignette
                    VStack {
                        Spacer()
                        LinearGradient(
                            colors: [.clear, Color.black.opacity(0.25)],
                            startPoint: .top, endPoint: .bottom
                        )
                        .frame(height: 100)
                    }

                    // Centered play button
                    ZStack {
                        ShareGlass.circleBackground()
                            .frame(width: 60, height: 60)
                        Image(systemName: "play.fill")
                            .font(.systemScaled(22, weight: .medium))
                            .foregroundColor(.black.opacity(0.75))
                            .offset(x: 2)
                    }

                    // Duration pill — bottom-left
                    VStack {
                        Spacer()
                        HStack {
                            if let duration = payload.videoDuration {
                                HStack(spacing: 5) {
                                    Image(systemName: "video")
                                        .font(.systemScaled(10, weight: .medium))
                                        .foregroundColor(Color(white: 0.40))
                                    Text("Video · \(duration)")
                                        .font(AMENFont.semiBold(11))
                                        .foregroundColor(Color(white: 0.40))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(ShareGlass.capsuleBackground())
                                .padding(.leading, 16)
                                .padding(.bottom, 14)
                            }
                            Spacer()
                        }
                    }

                    // AMEN corner stamp
                    VStack {
                        HStack {
                            Spacer()
                            AMENBrandedWatermark(style: .cornerStamp)
                                .padding(.top, 16)
                                .padding(.trailing, 16)
                        }
                        Spacer()
                    }
                }
                .frame(width: W, height: videoZoneHeight)

                // ── WHITE CONTENT ZONE ─────────────────────────────────
                VStack(alignment: .leading, spacing: 14) {
                    if !payload.captionText.isEmpty {
                        Text(payload.captionText)
                            .font(AMENFont.regular(16))
                            .foregroundColor(.black)
                            .multilineTextAlignment(.leading)
                            .lineSpacing(5)
                            .lineLimit(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    ShareAuthorRow(
                        authorName: payload.authorName,
                        authorInitials: payload.authorInitials
                    )

                    Spacer()

                    HairlineRule()

                    AMENDeepLinkStrip(deepLinkURL: payload.deepLinkURL)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, hPad)
                .padding(.top, 20)
                .padding(.bottom, ShareCardDimensions.bottomPad)
                .frame(width: W, height: whiteZoneHeight)
            }
        }
        .frame(width: W, height: H)
        .clipped()
    }
}

// MARK: AMENCarouselShareCard

/// Shows first image (or gradient placeholder), count pill, caption, signature.
struct AMENCarouselShareCard: View {
    let payload: AMENSharePayload

    private let W = ShareCardDimensions.width
    private let H = ShareCardDimensions.height
    private let hPad = ShareCardDimensions.horizontalPad
    private let imageZoneHeight: CGFloat = 420
    private let whiteZoneHeight: CGFloat = 273

    var body: some View {
        ZStack(alignment: .top) {
            Color.white
                .frame(width: W, height: H)

            VStack(spacing: 0) {

                // ── IMAGE ZONE ─────────────────────────────────────────
                ZStack {
                    if let data = payload.imageData, let uiImage = UIImage(data: data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: W, height: imageZoneHeight)
                            .clipped()
                    } else {
                        LinearGradient(
                            colors: [Color(white: 0.92), Color(white: 0.85)],
                            startPoint: .top, endPoint: .bottom
                        )
                        .frame(width: W, height: imageZoneHeight)
                    }

                    VStack {
                        Spacer()
                        LinearGradient(
                            colors: [.clear, Color.black.opacity(0.20)],
                            startPoint: .top, endPoint: .bottom
                        )
                        .frame(height: 80)
                    }

                    // Count pill — bottom-right
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            HStack(spacing: 5) {
                                Text("1 of \(payload.carouselCount)")
                                    .font(AMENFont.semiBold(11))
                                    .foregroundColor(Color(white: 0.40))
                                Text("·")
                                    .foregroundColor(Color(white: 0.55))
                                Image(systemName: payload.postType.icon)
                                    .font(.systemScaled(10, weight: .medium))
                                    .foregroundColor(Color(white: 0.40))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(ShareGlass.capsuleBackground())
                            .padding(.trailing, 16)
                            .padding(.bottom, 14)
                        }
                    }

                    // AMEN corner stamp
                    VStack {
                        HStack {
                            Spacer()
                            AMENBrandedWatermark(style: .cornerStamp)
                                .padding(.top, 16)
                                .padding(.trailing, 16)
                        }
                        Spacer()
                    }
                }
                .frame(width: W, height: imageZoneHeight)

                // ── WHITE CONTENT ZONE ─────────────────────────────────
                VStack(alignment: .leading, spacing: 14) {
                    if !payload.captionText.isEmpty {
                        Text(payload.captionText)
                            .font(AMENFont.regular(16))
                            .foregroundColor(.black)
                            .multilineTextAlignment(.leading)
                            .lineSpacing(5)
                            .lineLimit(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    ShareAuthorRow(
                        authorName: payload.authorName,
                        authorInitials: payload.authorInitials
                    )

                    Spacer()

                    HairlineRule()

                    AMENDeepLinkStrip(deepLinkURL: payload.deepLinkURL)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, hPad)
                .padding(.top, 20)
                .padding(.bottom, ShareCardDimensions.bottomPad)
                .frame(width: W, height: whiteZoneHeight)
            }
        }
        .frame(width: W, height: H)
        .clipped()
    }
}

// MARK: AMENChurchNoteShareCard

/// For shared church notes — glass card-within-card layout.
struct AMENChurchNoteShareCard: View {
    let payload: AMENSharePayload

    private let W = ShareCardDimensions.width
    private let H = ShareCardDimensions.height
    private let hPad = ShareCardDimensions.horizontalPad

    var body: some View {
        ZStack {
            Color.white
                .frame(width: W, height: H)

            VStack(spacing: 0) {

                // ── TOP: church name + pill ────────────────────────────
                HStack {
                    if let church = payload.churchName {
                        VStack(alignment: .leading, spacing: 2) {
                            AMENBrandedWatermark(style: .topMark)
                            Text(church)
                                .font(AMENFont.semiBold(13))
                                .foregroundColor(.black)
                        }
                    } else {
                        AMENBrandedWatermark(style: .topMark)
                    }
                    Spacer()
                    PostTypePill(label: "Church Notes", icon: "book.fill")
                }
                .padding(.horizontal, hPad)
                .padding(.top, ShareCardDimensions.topPad)

                Spacer()

                // ── GLASS NOTE CARD ────────────────────────────────────
                VStack(alignment: .leading, spacing: 14) {
                    Image(systemName: "book.fill")
                        .font(.systemScaled(20, weight: .regular))
                        .foregroundColor(Color(white: 0.45))

                    Text(payload.captionText)
                        .font(AMENFont.regular(16))
                        .foregroundColor(.black.opacity(0.85))
                        .multilineTextAlignment(.leading)
                        .lineSpacing(6)
                        .lineLimit(6)
                        .fixedSize(horizontal: false, vertical: true)

                    // Optional scripture chip
                    if let ref = payload.verseReference {
                        HStack(spacing: 5) {
                            Image(systemName: "book")
                                .font(.systemScaled(10, weight: .medium))
                                .foregroundColor(Color(white: 0.45))
                            Text(ref)
                                .font(AMENFont.semiBold(11))
                                .foregroundColor(Color(white: 0.45))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(ShareGlass.capsuleBackground())
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.white.opacity(0.55))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5)
                        )
                )
                .padding(.horizontal, hPad)

                Spacer()

                // ── AUTHOR ROW ─────────────────────────────────────────
                ShareAuthorRow(
                    authorName: payload.authorName,
                    authorInitials: payload.authorInitials
                )
                .padding(.horizontal, hPad)

                Spacer(minLength: 16)

                // ── BOTTOM ─────────────────────────────────────────────
                VStack(spacing: 6) {
                    Text("Written in Church Notes on AMEN")
                        .font(AMENFont.regular(11))
                        .foregroundColor(Color(white: 0.50))
                        .tracking(0.5)
                    AMENBrandedWatermark(style: .bottomSignature)
                }
                .padding(.bottom, ShareCardDimensions.bottomPad)
            }
        }
        .frame(width: W, height: H)
        .clipped()
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - Part 3 · Share Card Renderer
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

@MainActor
final class AMENShareCardRenderer: ObservableObject {

    // MARK: Render (SwiftUI View)

    func renderCard(payload: AMENSharePayload) -> some View {
        switch payload.postType {
        case .text, .announcement:
            return AnyView(AMENTextShareCard(payload: payload))
        case .testimony:
            return AnyView(AMENTestimonyShareCard(payload: payload))
        case .prayer:
            return AnyView(AMENPrayerShareCard(payload: payload))
        case .verse:
            return AnyView(AMENVerseShareCard(payload: payload))
        case .photo:
            return AnyView(AMENPhotoShareCard(payload: payload))
        case .video:
            return AnyView(AMENVideoShareCard(payload: payload))
        case .carousel:
            return AnyView(AMENCarouselShareCard(payload: payload))
        case .churchNote:
            return AnyView(AMENChurchNoteShareCard(payload: payload))
        }
    }

    // MARK: Export to UIImage

    @available(iOS 16.0, *)
    func exportAsImage(
        payload: AMENSharePayload,
        size: CGSize = CGSize(width: ShareCardDimensions.width,
                              height: ShareCardDimensions.height)
    ) async -> UIImage? {
        let view = renderCard(payload: payload)
        let renderer = ImageRenderer(
            content: view.frame(width: size.width, height: size.height)
        )
        renderer.scale = 3.0   // @3x — crisp export
        return renderer.uiImage
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - Share Action Button
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Glass capsule button — icon + label. Used for Instagram / Copy / Share actions.
struct ShareActionButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.systemScaled(16, weight: .medium))
                    .foregroundColor(.black.opacity(0.75))
                Text(label)
                    .font(AMENFont.semiBold(15))
                    .foregroundColor(.black)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .background(ShareGlass.capsuleBackground())
        }
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.65), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded   { _ in isPressed = false }
        )
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - AMENShareSheet
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct AMENShareSheet: View {
    let payload: AMENSharePayload
    @Binding var isPresented: Bool

    @State private var renderedImage: UIImage? = nil
    @State private var isRendering: Bool = true
    @State private var cardScale: CGFloat = 0.92
    @State private var cardOpacity: Double = 0.0
    @State private var showShareOptions: Bool = false

    private let renderer = AMENShareCardRenderer()

    var body: some View {
        ZStack {
            // Dim scrim
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { isPresented = false }

            VStack(spacing: 24) {

                // ── Handle bar ────────────────────────────────────────
                Capsule()
                    .fill(Color(white: 0.75))
                    .frame(width: 36, height: 4)
                    .padding(.top, 12)

                // ── Card preview ──────────────────────────────────────
                ZStack {
                    if let image = renderedImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .cornerRadius(20)
                            .shadow(color: .black.opacity(0.12), radius: 24, x: 0, y: 8)
                    } else {
                        // Placeholder while rendering
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color(white: 0.95))
                            .frame(width: 260, height: 462)
                            .overlay(
                                VStack(spacing: 10) {
                                    ProgressView()
                                        .tint(Color(white: 0.50))
                                    if isRendering {
                                        Text("Preparing...")
                                            .font(AMENFont.regular(13))
                                            .foregroundColor(Color(white: 0.55))
                                            .transition(.opacity)
                                    }
                                }
                            )
                    }
                }
                .scaleEffect(cardScale)
                .opacity(cardOpacity)
                .frame(height: 462)

                // ── Share action buttons ──────────────────────────────
                if showShareOptions {
                    VStack(spacing: 12) {
                        // Instagram Stories
                        ShareActionButton(
                            icon: "camera",
                            label: "Instagram Stories",
                            action: shareToInstagram
                        )

                        // Copy image
                        ShareActionButton(
                            icon: "doc.on.doc",
                            label: "Copy Image",
                            action: copyImage
                        )

                        // System share sheet
                        ShareActionButton(
                            icon: "square.and.arrow.up",
                            label: "Share...",
                            action: showSystemSheet
                        )
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // ── Cancel ────────────────────────────────────────────
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        isPresented = false
                    }
                } label: {
                    Text("Cancel")
                        .font(AMENFont.semiBold(15))
                        .foregroundColor(Color(white: 0.45))
                        .padding(.vertical, 10)
                }

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: 420)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(Color.white.opacity(0.70))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5)
                    )
                    .ignoresSafeArea(edges: .bottom)
            )
            .shadow(color: .black.opacity(0.12), radius: 32, x: 0, y: -8)
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .task {
            await renderCard()
        }
    }

    // MARK: Render

    private func renderCard() async {
        isRendering = true
        if #available(iOS 16.0, *) {
            let image = await renderer.exportAsImage(payload: payload)
            await MainActor.run {
                renderedImage = image
                isRendering = false
                // Entrance animation — card settles in
                withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                    cardScale = 1.0
                    cardOpacity = 1.0
                }
                withAnimation(.easeIn(duration: 0.25).delay(0.2)) {
                    showShareOptions = true
                }
            }
        } else {
            isRendering = false
            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                cardScale = 1.0
                cardOpacity = 1.0
            }
        }
    }

    // MARK: Share Actions

    private func shareToInstagram() {
        guard let image = renderedImage,
              let url = URL(string: "instagram-stories://share?source_application=amen") else { return }
        if UIApplication.shared.canOpenURL(url) {
            let pasteboardItems: [[String: Any]] = [
                ["com.instagram.sharedSticker.backgroundImage": image.pngData() as Any]
            ]
            UIPasteboard.general.setItems(pasteboardItems,
                                          options: [.expirationDate: Date().addingTimeInterval(60)])
            UIApplication.shared.open(url)
        } else {
            // Instagram not installed — fall through to system sheet
            showSystemSheet()
        }
    }

    private func copyImage() {
        guard let image = renderedImage else { return }
        UIPasteboard.general.image = image
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
    }

    private func showSystemSheet() {
        guard let image = renderedImage else { return }
        let activityVC = UIActivityViewController(
            activityItems: [image],
            applicationActivities: nil
        )
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - Previews
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

private let sampleTextPayload = AMENSharePayload(
    postType: .text,
    authorName: "Marcus Adetola",
    authorInitials: "MA",
    captionText: "Walking in faith means trusting the process even when the path isn't clear. His timing is perfect.",
    verseReference: nil,
    categoryLabel: "#OPENTABLE",
    imageData: nil,
    thumbnailData: nil,
    churchName: nil,
    timestamp: Date(),
    deepLinkURL: "amen://post/abc123"
)

private let sampleTestimonyPayload = AMENSharePayload(
    postType: .testimony,
    authorName: "Priya Joseph",
    authorInitials: "PJ",
    captionText: "Three years ago I was homeless. Today I own a home and lead a small group. God is faithful. He restores what the enemy stole.",
    verseReference: nil,
    categoryLabel: "Testimony",
    imageData: nil,
    thumbnailData: nil,
    churchName: nil,
    timestamp: Date(),
    deepLinkURL: "amen://post/def456"
)

private let samplePrayerPayload = AMENSharePayload(
    postType: .prayer,
    authorName: "Elijah Thompson",
    authorInitials: "ET",
    captionText: "Father, I lift up everyone reading this. May you cover them in your peace that surpasses all understanding. Amen.",
    verseReference: nil,
    categoryLabel: nil,
    imageData: nil,
    thumbnailData: nil,
    churchName: nil,
    timestamp: Date(),
    deepLinkURL: "amen://post/ghi789"
)

private let sampleVersePayload = AMENSharePayload(
    postType: .verse,
    authorName: "Community",
    authorInitials: "A",
    captionText: "I can do all things through Christ who strengthens me.",
    verseReference: "Philippians 4:13",
    categoryLabel: nil,
    imageData: nil,
    thumbnailData: nil,
    churchName: nil,
    timestamp: Date(),
    deepLinkURL: "amen://post/verse001"
)

private let sampleChurchNotePayload = AMENSharePayload(
    postType: .churchNote,
    authorName: "Sarah Okonkwo",
    authorInitials: "SO",
    captionText: "Sunday sermon note: The enemy comes to steal, kill and destroy — but Jesus came so we may have life abundantly. Don't let comparison rob you of your inheritance.",
    verseReference: "John 10:10",
    categoryLabel: nil,
    imageData: nil,
    thumbnailData: nil,
    churchName: "Elevation Church · Atlanta",
    timestamp: Date(),
    deepLinkURL: "amen://note/jkl012"
)

struct AMENShareCardSystem_Previews: PreviewProvider {
    static var previews: some View {
        Group {

            // Text card
            AMENTextShareCard(payload: sampleTextPayload)
                .previewDisplayName("Text Share Card")
                .previewLayout(.fixed(
                    width: ShareCardDimensions.width,
                    height: ShareCardDimensions.height
                ))

            // Testimony card
            AMENTestimonyShareCard(payload: sampleTestimonyPayload)
                .previewDisplayName("Testimony Share Card")
                .previewLayout(.fixed(
                    width: ShareCardDimensions.width,
                    height: ShareCardDimensions.height
                ))

            // Prayer card
            AMENPrayerShareCard(payload: samplePrayerPayload)
                .previewDisplayName("Prayer Share Card")
                .previewLayout(.fixed(
                    width: ShareCardDimensions.width,
                    height: ShareCardDimensions.height
                ))

            // Verse card
            AMENVerseShareCard(payload: sampleVersePayload)
                .previewDisplayName("Verse Share Card")
                .previewLayout(.fixed(
                    width: ShareCardDimensions.width,
                    height: ShareCardDimensions.height
                ))

            // Photo card (placeholder — no imageData in preview)
            AMENPhotoShareCard(payload: AMENSharePayload(
                postType: .photo,
                authorName: "James Adeyemi",
                authorInitials: "JA",
                captionText: "Sunday morning vibes at our community garden outreach.",
                verseReference: nil,
                categoryLabel: nil,
                imageData: nil,
                thumbnailData: nil,
                churchName: nil,
                timestamp: Date(),
                deepLinkURL: "amen://post/photo001"
            ))
            .previewDisplayName("Photo Share Card (placeholder)")
            .previewLayout(.fixed(
                width: ShareCardDimensions.width,
                height: ShareCardDimensions.height
            ))

            // Video card
            AMENVideoShareCard(payload: {
                var p = AMENSharePayload(
                    postType: .video,
                    authorName: "Rebecca Nwosu",
                    authorInitials: "RN",
                    captionText: "Worship night recap — what a time in His presence.",
                    verseReference: nil,
                    categoryLabel: nil,
                    imageData: nil,
                    thumbnailData: nil,
                    churchName: nil,
                    timestamp: Date(),
                    deepLinkURL: "amen://post/video001"
                )
                p.videoDuration = "3:47"
                return p
            }())
            .previewDisplayName("Video Share Card")
            .previewLayout(.fixed(
                width: ShareCardDimensions.width,
                height: ShareCardDimensions.height
            ))

            // Carousel card
            AMENCarouselShareCard(payload: {
                var p = AMENSharePayload(
                    postType: .carousel,
                    authorName: "Hope & Grace Ministry",
                    authorInitials: "HG",
                    captionText: "5 things God is saying to the church right now. Swipe through.",
                    verseReference: nil,
                    categoryLabel: nil,
                    imageData: nil,
                    thumbnailData: nil,
                    churchName: nil,
                    timestamp: Date(),
                    deepLinkURL: "amen://post/carousel001"
                )
                p.carouselCount = 5
                return p
            }())
            .previewDisplayName("Carousel Share Card")
            .previewLayout(.fixed(
                width: ShareCardDimensions.width,
                height: ShareCardDimensions.height
            ))

            // Church Note card
            AMENChurchNoteShareCard(payload: sampleChurchNotePayload)
                .previewDisplayName("Church Note Share Card")
                .previewLayout(.fixed(
                    width: ShareCardDimensions.width,
                    height: ShareCardDimensions.height
                ))

            // Watermark styles
            VStack(spacing: 24) {
                AMENBrandedWatermark(style: .topMark)
                AMENBrandedWatermark(style: .cornerStamp)
                AMENBrandedWatermark(style: .bottomSignature)
                AMENBrandedWatermark(style: .verticalSeal)
            }
            .padding(32)
            .background(Color.white)
            .previewDisplayName("Watermark Styles")

            // Share Sheet preview
            ZStack {
                Color.black.opacity(0.4).ignoresSafeArea()
                AMENShareSheet(payload: sampleVersePayload, isPresented: .constant(true))
            }
            .previewDisplayName("Share Sheet")
        }
    }
}
