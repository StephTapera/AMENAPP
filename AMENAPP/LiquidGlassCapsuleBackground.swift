//
//  LiquidGlassCapsuleBackground.swift
//  AMENAPP
//
//  Reusable white liquid-glass capsule shell for floating controls.
//

import SwiftUI

struct LiquidGlassCapsuleBackground: View {
    var cornerRadius: CGFloat = 28
    /// White glass overlay opacity. Keep low on white backgrounds so the
    /// material blur is visible and the capsule doesn't read as a flat white card.
    var glassOpacity: Double = 0.06
    var shadowOpacity: Double = 0.13
    var highlightOpacity: Double = 0.26

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                // Whisper-light directional tint — does NOT cover the material blur.
                // glassOpacity must stay below 0.10 on white backgrounds or the
                // capsule reads as a matte white card instead of glass.
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(glassOpacity * 0.65),
                                Color.white.opacity(glassOpacity * 0.30),
                                Color(red: 1.0, green: 0.96, blue: 0.92).opacity(glassOpacity * 0.12)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            // Border: white top-leading highlight + dark bottom-trailing definition.
            // The dark component is critical on white backgrounds — without it the
            // border is white-on-white and the capsule has no visible edge.
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.60),
                                Color.white.opacity(0.22),
                                Color.black.opacity(0.07),
                                Color.black.opacity(0.09)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.9
                    )
            )
            // Top-edge glow: the single strongest cue that this is glass, not paper.
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(highlightOpacity),
                                Color.white.opacity(0.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1.2
                    )
                    .blur(radius: 0.4)
                    .padding(1)
                    .allowsHitTesting(false)
            }
            // Top-left specular sheen — directional light catch
            .overlay(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(highlightOpacity * 0.85),
                                Color.white.opacity(0.04),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .padding(1)
                    .blendMode(.screen)
                    .allowsHitTesting(false)
            }
            // Warm bottom-trailing counter-light
            .overlay(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.98, green: 0.88, blue: 0.82).opacity(0.11),
                                Color.clear
                            ],
                            center: .bottomTrailing,
                            startRadius: 12,
                            endRadius: 120
                        )
                    )
                    .blendMode(.screen)
                    .allowsHitTesting(false)
            }
            // Lift shadow — depth and float
            .shadow(color: Color.black.opacity(shadowOpacity), radius: 28, x: 0, y: 14)
            // Contact shadow — grounds the capsule
            .shadow(color: Color.black.opacity(shadowOpacity * 0.50), radius: 8, x: 0, y: 3)
    }
}
