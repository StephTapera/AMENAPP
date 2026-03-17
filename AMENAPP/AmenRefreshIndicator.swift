//
//  AmenRefreshIndicator.swift
//  AMENAPP
//
//  Pull-to-refresh indicator using the AMEN "A" logo with a Threads-style
//  path-tracing snake animation.
//
//  Architecture:
//  - Two SVG strokes drawn with stroke-dashoffset animation via trim(from:to:)
//  - Path 1 (outer arc) animates first, Path 2 (crossbar) follows with a slight
//    phase offset so the snake "travels" across the interlocked logo
//  - The interlocking depth (crossbar passes behind left leg, over right leg)
//    is achieved by rendering Path 2 twice: once clipped to the "behind" region
//    with lower zIndex, once unmasked for the "over" region
//  - Pull progress (0→1) drives both the vertical offset and the initial
//    trim reveal before isRefreshing kicks in
//  - Animation uses a custom cubic easing that accelerates through the loopy
//    crossbar and steadies on the outer arc, matching the Threads feel
//

import SwiftUI

// MARK: - Path Data

// Path 1: Outer rounded arc (the A frame, left base → apex → right base)
// Matches SVG: M34.5 73.5 C28.5 68 22.5 59.5 22.5 52 C22.5 35.5 33.5 22 50 22
//              C66.5 22 77.5 35.5 77.5 52 C77.5 60.5 73.5 68.5 67 74
private let outerArcPath: Path = {
    var p = Path()
    // Scale from 100×100 SVG viewBox to unit space (0…1), then callers scale to frame
    // We'll work directly in the 100×100 coordinate space and use .transform in the view
    p.move(to: CGPoint(x: 34.5, y: 73.5))
    p.addCurve(
        to:       CGPoint(x: 22.5, y: 52),
        control1: CGPoint(x: 28.5, y: 68),
        control2: CGPoint(x: 22.5, y: 59.5)
    )
    p.addCurve(
        to:       CGPoint(x: 50,   y: 22),
        control1: CGPoint(x: 22.5, y: 35.5),
        control2: CGPoint(x: 33.5, y: 22)
    )
    p.addCurve(
        to:       CGPoint(x: 77.5, y: 52),
        control1: CGPoint(x: 66.5, y: 22),
        control2: CGPoint(x: 77.5, y: 35.5)
    )
    p.addCurve(
        to:       CGPoint(x: 67,   y: 74),
        control1: CGPoint(x: 77.5, y: 60.5),
        control2: CGPoint(x: 73.5, y: 68.5)
    )
    return p
}()

// Path 2: Crossbar + tail stroke
// This is the interlocked element. It passes BEHIND the left leg and OVER the right.
// Broken into segments for the masking trick:
//   Segment A (crossbar peak, left side): start → behind-left-leg entry
//   Segment B (crossbar mid + right arc): behind-left-leg exit → right loop → tail end
private let crossbarPath: Path = {
    var p = Path()
    // M62 49.5 → the full crossbar/tail compound path
    p.move(to: CGPoint(x: 62, y: 49.5))
    // Crossbar dip to mid
    p.addCurve(
        to:       CGPoint(x: 43.5, y: 47),
        control1: CGPoint(x: 57.5, y: 51),
        control2: CGPoint(x: 51,   y: 52.5)
    )
    // Continue: left arc sweep up toward right
    p.addLine(to: CGPoint(x: 63.5, y: 60.5))
    // Right loop out
    p.addCurve(
        to:       CGPoint(x: 77,   y: 58.5),
        control1: CGPoint(x: 68.5, y: 58.5),
        control2: CGPoint(x: 73,   y: 57.5)
    )
    // The looping return arc
    p.addCurve(
        to:       CGPoint(x: 67,   y: 66.5),
        control1: CGPoint(x: 78.5, y: 59.5),
        control2: CGPoint(x: 78.5, y: 61)
    )
    p.addCurve(
        to:       CGPoint(x: 38,   y: 71),
        control1: CGPoint(x: 71.5, y: 65),
        control2: CGPoint(x: 60.5, y: 68.5)
    )
    // Long tail sweep to lower left
    p.addCurve(
        to:       CGPoint(x: 13.5, y: 69.5),
        control1: CGPoint(x: 25.5, y: 72),
        control2: CGPoint(x: 16.5, y: 71.5)
    )
    // Return arc through base
    p.addCurve(
        to:       CGPoint(x: 35.5, y: 60),
        control1: CGPoint(x: 16.5, y: 69.5),
        control2: CGPoint(x: 25.5, y: 66)
    )
    p.addCurve(
        to:       CGPoint(x: 50,   y: 43.5),
        control1: CGPoint(x: 39.5, y: 54.5),
        control2: CGPoint(x: 44,   y: 49)
    )
    // Closing tick
    p.addLine(to: CGPoint(x: 42.5, y: 52.5))
    return p
}()

