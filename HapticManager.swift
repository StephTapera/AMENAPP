//
//  HapticManager.swift
//  AMENAPP
//
//  Centralized haptic feedback utility with pre-warmed shared generators.
//  Using shared, pre-warmed generators eliminates the latency of
//  instantiating a new generator on every tap.
//

import UIKit

final class HapticManager {
    // MARK: - Shared pre-warmed generators
    // Generators are created once and kept alive, avoiding per-call allocation.

    private static let lightImpact: UIImpactFeedbackGenerator = {
        let g = UIImpactFeedbackGenerator(style: .light)
        g.prepare()
        return g
    }()

    private static let mediumImpact: UIImpactFeedbackGenerator = {
        let g = UIImpactFeedbackGenerator(style: .medium)
        g.prepare()
        return g
    }()

    private static let heavyImpact: UIImpactFeedbackGenerator = {
        let g = UIImpactFeedbackGenerator(style: .heavy)
        g.prepare()
        return g
    }()

    private static let rigidImpact: UIImpactFeedbackGenerator = {
        let g = UIImpactFeedbackGenerator(style: .rigid)
        g.prepare()
        return g
    }()

    private static let softImpact: UIImpactFeedbackGenerator = {
        let g = UIImpactFeedbackGenerator(style: .soft)
        g.prepare()
        return g
    }()

    private static let notificationGenerator: UINotificationFeedbackGenerator = {
        let g = UINotificationFeedbackGenerator()
        g.prepare()
        return g
    }()

    private static let selectionGenerator: UISelectionFeedbackGenerator = {
        let g = UISelectionFeedbackGenerator()
        g.prepare()
        return g
    }()

    // MARK: - Public API

    /// Fire an impact haptic. Call `prepare()` before a known interaction
    /// (e.g. in button `onHover`/`onLongPressGesture` began) for zero-latency playback.
    static func impact(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        switch style {
        case .light:   lightImpact.impactOccurred();  lightImpact.prepare()
        case .medium:  mediumImpact.impactOccurred(); mediumImpact.prepare()
        case .heavy:   heavyImpact.impactOccurred();  heavyImpact.prepare()
        case .rigid:   rigidImpact.impactOccurred();  rigidImpact.prepare()
        case .soft:    softImpact.impactOccurred();   softImpact.prepare()
        @unknown default:
            mediumImpact.impactOccurred()
            mediumImpact.prepare()
        }
    }

    static func notification(type: UINotificationFeedbackGenerator.FeedbackType) {
        notificationGenerator.notificationOccurred(type)
        notificationGenerator.prepare()
    }

    static func selection() {
        selectionGenerator.selectionChanged()
        selectionGenerator.prepare()
    }

    // MARK: - Convenience pre-warm
    /// Call on app launch or before a view is about to appear to prime the taptic engine.
    static func prepareAll() {
        lightImpact.prepare()
        mediumImpact.prepare()
        heavyImpact.prepare()
        rigidImpact.prepare()
        softImpact.prepare()
        notificationGenerator.prepare()
        selectionGenerator.prepare()
    }
}
