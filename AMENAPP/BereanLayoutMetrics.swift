//
//  BereanLayoutMetrics.swift
//  AMENAPP
//
//  Layout metrics tuned for Berean chat across iPhone sizes.
//  Avoids hardcoded magic numbers scattered across views.
//
//  Size classes used internally:
//    compact  — iPhone SE 1st/2nd gen, iPhone 12 mini/13 mini  (h < 700pt)
//    standard — iPhone 14/15/16, iPhone 14 Pro                 (700...850pt)
//    large    — iPhone 14/15/16 Plus, Pro Max                  (> 850pt)
//

import SwiftUI

struct BereanLayoutMetrics {
    let screenHeight: CGFloat
    let screenWidth: CGFloat
    /// Top safe-area inset passed in from the parent view's safeAreaInsets.
    /// Dynamic Island devices report 59pt; TrueDepth notch devices report 47pt.
    let topSafeAreaInset: CGFloat
    /// Bottom safe-area inset (home indicator bar).
    /// Face ID iPhones report ~34pt; older devices with a Home button report 0.
    let bottomSafeAreaInset: CGFloat

    init(size: CGSize, topSafeAreaInset: CGFloat = 0, bottomSafeAreaInset: CGFloat = 0) {
        self.screenHeight = size.height
        self.screenWidth = size.width
        self.topSafeAreaInset = topSafeAreaInset
        self.bottomSafeAreaInset = bottomSafeAreaInset
    }

    // MARK: - Size Classification

    private var isCompact: Bool { screenHeight < 700 }
    private var isLarge: Bool { screenHeight > 850 }

    // MARK: - Input Bar

    var inputBarExpandedHeight: CGFloat { isCompact ? 52 : 56 }
    var inputBarCompactHeight: CGFloat  { isCompact ? 44 : 46 }

    /// The minimum tap target height for input bar actions (accessibility).
    var inputBarMinTapTarget: CGFloat { 44 }

    // MARK: - Study Surface

    var studySurfaceMaxHeight: CGFloat      { isCompact ? 180 : (isLarge ? 260 : 220) }
    var studySurfaceCollapsedHeight: CGFloat { isCompact ? 54 : 60 }

    /// Number of category cards shown in collapsed ribbon mode.
    var studySurfaceRibbonItemCount: Int { isCompact ? 3 : 4 }

    // MARK: - Header

    /// Dynamic Island devices report a top safe-area inset of ≥ 59pt.
    /// TrueDepth notch devices report 47pt. SE and older report ≤ 24pt.
    private var hasDynamicIsland: Bool { topSafeAreaInset >= 59 }

    var headerVerticalPadding: CGFloat { isCompact ? 8 : (hasDynamicIsland ? 14 : 10) }
    /// Additional safe-area top offset for headers sitting below the nav area.
    /// On Dynamic Island devices we add the extra 12pt of island intrusion so
    /// the header content is never obscured by the pill-shaped cutout.
    var headerTopSafeOffset: CGFloat {
        if hasDynamicIsland { return 12 }
        return isCompact ? 0 : 2
    }

    // MARK: - Content Spacing

    var contentHorizontalPadding: CGFloat { screenWidth < 360 ? 14 : 16 }
    var messageSectionSpacing: CGFloat    { isCompact ? 12 : 16 }
    var heroTopPadding: CGFloat           { isCompact ? 16 : 24 }

    // MARK: - Bottom Inset

    /// Space reserved at bottom of scroll content so the last message
    /// is never hidden behind the floating input bar.
    var bottomContentInset: CGFloat { isCompact ? 140 : (isLarge ? 180 : 160) }

    /// Bottom padding for the floating composer VStack so it clears the home indicator.
    /// On Face ID iPhones (bottomSafeAreaInset ≈ 34pt) this prevents the input bar
    /// from overlapping the system swipe-up gesture area.
    var composerBottomPadding: CGFloat { max(bottomSafeAreaInset, 8) }

    // MARK: - Scroll Thresholds

    /// Offset above which the header begins to visually compress.
    var headerCompressionThreshold: CGFloat { 40 }
    /// Offset above which the study surface collapses to a ribbon.
    var studySurfaceCollapseThreshold: CGFloat { isCompact ? 80 : 120 }

    // MARK: - Grid

    /// Column count for study mode reasoning grid.
    var studyModeGridColumns: Int { screenWidth < 360 ? 1 : 2 }
}
