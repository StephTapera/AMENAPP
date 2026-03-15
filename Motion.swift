//
//  Motion.swift
//  AMENAPP
//
//  Centralized motion primitives for premium iOS-native animation.
//  Rules:
//   - Zero layout drift: all scale/offset animations return to identity.
//   - Explicit animations only: no implicit leaks onto parent containers.
//   - Reduce Motion aware: springs replaced with short fade when enabled.
//   - 60fps safe: no GeometryReader-driven continuous updates, no repeated
//     shadow recalculation inside hot paths.
//

import SwiftUI

// MARK: - Motion Namespace

/// Drop-in replacements / complements for AnimationPresets.
/// Use `Motion.springPress`, `Motion.popToggle`, etc. throughout the app.
enum Motion {

    // MARK: Springs

    /// Press-down: tight, no overshoot — finger-on-screen feel.
    static let springPress = Animation.spring(response: 0.22, dampingFraction: 0.88)

    /// Release / snap-back: slightly more room for a crisp rebound.
    static let springRelease = Animation.spring(response: 0.26, dampingFraction: 0.72)

    /// Reaction toggle ON (lightbulb, amen, save): quick pop with a hint of bounce.
    static let popToggle = Animation.spring(response: 0.20, dampingFraction: 0.56)

    /// Reaction toggle OFF: smaller, no pop — just a tight spring back.
    static let unpopToggle = Animation.spring(response: 0.22, dampingFraction: 0.82)

    /// Card / row one-time appear: easeOut feel — fast and unobtrusive.
    static let appearEase = Animation.easeOut(duration: 0.24)

    /// Error shake: plain linear, short — not a spring (prevents overshoot on shake).
    static let shakeLinear = Animation.linear(duration: 0.06)

    // MARK: Reduce Motion Helpers

    /// Returns `spring` when Reduce Motion is OFF, else `easeInOut(0.16)` fade.
    static func adaptive(_ spring: Animation) -> Animation {
        UIAccessibility.isReduceMotionEnabled
            ? .easeInOut(duration: 0.16)
            : spring
    }
}

// MARK: - A) PressableScaleModifier
// Use on interactive cards. Does NOT conflict with ScrollView vertical gestures
// because minimumDistance: 0 is simultaneous with the scroll gesture.

struct PressableScaleModifier: ViewModifier {
    /// Scale applied while finger is down (cards: 0.985, buttons: 0.97).
    var pressedScale: CGFloat = 0.985
    /// Optional opacity delta while pressed (very subtle).
    var pressedOpacityDelta: Double = 0.03

    // DragGesture(minimumDistance: 0) removed — it competed with the parent
    // ScrollView's pan recognizer and blocked vertical scroll entirely.
    // The gesture system sees a zero-distance drag on every PostCard and
    // prevents UIScrollView from recognizing the pan until the SwiftUI
    // gesture fails, which it never does → scroll is permanently blocked.

    func body(content: Content) -> some View {
        content
    }
}

extension View {
    /// Adds a subtle press-down scale to any interactive card or row.
    func pressableCard(scale: CGFloat = 0.985) -> some View {
        modifier(PressableScaleModifier(pressedScale: scale))
    }

    /// Slightly stronger press for standalone buttons (not inside cards).
    func pressableButton() -> some View {
        modifier(PressableScaleModifier(pressedScale: 0.97, pressedOpacityDelta: 0.04))
    }
}

// MARK: - D) OneTimeAppearModifier
// Animates a feed item in on first appearance only.
// Uses a seen-IDs cache so scrolling back does NOT re-trigger the animation.

private actor SeenIDsCache {
    static let shared = SeenIDsCache()
    private var seen = Set<AnyHashable>()
    func insert(_ id: AnyHashable) { seen.insert(id) }
    func contains(_ id: AnyHashable) -> Bool { seen.contains(id) }
}

struct OneTimeAppearModifier: ViewModifier {
    let id: AnyHashable
    /// Stagger delay (seconds) for list items — pass `index * 0.04` for a cascade.
    /// When 0 (tab-switch suppression), skip the async actor hop and appear instantly.
    var delay: Double = 0

    @State private var visible = false
    @State private var hasAnimated = false

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : 8)
            // Explicit animation on `visible` change only.
            .animation(
                Motion.adaptive(Motion.appearEase).delay(delay),
                value: visible
            )
            .onAppear {
                guard !hasAnimated else { return }
                // Fast path: delay==0 means tab-switch suppression — skip actor hop, appear instantly.
                if delay == 0 {
                    visible = true
                    return
                }
                // Normal path: check seen cache so scroll-back items don't re-animate.
                Task {
                    let alreadySeen = await SeenIDsCache.shared.contains(id)
                    await MainActor.run {
                        if alreadySeen {
                            // Skip animation for recycled/scroll-back items — set instantly.
                            visible = true
                        } else {
                            hasAnimated = true
                            visible = true   // triggers fade+slide animation via .animation
                        }
                    }
                    if !alreadySeen {
                        await SeenIDsCache.shared.insert(id)
                    }
                }
            }
    }
}

