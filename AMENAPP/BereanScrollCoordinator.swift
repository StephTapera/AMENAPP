//
//  BereanScrollCoordinator.swift
//  AMENAPP
//
//  Scroll state coordinator for Berean chat. Throttles updates,
//  tracks scroll velocity and direction, and determines near-bottom
//  behavior without layout jitter.
//

import SwiftUI

enum BereanScrollContext: Equatable {
    case atTop
    case midScroll
    case nearBottom
    case activelyDragging
    case reversingDirection
}

final class BereanScrollCoordinator: ObservableObject {
    @Published private(set) var context: BereanScrollContext = .nearBottom
    @Published private(set) var isNearBottom: Bool = true
    @Published private(set) var isUserDragging: Bool = false
    @Published private(set) var scrollOffset: CGFloat = 0
    /// Normalized scroll velocity — positive = scrolling down, negative = scrolling up.
    @Published private(set) var scrollVelocity: CGFloat = 0
    /// True when the user is actively scrolling upward through history.
    @Published private(set) var isScrollingUpward: Bool = false
    /// Relative progress 0…1 from top to bottom of content.
    @Published private(set) var scrollProgress: CGFloat = 0

    private var lastOffset: CGFloat = 0
    private var lastUpdate: TimeInterval = 0
    private let throttleInterval: TimeInterval = 0.06

    // Velocity smoothing
    private var recentDeltas: [CGFloat] = []
    private let velocityWindowSize = 4

    func setDragging(_ dragging: Bool) {
        if isUserDragging != dragging {
            isUserDragging = dragging
            if dragging {
                context = .activelyDragging
            }
        }
    }

    func update(offset: CGFloat, contentHeight: CGFloat, viewportHeight: CGFloat) {
        let now = Date().timeIntervalSince1970
        guard now - lastUpdate > throttleInterval else { return }
        lastUpdate = now

        let newOffset = max(0, offset)
        let delta = newOffset - lastOffset

        // Maintain a small velocity window for smooth reads
        recentDeltas.append(delta)
        if recentDeltas.count > velocityWindowSize { recentDeltas.removeFirst() }
        let avgDelta = recentDeltas.reduce(0, +) / CGFloat(max(recentDeltas.count, 1))
        scrollVelocity = avgDelta

        isScrollingUpward = avgDelta < -1.5

        scrollOffset = newOffset
        lastOffset = newOffset

        let scrollableRange = max(0, contentHeight - viewportHeight)
        if scrollableRange > 0 {
            scrollProgress = min(max(newOffset / scrollableRange, 0), 1)
        } else {
            scrollProgress = 1
        }

        let distanceFromBottom = max(0, contentHeight - (newOffset + viewportHeight))
        let nearBottomThreshold: CGFloat = 140
        let isNowNearBottom = distanceFromBottom <= nearBottomThreshold
        isNearBottom = isNowNearBottom

        let isReversing = avgDelta < -2

        if newOffset <= 6 {
            context = .atTop
        } else if isNowNearBottom {
            context = .nearBottom
        } else if isReversing {
            context = .reversingDirection
        } else {
            context = .midScroll
        }
    }

    func shouldAutoScroll(isUserInitiated: Bool) -> Bool {
        if isUserInitiated { return true }
        if isUserDragging { return false }
        return isNearBottom
    }

    /// Compact input bar when user is scrolling up through history.
    var shouldCompactInputBar: Bool {
        scrollOffset > 100 && !isScrollingUpward && context == .midScroll
    }
}
