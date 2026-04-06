// TopChromeMetrics.swift
// Smart Header Orchestrator — Layout constants

import CoreFoundation

enum TopChromeMetrics {
    // Heights
    static let greetingRowHeight:  CGFloat = 56
    static let compactBarHeight:   CGFloat = 44
    static let verseBannerMinHeight: CGFloat = 72

    // Spacing
    static let containerPadding:   CGFloat = 16
    static let innerSpacing:       CGFloat = 10

    // Animation
    static let expandDuration:     Double  = 0.32
    static let collapseDuration:   Double  = 0.22
    static let springResponse:     Double  = 0.38
    static let springDamping:      Double  = 0.82

    // Scroll thresholds
    static let collapseThreshold:  CGFloat = 60
    static let hideThreshold:      CGFloat = 120

    // Corner radii
    static let containerRadius:    CGFloat = 20
    static let pillRadius:         CGFloat = 12
}
