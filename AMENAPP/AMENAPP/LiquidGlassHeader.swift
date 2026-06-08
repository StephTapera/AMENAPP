// LiquidGlassHeader.swift
// AMENAPP — Berean assistant chrome header.
//
// Layout (left → right):
//   [menu circle] ── [Berean capsule] ── [Pulse pill?] ── [avatar circle]
//
// Glass treatment follows DesignTokens from BereanIntelligenceContracts.swift.
// Reduces to opaque white + separator border when reduceTransparency is on.
// Haptics via HapticManager — already in the same module; no import needed.

import SwiftUI

// MARK: - LiquidGlassHeader

struct BereanLiquidGlassHeader: View {

    // MARK: - Init

    let onMenu: () -> Void
    let onAvatar: () -> Void
    let onPulse: () -> Void
    var showPulsePill: Bool = false

    // MARK: - Environment

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    // MARK: - Body

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            menuButton
            Spacer(minLength: 0)
            bereanTitlePill
            if showPulsePill {
                pulsePill
                    .transition(
                        .move(edge: .trailing)
                        .combined(with: .opacity)
                    )
            }
            Spacer(minLength: 0)
            avatarButton
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: showPulsePill)
    }

    // MARK: - Menu Button (leading)

    private var menuButton: some View {
        Button {
            HapticManager.impact(style: .light)
            onMenu()
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(.systemScaled(17, weight: .medium))
                .foregroundColor(.black.opacity(0.78))
                .frame(width: 44, height: 44)
                .background(glassCircle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Menu")
    }

    // MARK: - Berean Title Pill (center)

    private var bereanTitlePill: some View {
        HStack(spacing: 6) {
            Image(systemName: "graduationcap")
                .font(.systemScaled(13, weight: .medium))
                .foregroundColor(.black.opacity(0.64))
            Text("Berean")
                .font(.systemScaled(15, weight: .semibold))
                .foregroundColor(.black.opacity(0.76))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(glassCapsule)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Berean")
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Pulse Pill (optional center-right)

    private var pulsePill: some View {
        Button {
            HapticManager.impact(style: .light)
            onPulse()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "sparkle")
                    .font(.systemScaled(12, weight: .medium))
                    .foregroundColor(.black.opacity(0.68))
                Text("Today's Pulse")
                    .font(.systemScaled(13, weight: .medium))
                    .foregroundColor(.black.opacity(0.68))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(glassCapsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Today's Berean Pulse")
    }

    // MARK: - Avatar Button (trailing)

    private var avatarButton: some View {
        Button {
            HapticManager.impact(style: .light)
            onAvatar()
        } label: {
            ZStack {
                glassCircle
                Text("ST")
                    .font(.systemScaled(13, weight: .semibold))
                    .foregroundColor(.black.opacity(0.72))
            }
            .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Profile and settings")
    }

    // MARK: - Glass Surfaces

    /// 44 × 44 glass circle reused by menu button background.
    private var glassCircle: some View {
        Group {
            if reduceTransparency {
                Circle()
                    .fill(Color.white)
                    .overlay(
                        Circle()
                            .strokeBorder(Color(.separator), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
            } else {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(Circle().fill(Color.white.opacity(0.52)))
                    .overlay(
                        Circle().strokeBorder(Color.white.opacity(0.55), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
            }
        }
    }

    /// Capsule glass reused by title pill and pulse pill.
    private var glassCapsule: some View {
        Group {
            if reduceTransparency {
                Capsule()
                    .fill(Color.white)
                    .overlay(
                        Capsule()
                            .strokeBorder(Color(.separator), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
            } else {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().fill(Color.white.opacity(0.52)))
                    .overlay(
                        Capsule().strokeBorder(Color.white.opacity(0.55), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
            }
        }
    }
}

// MARK: - Preview

#Preview("Default — Pulse Hidden") {
    ZStack(alignment: .top) {
        Color(red: 0.971, green: 0.971, blue: 0.969).ignoresSafeArea()
        BereanLiquidGlassHeader(
            onMenu: {},
            onAvatar: {},
            onPulse: {},
            showPulsePill: false
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}

#Preview("Pulse Pill Visible") {
    ZStack(alignment: .top) {
        Color(red: 0.971, green: 0.971, blue: 0.969).ignoresSafeArea()
        BereanLiquidGlassHeader(
            onMenu: {},
            onAvatar: {},
            onPulse: {},
            showPulsePill: true
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}

#Preview("Reduce Transparency") {
    ZStack(alignment: .top) {
        Color(red: 0.971, green: 0.971, blue: 0.969).ignoresSafeArea()
        BereanLiquidGlassHeader(
            onMenu: {},
            onAvatar: {},
            onPulse: {},
            showPulsePill: true
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
        // test reduce-transparency via device Settings > Accessibility
    }
}