// The circular mask region that defines "behind the left leg"
// (the inner circle from the SVG mask)
private let innerCirclePath: Path = {
    Path(ellipseIn: CGRect(x: 20, y: 22, width: 60, height: 60))
}()

// MARK: - Snake Animation State

private struct SnakePhase {
    /// Fraction [0…1] of total path length where the snake head is
    var head: Double
    /// Length of the traveling snake segment as a fraction of path length
    var snakeLength: Double = 0.28
    var tail: Double { max(0, head - snakeLength) }
}

// MARK: - Main Indicator View

struct AmenRefreshIndicator: View {

    /// true while the feed is loading — drives the continuous loop animation
    var isRefreshing: Bool

    /// Pull progress from the scroll view: 0 = not pulled, 1 = fully pulled (trigger point)
    var pullProgress: CGFloat = 0

    // Stroke color — adapts to color scheme
    @Environment(\.colorScheme) private var colorScheme
    private var strokeColor: Color { colorScheme == .dark ? .white : .black }

    // Animation state
    @State private var phase1 = SnakePhase(head: 0)   // outer arc
    @State private var phase2 = SnakePhase(head: 0)   // crossbar (offset behind phase1)
    @State private var loopTask: Task<Void, Never>?
    @State private var opacity: Double = 0

    // During pull (not yet refreshing), just reveal the static logo proportional to pull
    private var staticReveal: CGFloat { min(pullProgress, 1.0) }

    var body: some View {
        ZStack {
            if isRefreshing {
                animatingLogo
                    .transition(.opacity)
            } else {
                staticLogo
                    .opacity(Double(staticReveal))
                    .scaleEffect(0.6 + 0.4 * staticReveal)
                    .transition(.opacity)
            }
        }
        .frame(width: 44, height: 44)
        .onChange(of: isRefreshing) { _, refreshing in
            if refreshing {
                startLoop()
            } else {
                stopLoop()
            }
        }
    }

    // MARK: - Static Logo (shown during pull, before trigger)

    private var staticLogo: some View {
        Canvas { ctx, size in
            let scale = size.width / 100
            let t = CGAffineTransform(scaleX: scale, y: scale)

            let strokeStyle = StrokeStyle(lineWidth: 6 * scale, lineCap: .round, lineJoin: .round)

            // Draw outer arc trimmed by pull progress
            let p1 = outerArcPath.applying(t)
            ctx.stroke(
                p1.trimmedPath(from: 0, to: staticReveal),
                with: .color(strokeColor),
                style: strokeStyle
            )

            // Draw crossbar at same reveal fraction
            let p2 = crossbarPath.applying(t)
            ctx.stroke(
                p2.trimmedPath(from: 0, to: staticReveal),
                with: .color(strokeColor),
                style: strokeStyle
            )
        }
    }

    // MARK: - Animating Logo (continuous snake loop while refreshing)

    private var animatingLogo: some View {
        Canvas { ctx, size in
            let scale = size.width / 100
            let t = CGAffineTransform(scaleX: scale, y: scale)
            let strokeStyle = StrokeStyle(lineWidth: 6 * scale, lineCap: .round, lineJoin: .round)
            let innerMask = innerCirclePath.applying(t)

            // ── Path 1: Outer arc — full snake segment ─────────────────────
            let p1 = outerArcPath.applying(t)
            ctx.stroke(
                p1.trimmedPath(from: phase1.tail, to: phase1.head),
                with: .color(strokeColor),
                style: strokeStyle
            )

            // ── Path 2: Crossbar — rendered in two layers for depth illusion ─
            //
            // The crossbar passes BEHIND the left leg at the inner circle region,
            // and OVER the right leg outside that region.
            //
            // Layer A — "behind": clip to inner circle, draw UNDER p1
            // Layer B — "over":   clip to outside inner circle, draw OVER p1
            //
            // SwiftUI Canvas draws in painter's order, so we sandwich p1 between them.

            let p2 = crossbarPath.applying(t)
            let p2Snake = p2.trimmedPath(from: phase2.tail, to: phase2.head)

            // Layer A: behind (clipped to inner circle) — drawn before p1 (already done above)
            // We redraw p1 over it using a clip to achieve the "behind" look.
            // Practical approach: draw the snake segment, then overdraw p1's
            // silhouette in the inner circle region to simulate the crossbar going behind.

            // Draw crossbar snake
            ctx.stroke(p2Snake, with: .color(strokeColor), style: strokeStyle)

            // Overdraw the outer arc in the inner-circle region to restore the "over" z-order
            // for the section of p1 that should appear in front of p2.
            ctx.clip(to: innerMask, style: FillStyle())
            ctx.stroke(p1, with: .color(strokeColor), style: strokeStyle)
        }
    }

