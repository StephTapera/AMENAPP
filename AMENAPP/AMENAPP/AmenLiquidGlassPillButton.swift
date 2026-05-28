// AmenMediaLiquidGlassPillButton.swift
// AMEN App — Design System / Media Components
//
// Reusable Liquid Glass pill button used across the media system:
// chapter pills, action pills, caption controls, and Selah controls.
// Minimum touch target: 44pt height (WCAG 2.1 AA + Apple HIG).
// Accessibility: Reduce Motion, Reduce Transparency, Dynamic Type respected.

import SwiftUI

// MARK: - Pill Button

struct AmenMediaLiquidGlassPillButton: View {

    // MARK: Style Enum

    enum PillStyle {
        case `default`    // ultraThinMaterial bg, primary text
        case prominent    // black bg, white text, no blur
        case outline      // transparent bg, black border
        case glass        // ultraThinMaterial + subtle inner glow
    }

    // MARK: Properties

    let title: String
    var systemImage: String? = nil
    var isActive: Bool = false
    var style: PillStyle = .default
    var isDestructive: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    // MARK: Environment

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    // MARK: Body

    var body: some View {
        Button(action: {
            guard !isDisabled else { return }
            action()
        }) {
            pillLabel
        }
        .buttonStyle(AmenGlassPillPressStyle(reduceMotion: reduceMotion, isDisabled: isDisabled))
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.40 : 1.0)
        .scaleEffect(isActive && !reduceMotion ? 1.02 : 1.0)
        .animation(
            reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.80),
            value: isActive
        )
        .accessibilityLabel(title)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
        .accessibilityAddTraits(isDisabled ? [.isStaticText] : [.isButton])
        .accessibilityHint(isDisabled ? "Unavailable" : "")
    }

    // MARK: Label

    private var pillLabel: some View {
        HStack(spacing: 6) {
            if let imageName = systemImage {
                Image(systemName: imageName)
                    .font(.system(size: 14, weight: labelFontWeight))
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(.subheadline.weight(labelFontWeight))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .foregroundStyle(foregroundColor)
        .padding(.horizontal, horizontalPadding)
        .frame(minWidth: 44, minHeight: 44)
        .background(pillBackground)
        .overlay(pillBorder)
        .overlay(innerGlowOverlay)
        .contentShape(Capsule(style: .continuous))
    }

    // MARK: Foreground

    private var foregroundColor: Color {
        if isDestructive {
            return .red
        }
        switch style {
        case .default, .glass:
            return .primary
        case .prominent:
            return .white
        case .outline:
            return colorScheme == .dark ? .white : .black
        }
    }

    private var labelFontWeight: Font.Weight {
        isActive ? .semibold : .regular
    }

    private var horizontalPadding: CGFloat {
        systemImage != nil ? 14 : 18
    }

    // MARK: Background

    @ViewBuilder
    private var pillBackground: some View {
        switch style {
        case .default:
            defaultBackground

        case .prominent:
            Capsule(style: .continuous)
                .fill(Color.black)

        case .outline:
            Capsule(style: .continuous)
                .fill(Color.clear)

        case .glass:
            glassBackground
        }
    }

    @ViewBuilder
    private var defaultBackground: some View {
        if reduceTransparency {
            Capsule(style: .continuous)
                .fill(
                    isActive
                        ? Color(uiColor: .secondarySystemBackground)
                        : Color(uiColor: .systemGray6)
                )
        } else {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule(style: .continuous)
                        .fill(activeAccentFill)
                }
        }
    }

    @ViewBuilder
    private var glassBackground: some View {
        if reduceTransparency {
            Capsule(style: .continuous)
                .fill(
                    isActive
                        ? Color(uiColor: .secondarySystemBackground)
                        : Color(uiColor: .systemGray6)
                )
        } else {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule(style: .continuous)
                        .fill(activeAccentFill)
                }
        }
    }

    // Extra tint overlay when active, skip for prominent/outline which manage their own bg.
    private var activeAccentFill: Color {
        guard isActive else { return .clear }
        return Color.white.opacity(0.10)
    }

    // MARK: Border

    @ViewBuilder
    private var pillBorder: some View {
        switch style {
        case .outline:
            Capsule(style: .continuous)
                .strokeBorder(
                    colorScheme == .dark ? Color.white.opacity(0.70) : Color.black.opacity(0.78),
                    lineWidth: 1.5
                )
        case .glass:
            if !reduceTransparency {
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(isActive ? 0.55 : 0.28), lineWidth: 0.8)
            } else {
                EmptyView()
            }
        case .default:
            if !reduceTransparency {
                Capsule(style: .continuous)
                    .strokeBorder(
                        Color.white.opacity(isActive ? 0.45 : 0.20),
                        lineWidth: 0.6
                    )
            } else {
                EmptyView()
            }
        case .prominent:
            EmptyView()
        }
    }

    // MARK: Inner Glow (glass style only)

    @ViewBuilder
    private var innerGlowOverlay: some View {
        if style == .glass && !reduceTransparency {
            // Subtle top-edge specular shimmer
            VStack {
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.42),
                                Color.white.opacity(0.0)
                            ],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
                    .frame(height: 10)
                    .padding(.horizontal, 18)
                    .padding(.top, 4)
                Spacer()
            }
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Press Style

