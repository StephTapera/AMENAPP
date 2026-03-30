// AmbientOrbBackground.swift
// AMEN App — Reusable animated orb background for AutoLoginSplashView
// Uses TimelineView + Canvas for smooth, non-blocking animation

import SwiftUI

struct AmbientOrbBackground: View {
    // Slow sine-wave drift state
    @State private var phase: Double = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            Canvas { ctx, size in
                let t = context.date.timeIntervalSinceReferenceDate
                drawOrb(ctx, size: size, t: t, index: 0)
                drawOrb(ctx, size: size, t: t, index: 1)
                drawOrb(ctx, size: size, t: t, index: 2)
            }
            .drawingGroup()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func drawOrb(_ ctx: GraphicsContext, size: CGSize, t: TimeInterval, index: Int) {
        let configs: [(baseX: Double, baseY: Double, radius: Double, color: Color, speed: Double, amp: Double)] = [
            (0.25, 0.30, 280, Color(red: 0.38, green: 0.36, blue: 0.90), 0.18, 60),  // indigo
            (0.75, 0.65, 240, Color(red: 0.55, green: 0.25, blue: 0.80), 0.12, 50),  // purple
            (0.50, 0.80, 200, Color(red: 0.20, green: 0.20, blue: 0.70), 0.22, 40),  // deep indigo
        ]

        let c = configs[index]
        let offsetX = sin(t * c.speed + Double(index) * 1.3) * c.amp
        let offsetY = cos(t * c.speed * 0.7 + Double(index) * 0.9) * c.amp * 0.6
        let cx = size.width * c.baseX + offsetX
        let cy = size.height * c.baseY + offsetY

        let rect = CGRect(
            x: cx - c.radius,
            y: cy - c.radius,
            width: c.radius * 2,
            height: c.radius * 2
        )

        var innerCtx = ctx
        innerCtx.opacity = 0.15
        innerCtx.fill(Path(ellipseIn: rect), with: .color(c.color))
    }
}
