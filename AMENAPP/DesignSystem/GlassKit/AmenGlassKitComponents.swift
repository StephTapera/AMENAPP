// AmenGlassKitComponents.swift
// AMENAPP — DesignSystem/GlassKit
//
// Supplemental Liquid Glass components.
// Lives alongside (not inside) the frozen AmenGlassKit.swift.

import SwiftUI

// ─────────────────────────────────────────────────────────────────
// MARK: - AmenGlassLoadingSkeleton
// ─────────────────────────────────────────────────────────────────

/// Shimmering glass skeleton placeholder used while content loads.
struct AmenGlassLoadingSkeleton: View {
    var cornerRadius: CGFloat = 14
    var height: CGFloat = 80

    @State private var phase: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay {
                if !reduceMotion {
                    GeometryReader { geo in
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0),
                                Color.white.opacity(0.25),
                                Color.white.opacity(0)
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: geo.size.width * 0.5)
                        .offset(x: phase * geo.size.width * 1.5)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    }
                }
            }
            .frame(height: height)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

// ─────────────────────────────────────────────────────────────────
// MARK: - AmenFloatingGlassBackButton
// ─────────────────────────────────────────────────────────────────

/// Circular glass back button for full-screen media viewers (PhotoZoomView, ViewOnceViewerView).
struct AmenFloatingGlassBackButton: View {
    var action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
        }
        .buttonStyle(GlassKitPressStyle(reduceMotion: reduceMotion))
        .accessibilityLabel("Back")
    }
}
