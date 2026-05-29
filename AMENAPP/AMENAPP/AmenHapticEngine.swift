//
//  AmenHapticEngine.swift
//  AMENAPP
//
//  CoreHaptics-backed haptic engine with spiritual/faithful patterns.
//  Patterns are intentionally gentle and reverent — never gamified.
//
//  Usage:
//    await AmenHapticEngine.shared.play(.prayerReceived)
//    AmenHapticEngine.feedback(.light)
//

import CoreHaptics
import UIKit

// MARK: - Pattern Definitions

/// Named haptic patterns for meaningful, faith-aligned moments in AMEN.
/// All patterns are deliberately soft. Max intensities are capped at 0.7
/// so the device never feels jarring or attention-seeking.
enum AmenHapticPattern {

    /// Soft warm pulse — someone sent you a prayer request or prayed for you.
    case prayerReceived

    /// Rising double-tap — a word of encouragement or affirmation.
    case encouragement

    /// Long soft fade — reflection session or reading plan completed.
    case reflectionCompleted

    /// Gentle wave — safe space / calm mode activated.
    case safeSpaceActivated

    /// Light shiver then bloom — a scripture is revealed or highlighted.
    case scriptureRevealed

    /// Three staggered cautionary taps — content warning shown.
    case contentWarning

    /// Warm burst + soft decay — someone reacted with Amen.
    case amenReaction

    /// Two-tone pulse — new connection made or follow accepted.
    case connectionMade
}

// MARK: - AmenHapticEngine

@MainActor
final class AmenHapticEngine {

    // MARK: Singleton
    static let shared = AmenHapticEngine()
    private init() {}

    // MARK: State
    private var engine: CHHapticEngine?
    private var engineReady = false

    // MARK: - Engine Lifecycle

