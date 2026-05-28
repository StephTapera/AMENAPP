import SwiftUI
import UIKit

// MARK: - PUBLIC INTERFACE

/// Visual spec for share card sizes. ogPreview (1200×630) lives server-side in Agent D.
public enum ShareCardSize: CaseIterable {
    case story   // 1080×1920, 9:16
    case square  // 1080×1080, 1:1

    /// Exact pixel dimensions — ImageRenderer renders at scale=1 so points == pixels.
    public var pixelSize: CGSize {
        switch self {
        case .story:  return CGSize(width: 1080, height: 1920)
        case .square: return CGSize(width: 1080, height: 1080)
        }
    }

    /// Safe-area inset on all sides (from spec).
    public var padding: CGFloat {
        switch self {
        case .story:  return 80
        case .square: return 60
        }
    }

    /// Display-weight pull-quote font size (from spec).
    public var pullQuoteFontSize: CGFloat {
        switch self {
        case .story:  return 64
        case .square: return 52
        }
    }

    /// Verse reference font size.
    public var verseRefFontSize: CGFloat { 32 }

    /// Maximum rendered lines before truncation.
    public var maxLines: Int { 4 }

    /// Hard character cap; text beyond this is truncated with "…".
    public var maxPullQuoteChars: Int { 180 }
}

/// Static color constants for share cards.
/// These are not adaptive — cards must look identical regardless of device color scheme.
public enum ShareCardColors {
    public static let amenGold   = Color(red: 0.83, green: 0.69, blue: 0.22)
    public static let amenBlack  = Color(red: 0.05, green: 0.05, blue: 0.07)
    public static let amenPurple = Color(red: 0.47, green: 0.24, blue: 0.85)

    public static var radialBackground: RadialGradient {
        RadialGradient(
            colors: [amenPurple.opacity(0.45), amenBlack],
            center: .center,
            startRadius: 0,
            endRadius: 700
        )
    }
}
