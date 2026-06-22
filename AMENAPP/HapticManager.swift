//
//  HapticManager.swift
//  AMENAPP
//
//  Centralized haptic feedback with pre-warmed generators and debouncing.
//
//  Design rules for AMEN haptics:
//    - Use haptics only for meaningful user-initiated outcomes:
//        follow/unfollow, send message, save post, submit form,
//        success/error on important async actions.
//    - Do NOT use haptics for: navigation taps, row selection,
//        filter changes, scroll events, or loading completions.
//    - Max intensity is .medium — .heavy and .rigid are excluded
//        (too jarring for a calm, faith-centered social app).
//    - Debouncing: same key cannot fire within 80 ms to prevent stacking.
//

import UIKit

final class HapticManager {

    // MARK: - Pre-warmed generators

    private static let lightImpact: UIImpactFeedbackGenerator = {
        let g = UIImpactFeedbackGenerator(style: .light); g.prepare(); return g
    }()

    private static let mediumImpact: UIImpactFeedbackGenerator = {
        let g = UIImpactFeedbackGenerator(style: .medium); g.prepare(); return g
    }()

    private static let softImpact: UIImpactFeedbackGenerator = {
        let g = UIImpactFeedbackGenerator(style: .soft); g.prepare(); return g
    }()

    private static let notificationGenerator: UINotificationFeedbackGenerator = {
        let g = UINotificationFeedbackGenerator(); g.prepare(); return g
    }()

    private static let selectionGenerator: UISelectionFeedbackGenerator = {
        let g = UISelectionFeedbackGenerator(); g.prepare(); return g
    }()

    // MARK: - Debounce (80 ms minimum interval per key)

    private static var lastFiredAt: [String: Date] = [:]
    private static let minimumInterval: TimeInterval = 0.08

    private static func canFire(key: String) -> Bool {
        let now = Date()
        if let last = lastFiredAt[key], now.timeIntervalSince(last) < minimumInterval {
            return false
        }
        lastFiredAt[key] = now
        return true
    }

    // MARK: - Public API

    /// Subtle confirmatory tap for follow, save, send, etc.
    /// `.heavy` and `.rigid` are capped to `.medium` — keep the experience calm.
    static func impact(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard canFire(key: "impact-\(style.rawValue)") else { return }

        switch style {
        case .light:  lightImpact.impactOccurred();  lightImpact.prepare()
        case .medium: mediumImpact.impactOccurred(); mediumImpact.prepare()
        case .soft:   softImpact.impactOccurred();   softImpact.prepare()
        default:      mediumImpact.impactOccurred(); mediumImpact.prepare()
        }
    }

    /// Use only for important async outcomes: post sent, sign-in success, network error.
    /// Do NOT use for routine row taps or filter changes.
    static func notification(type: UINotificationFeedbackGenerator.FeedbackType) {
        guard canFire(key: "notification-\(type.rawValue)") else { return }

        notificationGenerator.notificationOccurred(type)
        notificationGenerator.prepare()
    }

    /// Use only for meaningful segmented-control or picker changes.
    static func selection() {
        guard canFire(key: "selection") else { return }

        selectionGenerator.selectionChanged()
        selectionGenerator.prepare()
    }

    // MARK: - Pre-warm on launch
    static func prepareAll() {
        lightImpact.prepare()
        mediumImpact.prepare()
        softImpact.prepare()
        notificationGenerator.prepare()
        selectionGenerator.prepare()
    }
}