    /// Creates, configures and starts the CHHapticEngine.
    /// Safe to call multiple times — re-creates engine if it was reset.
    func prepareEngine() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            dlog("AmenHapticEngine: device does not support CoreHaptics")
            return
        }
        do {
            let newEngine = try CHHapticEngine()
            newEngine.isAutoShutdownEnabled = true
            newEngine.resetHandler = { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    dlog("AmenHapticEngine: engine reset — re-preparing")
                    self.engine = nil
                    self.engineReady = false
                    self.prepareEngine()
                }
            }
            newEngine.stoppedHandler = { [weak self] reason in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    dlog("AmenHapticEngine: engine stopped (\(reason)) — marking not ready")
                    self.engineReady = false
                }
            }
            try newEngine.start()
            engine = newEngine
            engineReady = true
            dlog("AmenHapticEngine: engine prepared and started")
        } catch {
            dlog("AmenHapticEngine: failed to prepare engine — \(error.localizedDescription)")
        }
    }

    // MARK: - Public Play API

    /// Plays the given spiritual haptic pattern.
    /// - Skipped entirely when Reduce Motion is enabled (accessibility).
    /// - Falls back to UIImpactFeedbackGenerator when CoreHaptics is unavailable.
    func play(_ pattern: AmenHapticPattern) async {
        // Honour Reduce Motion — silence all haptics.
        guard !UIAccessibility.isReduceMotionEnabled else { return }

        // Lazy engine init on first use.
        if engine == nil || !engineReady {
            prepareEngine()
        }

        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics,
              let engine, engineReady else {
            // Fallback: UIImpactFeedbackGenerator
            fallbackFeedback(for: pattern)
            return
        }

        do {
            let hapticPattern: CHHapticPattern
            if pattern == .reflectionCompleted {
                hapticPattern = try buildFadePattern()
            } else {
                let events = try buildEvents(for: pattern)
                hapticPattern = try CHHapticPattern(events: events, parameters: [])
            }
            let player = try engine.makePlayer(with: hapticPattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            dlog("AmenHapticEngine: play(\(pattern)) failed — \(error.localizedDescription)")
            fallbackFeedback(for: pattern)
        }
    }

    /// Builds the reflectionCompleted pattern with a real intensity fade curve.
    private func buildFadePattern() throws -> CHHapticPattern {
        let event = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.5),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.05)
            ],
            relativeTime: 0,
            duration: 0.8
        )
        let fadeCurve = CHHapticParameterCurve(
            parameterID: .hapticIntensityControl,
            controlPoints: [
                CHHapticParameterCurve.ControlPoint(relativeTime: 0,   value: 1.0),
                CHHapticParameterCurve.ControlPoint(relativeTime: 0.8, value: 0.2)   // 0.1/0.5
            ],
            relativeTime: 0
        )
        return try CHHapticPattern(events: [event], parameterCurves: [fadeCurve])
    }

    // MARK: - Convenience Static Feedback

    /// Simple UIImpactFeedbackGenerator wrapper for non-spiritual, utilitarian taps.
    static func feedback(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }

    // MARK: - Event Builders

    private func buildEvents(for pattern: AmenHapticPattern) throws -> [CHHapticEvent] {
        switch pattern {

        case .prayerReceived:
            // Soft warm pulse: one low-intensity continuous event over 0.3 s
            return [
                continuousEvent(intensity: 0.4, sharpness: 0.1, time: 0, duration: 0.3)
            ]

        case .encouragement:
            // Rising double-tap: two transients, intensities [0.5, 0.7], at [0, 0.15]
            return [
                transientEvent(intensity: 0.5, sharpness: 0.2, time: 0),
                transientEvent(intensity: 0.7, sharpness: 0.3, time: 0.15)
            ]

        case .reflectionCompleted:
            // Handled separately via buildFadePattern() — should not reach here.
            return []

        case .safeSpaceActivated:
            // Gentle wave: very soft transient + one soft at 0.1 s
            return [
                transientEvent(intensity: 0.3, sharpness: 0.05, time: 0),
                transientEvent(intensity: 0.25, sharpness: 0.05, time: 0.1)
            ]

        case .scriptureRevealed:
            // Light shiver then bloom: 3 quick soft transients + one medium at 0.25 s
            return [
                transientEvent(intensity: 0.3, sharpness: 0.15, time: 0),
                transientEvent(intensity: 0.3, sharpness: 0.15, time: 0.07),
                transientEvent(intensity: 0.3, sharpness: 0.15, time: 0.14),
                transientEvent(intensity: 0.5, sharpness: 0.2,  time: 0.25)
            ]

        case .contentWarning:
            // Three staggered cautionary taps: transients at [0, 0.12, 0.24], intensity 0.45
            return [
                transientEvent(intensity: 0.45, sharpness: 0.4, time: 0),
                transientEvent(intensity: 0.45, sharpness: 0.4, time: 0.12),
                transientEvent(intensity: 0.45, sharpness: 0.4, time: 0.24)
            ]

        case .amenReaction:
            // Warm burst + decaying follow: transient 0.7 + softer one at 0.1 s
            return [
                transientEvent(intensity: 0.7, sharpness: 0.25, time: 0),
                transientEvent(intensity: 0.35, sharpness: 0.1, time: 0.1)
            ]

        case .connectionMade:
            // Two-tone pulse: transients at [0, 0.2], intensities [0.6, 0.4]
            return [
                transientEvent(intensity: 0.6, sharpness: 0.3, time: 0),
                transientEvent(intensity: 0.4, sharpness: 0.15, time: 0.2)
            ]
        }
    }

    // MARK: - Event Factories

    private func transientEvent(
        intensity: Float,
        sharpness: Float,
        time: TimeInterval
    ) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
            ],
            relativeTime: time
        )
    }

    private func continuousEvent(
        intensity: Float,
        sharpness: Float,
        time: TimeInterval,
        duration: TimeInterval
    ) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
            ],
            relativeTime: time,
            duration: duration
        )
    }

    // MARK: - Fallback

    /// UIImpactFeedbackGenerator fallback when CoreHaptics is unavailable.
    /// Uses .light for low-intensity patterns, .medium for others.
    private func fallbackFeedback(for pattern: AmenHapticPattern) {
        let style: UIImpactFeedbackGenerator.FeedbackStyle = lowIntensityPatterns.contains(pattern)
            ? .light
            : .medium
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }

    private let lowIntensityPatterns: Set<AmenHapticPattern> = [
        .prayerReceived, .safeSpaceActivated, .reflectionCompleted
    ]
}

// MARK: - AmenHapticPattern: Hashable

extension AmenHapticPattern: Hashable {}