extension View {
    /// One-time fade+slide-up appear for feed items. Pass a stable post ID.
    func feedItemAppear(id: AnyHashable, delay: Double = 0) -> some View {
        modifier(OneTimeAppearModifier(id: id, delay: delay))
    }
}

// MARK: - E) ReactionPopModifier
// Drives the scale "pop" for toggle-ON / "dip" for toggle-OFF.
// Apply directly on the Image inside a reaction button for best perf.

struct ReactionPopModifier: ViewModifier {
    let isActive: Bool
    @State private var scale: CGFloat = 1.0
    @State private var lastActive: Bool

    init(isActive: Bool) {
        self.isActive = isActive
        self._lastActive = State(initialValue: isActive)
    }

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .onChange(of: isActive) { _, newValue in
                if newValue {
                    // Toggle ON: pop 1 → 1.22 → 1.0
                    withAnimation(Motion.adaptive(Motion.popToggle)) {
                        scale = 1.22
                    }
                    withAnimation(Motion.adaptive(Motion.springRelease).delay(0.14)) {
                        scale = 1.0
                    }
                } else {
                    // Toggle OFF: dip 1 → 0.86 → 1.0
                    withAnimation(Motion.adaptive(Motion.unpopToggle)) {
                        scale = 0.86
                    }
                    withAnimation(Motion.adaptive(Motion.springRelease).delay(0.10)) {
                        scale = 1.0
                    }
                }
            }
    }
}

extension View {
    /// Adds pop-on / dip-off scale animation to reaction icons.
    func reactionPop(isActive: Bool) -> some View {
        modifier(ReactionPopModifier(isActive: isActive))
    }
}

// MARK: - H) ShakeModifier (error feedback)
// Triggered by a boolean flag. 2–3 quick horizontal oscillations, ~0.22s total.
// Caller is responsible for firing `UINotificationFeedbackGenerator(.error)`.

struct ShakeModifier: ViewModifier {
    let trigger: Bool
    @State private var offset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .onChange(of: trigger) { _, fired in
                guard fired else { return }
                guard !UIAccessibility.isReduceMotionEnabled else { return }
                let magnitude: CGFloat = 6
                // Three oscillations (6 half-cycles): each 36ms ≈ 0.22s total.
                for i in 0..<6 {
                    let delay = Double(i) * 0.036
                    let sign: CGFloat = (i % 2 == 0) ? 1 : -1
                    withAnimation(Motion.shakeLinear.delay(delay)) {
                        offset = sign * magnitude * (1 - CGFloat(i) / 8)
                    }
                }
                withAnimation(Motion.shakeLinear.delay(0.036 * 6)) {
                    offset = 0
                }
            }
    }
}

extension View {
    /// Horizontal shake on error. Pass a boolean that flips to `true` on failure.
    func shakeOnError(_ trigger: Bool) -> some View {
        modifier(ShakeModifier(trigger: trigger))
    }
}

// MARK: - Navigation Tap Guard
// Prevents double-push from rapid taps. Wrap NavigationLink / sheet toggle.

final class NavigationGuard {
    static let shared = NavigationGuard()
    private var lastFireDate: Date = .distantPast
    private let minInterval: TimeInterval = 0.35

    /// Returns true if the navigation should proceed (debounced).
    func shouldNavigate() -> Bool {
        let now = Date()
        guard now.timeIntervalSince(lastFireDate) > minInterval else { return false }
        lastFireDate = now
        return true
    }
}

// MARK: - StaggeredReveal
// Use inside a container to give children a cascading appear effect.

struct StaggeredReveal: ViewModifier {
    let index: Int
    let baseDelay: Double     // seconds between items (e.g. 0.04)
    let maxDelay: Double      // cap so deep lists don't stall (e.g. 0.20)

    private var delay: Double {
        min(Double(index) * baseDelay, maxDelay)
    }

    @State private var visible = false

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : 6)
            .animation(
                Motion.adaptive(Motion.appearEase).delay(delay),
                value: visible
            )
            .onAppear { visible = true }
    }
}

extension View {
    /// Staggered fade+slide for a list of items (e.g. comment rows).
    func staggeredReveal(index: Int, baseDelay: Double = 0.04, maxDelay: Double = 0.20) -> some View {
        modifier(StaggeredReveal(index: index, baseDelay: baseDelay, maxDelay: maxDelay))
    }
}