private struct AmenGlassPillPressStyle: ButtonStyle {
    let reduceMotion: Bool
    let isDisabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(
                (configuration.isPressed && !reduceMotion && !isDisabled) ? 0.96 : 1.0
            )
            .animation(
                reduceMotion ? nil : .spring(response: 0.16, dampingFraction: 0.68),
                value: configuration.isPressed
            )
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Default — inactive / active") {
    VStack(spacing: 16) {
        HStack(spacing: 10) {
            AmenMediaLiquidGlassPillButton(title: "Pray", systemImage: "hands.sparkles", isActive: false, style: .default, action: {})
            AmenMediaLiquidGlassPillButton(title: "Pray", systemImage: "hands.sparkles", isActive: true,  style: .default, action: {})
        }
        HStack(spacing: 10) {
            AmenMediaLiquidGlassPillButton(title: "Scripture", isActive: false, style: .default, action: {})
            AmenMediaLiquidGlassPillButton(title: "Scripture", isActive: true,  style: .default, action: {})
        }
    }
    .padding()
    .background(Color(.systemBackground))
}

#Preview("Prominent style") {
    HStack(spacing: 10) {
        AmenMediaLiquidGlassPillButton(title: "Save", systemImage: "bookmark.fill", style: .prominent, action: {})
        AmenMediaLiquidGlassPillButton(title: "Share",                              style: .prominent, action: {})
    }
    .padding()
    .background(Color(.systemBackground))
}

#Preview("Outline style") {
    HStack(spacing: 10) {
        AmenMediaLiquidGlassPillButton(title: "Reflect", style: .outline, action: {})
        AmenMediaLiquidGlassPillButton(title: "Reply", isActive: true, style: .outline, action: {})
    }
    .padding()
    .background(Color(.systemBackground))
}

#Preview("Glass style (media chrome)") {
    ZStack {
        LinearGradient(colors: [.indigo, .purple], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                AmenMediaLiquidGlassPillButton(title: "Selah",    systemImage: "moon.stars.fill", isActive: true,  style: .glass, action: {})
                AmenMediaLiquidGlassPillButton(title: "Captions", systemImage: "captions.bubble", isActive: false, style: .glass, action: {})
            }
            HStack(spacing: 10) {
                AmenMediaLiquidGlassPillButton(title: "Worship", systemImage: "music.note", isActive: false, style: .glass, action: {})
            }
        }
    }
}

#Preview("Destructive") {
    AmenMediaLiquidGlassPillButton(title: "Remove", systemImage: "trash", style: .outline, isDestructive: true, action: {})
        .padding()
}

#Preview("Disabled") {
    HStack(spacing: 10) {
        AmenMediaLiquidGlassPillButton(title: "Save",  style: .default,   isDisabled: true, action: {})
        AmenMediaLiquidGlassPillButton(title: "Share", style: .prominent, isDisabled: true, action: {})
    }
    .padding()
}

#Preview("Reduce Transparency") {
    HStack(spacing: 10) {
        AmenMediaLiquidGlassPillButton(title: "Prayer",    isActive: false, style: .default,   action: {})
        AmenMediaLiquidGlassPillButton(title: "Scripture", isActive: true,  style: .default,   action: {})
        AmenMediaLiquidGlassPillButton(title: "Save",                       style: .prominent, action: {})
    }
    .padding()
    .background(Color(.systemBackground))
}

#Preview("Dark Mode — Glass") {
    ZStack {
        Color.black.ignoresSafeArea()
        HStack(spacing: 10) {
            AmenMediaLiquidGlassPillButton(title: "Selah",    systemImage: "moon.stars.fill", isActive: true,  style: .glass, action: {})
            AmenMediaLiquidGlassPillButton(title: "Captions", systemImage: "captions.bubble", isActive: false, style: .glass, action: {})
            AmenMediaLiquidGlassPillButton(title: "Follow",   style: .outline, action: {})
        }
    }
    .environment(\.colorScheme, .dark)
}
#endif
