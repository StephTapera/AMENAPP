//
//  ComposerActionButton.swift
//  AMENAPP
//
//  Reusable liquid-glass circle button for the Berean composer bar.
//  Matches the material family of LiquidGlassCapsuleBackground —
//  white glass fill, thin border, no opaque backgrounds.
//

import SwiftUI

/// A circular glass action button for use inside BereanComposerBar.
///
/// Scales icon and frame with `collapseProgress` so the button
/// smoothly densifies as the composer compacts on scroll.
struct ComposerActionButton: View {
    let icon: String
    let size: CGFloat
    let iconSize: CGFloat
    let iconColor: Color
    let accessibilityLabel: String
    let accessibilityHint: String
    let action: () -> Void

    init(
        icon: String,
        size: CGFloat = 38,
        iconSize: CGFloat = 18,
        iconColor: Color = BereanColor.textPrimary.opacity(0.72),
        accessibilityLabel: String = "",
        accessibilityHint: String = "",
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.size = size
        self.iconSize = iconSize
        self.iconColor = iconColor
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityHint = accessibilityHint
        self.action = action
    }

    var body: some View {
        Button {
            action()
        } label: {
            Image(systemName: icon)
                .font(.systemScaled(iconSize, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: size, height: size)
                .background(
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.36),
                                    Color.white.opacity(0.24),
                                    Color(red: 1.0, green: 0.96, blue: 0.93).opacity(0.16)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            Circle()
                                .strokeBorder(Color.white.opacity(0.45), lineWidth: 0.7)
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
    }
}

/// Variant with interpolated size for scroll-collapse transitions.
struct ComposerScaledActionButton: View {
    let icon: String
    let expandedSize: CGFloat
    let compactSize: CGFloat
    let expandedIconSize: CGFloat
    let compactIconSize: CGFloat
    let iconColor: Color
    let collapseProgress: CGFloat
    let accessibilityLabel: String
    let accessibilityHint: String
    let action: () -> Void

    private func interpolate(_ start: CGFloat, _ end: CGFloat) -> CGFloat {
        start + (end - start) * min(max(collapseProgress, 0), 1)
    }

    var body: some View {
        let size = interpolate(expandedSize, compactSize)
        let iconSz = interpolate(expandedIconSize, compactIconSize)

        Button {
            action()
        } label: {
            Image(systemName: icon)
                .font(.systemScaled(iconSz, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: size, height: size)
                .background(
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(interpolate(0.36, 0.40)),
                                    Color.white.opacity(interpolate(0.24, 0.28)),
                                    Color(red: 1.0, green: 0.96, blue: 0.93).opacity(interpolate(0.16, 0.14))
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            Circle()
                                .strokeBorder(Color.white.opacity(interpolate(0.45, 0.40)), lineWidth: 0.7)
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
    }
}