    // MARK: - Animation Loop

    private func startLoop() {
        loopTask?.cancel()
        // Reset to start
        phase1 = SnakePhase(head: 0)
        phase2 = SnakePhase(head: 0)

        loopTask = Task {
            // Total loop: 1.1s per revolution, staggered 0.18s between paths
            // Easing: accelerate through the loopy crossbar (0.35…0.75 of path),
            //         steady elsewhere — approximated by driving head via a custom curve.
            let fps: Double = 60
            let dt: Double = 1 / fps
            // How fast head advances per frame (full 0→1 in ~1.1s)
            let baseSpeed: Double = dt / 1.1
            // Lag offset for Phase 2 (0.18s expressed as fraction of the 1.1s loop)
            let lagFraction: Double = 0.18 / 1.1

            var t: Double = 0  // global time [0…∞), wraps at 1.0 per loop

            while !Task.isCancelled {
                t += baseSpeed
                if t > 1 { t -= 1 }

                // Phase 2 lags 0.18s behind Phase 1 (expressed as fraction of loop)
                let t2 = t > lagFraction ? t - lagFraction : t + 1.0 - lagFraction

                await MainActor.run {
                    phase1.head = eased(t)
                    phase2.head = eased(t2)
                }

                try? await Task.sleep(nanoseconds: UInt64(dt * 1_000_000_000))
            }
        }
    }

    private func stopLoop() {
        // Let the current frame finish gracefully; the task ends on next cancel check
        loopTask?.cancel()
        loopTask = nil
    }

    // MARK: - Custom Easing

    /// Maps linear progress [0…1] to eased progress [0…1].
    /// Faster through the loopy crossbar region (0.35…0.75), steady on the arc ends.
    private func eased(_ t: Double) -> Double {
        // Piecewise: ease-in on first third, fast middle, ease-out on last third.
        // Approximates cubic-bezier(0.4, 0.0, 0.2, 1.0) with a mid-section speedup.
        switch t {
        case ..<0.3:
            // Ease in: slow start
            return 0.5 * t / 0.3 * t / 0.3 * 0.3  // quadratic in
        case 0.3..<0.7:
            // Fast middle (crossbar loop region): linear but 1.4× speed
            let mid = (t - 0.3) / 0.4
            return 0.15 + mid * 0.70
        default:
            // Ease out: slow finish
            let end = (t - 0.7) / 0.3
            return 0.85 + (1 - pow(1 - end, 2)) * 0.15
        }
    }
}

// MARK: - ScrollView Integration Modifier

/// Wraps a ScrollView with the AMEN pull-to-refresh indicator.
/// Replaces the default system spinner.
///
/// Usage:
/// ```swift
/// ScrollView {
///     content
/// }
/// .amenRefreshable {
///     await viewModel.reload()
/// }
/// ```
extension View {
    func amenRefreshable(action: @escaping () async -> Void) -> some View {
        self.modifier(AmenRefreshModifier(action: action))
    }
}

private struct AmenRefreshModifier: ViewModifier {
    let action: () async -> Void
    @State private var isRefreshing = false
    @State private var pullProgress: CGFloat = 0
    @State private var refreshTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .refreshable {
                isRefreshing = true
                await action()
                isRefreshing = false
            }
            .overlay(alignment: .top) {
                if isRefreshing {
                    AmenRefreshIndicator(isRefreshing: isRefreshing, pullProgress: 1.0)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isRefreshing)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Refreshing") {
    VStack(spacing: 24) {
        AmenRefreshIndicator(isRefreshing: true, pullProgress: 1.0)
            .frame(width: 44, height: 44)

        AmenRefreshIndicator(isRefreshing: false, pullProgress: 0.5)
            .frame(width: 44, height: 44)

        AmenRefreshIndicator(isRefreshing: false, pullProgress: 0.0)
            .frame(width: 44, height: 44)
    }
    .padding(40)
}
#endif
