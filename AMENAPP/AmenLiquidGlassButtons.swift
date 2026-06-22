//
//  AmenLiquidGlassButtons.swift
//  AMENAPP
//
//  Apple-style Liquid Glass button system — App Store tab bar feel.
//
//  Visual language:
//   - Translucent white material backgrounds
//   - Soft frosted blur (.regularMaterial / .ultraThinMaterial)
//   - Subtle stroke + soft low shadow
//   - Black icons/text by default, AMEN blue accent for selected/primary
//   - Calm press feedback (~0.97 scale), no glow, no gradients
//   - Respects Reduce Motion + Reduce Transparency + Dynamic Type
//
//  Usage:
//    AmenLiquidGlassIconButton(systemName: "bookmark", title: "Save post") {
//        savePost()
//    }
//
//    AmenLiquidGlassCapsuleButton(title: "Ask Berean",
//                                 systemImage: "sparkles",
//                                 variant: .primary) {
//        askBerean()
//    }
//
//    AmenLiquidGlassControlGroup(
//        items: tabs,
//        selection: $selectedTab
//    )
//

import SwiftUI

// MARK: - Tokens

enum AmenLiquidGlass {
    static let accent: Color = Color(red: 0.0, green: 0.48, blue: 1.0) // iOS blue, matches App Store
    static let minTapTarget: CGFloat = 44

    enum Size {
        case small      // 32 icon, 36 height
        case medium     // 40 icon, 44 height
        case large      // 48 icon, 52 height

        var height: CGFloat {
            switch self {
            case .small: return 36
            case .medium: return 44
            case .large: return 52
            }
        }

        var horizontalPadding: CGFloat {
            switch self {
            case .small: return 12
            case .medium: return 16
            case .large: return 20
            }
        }

        var iconFont: Font {
            switch self {
            case .small: return .systemScaled(14, weight: .semibold)
            case .medium: return .systemScaled(16, weight: .semibold)
            case .large: return .systemScaled(18, weight: .semibold)
            }
        }

        var labelFont: Font {
            switch self {
            case .small: return .systemScaled(13, weight: .semibold)
            case .medium: return .systemScaled(15, weight: .semibold)
            case .large: return .systemScaled(17, weight: .semibold)
            }
        }
    }

    enum Variant {
        case `default`   // translucent white, primary label
        case primary     // filled accent, white label
        case selected    // denser glass + accent label
        case subtle      // lighter glass, secondary label
        case destructive // red label, glass background — confirmation must still gate the action
    }
}

// MARK: - Press Style

struct AmenLiquidGlassPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.85),
                       value: configuration.isPressed)
    }
}

// MARK: - Background

private struct AmenLiquidGlassBackground: View {
    let variant: AmenLiquidGlass.Variant
    let isSelected: Bool
    let shape: AnyShape

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            if reduceTransparency {
                shape.fill(solidFallback)
            } else {
                shape.fill(.regularMaterial)
                shape.fill(tint)
            }
            shape
                .stroke(strokeColor, lineWidth: 0.5)
        }
        .compositingGroup()
        .shadow(color: .black.opacity(shadowOpacity), radius: 6, y: 2)
    }

    private var tint: Color {
        switch variant {
        case .primary:
            return AmenLiquidGlass.accent
        case .selected:
            return AmenLiquidGlass.accent.opacity(0.12)
        case .destructive:
            return Color.red.opacity(0.08)
        case .subtle:
            return Color.white.opacity(0.06)
        case .default:
            return isSelected ? AmenLiquidGlass.accent.opacity(0.12) : Color.white.opacity(0.18)
        }
    }

    private var solidFallback: Color {
        switch variant {
        case .primary: return AmenLiquidGlass.accent
        case .selected: return Color(.secondarySystemBackground)
        case .destructive: return Color(.secondarySystemBackground)
        case .subtle: return Color(.tertiarySystemBackground)
        case .default: return Color(.secondarySystemBackground)
        }
    }

    private var strokeColor: Color {
        if variant == .primary { return Color.white.opacity(0.18) }
        return colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
    }

    private var shadowOpacity: Double {
        variant == .primary ? 0.12 : 0.05
    }
}

// MARK: - Icon Button

struct AmenLiquidGlassIconButton: View {
    let systemName: String
    let title: String                       // accessibility label
    var isSelected: Bool = false
    var size: AmenLiquidGlass.Size = .medium
    var variant: AmenLiquidGlass.Variant = .default
    var action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(size.iconFont)
                .foregroundStyle(foreground)
                .frame(width: max(size.height, AmenLiquidGlass.minTapTarget),
                       height: max(size.height, AmenLiquidGlass.minTapTarget))
                .background(
                    AmenLiquidGlassBackground(
                        variant: variant,
                        isSelected: isSelected,
                        shape: AnyShape(Circle())
                    )
                )
                .opacity(isEnabled ? 1.0 : 0.4)
        }
        .buttonStyle(AmenLiquidGlassPressStyle())
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var foreground: Color {
        switch variant {
        case .primary: return .white
        case .selected: return AmenLiquidGlass.accent
        case .destructive: return .red
        case .subtle: return .secondary
        case .default: return isSelected ? AmenLiquidGlass.accent : .primary
        }
    }
}

// MARK: - Capsule Button

struct AmenLiquidGlassCapsuleButton: View {
    let title: String
    var systemImage: String? = nil
    var variant: AmenLiquidGlass.Variant = .default
    var size: AmenLiquidGlass.Size = .medium
    var isSelected: Bool = false
    var isLoading: Bool = false
    var action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(foreground)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(size.iconFont)
                }
                Text(title)
                    .font(size.labelFont)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, size.horizontalPadding)
            .frame(minHeight: max(size.height, AmenLiquidGlass.minTapTarget))
            .background(
                AmenLiquidGlassBackground(
                    variant: variant,
                    isSelected: isSelected,
                    shape: AnyShape(Capsule(style: .continuous))
                )
            )
            .opacity(isEnabled ? 1.0 : 0.45)
        }
        .buttonStyle(AmenLiquidGlassPressStyle())
        .disabled(isLoading)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var foreground: Color {
        switch variant {
        case .primary: return .white
        case .selected: return AmenLiquidGlass.accent
        case .destructive: return .red
        case .subtle: return .secondary
        case .default: return isSelected ? AmenLiquidGlass.accent : .primary
        }
    }
}

// MARK: - Control Group (App Store-style segmented capsule)

/// A horizontal group of items inside a single capsule glass container — the visual
/// language from the App Store tab bar. One item is highlighted at a time.
struct AmenLiquidGlassControlGroup<Value: Hashable>: View {
    struct Item: Identifiable {
        let id: Value
        let systemImage: String
        let title: String
    }

    let items: [Item]
    @Binding var selection: Value
    var size: AmenLiquidGlass.Size = .medium

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionNamespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items) { item in
                Button {
                    if reduceMotion {
                        selection = item.id
                    } else {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                            selection = item.id
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: item.systemImage)
                            .font(size.iconFont)
                        Text(item.title)
                            .font(size.labelFont)
                            .lineLimit(1)
                    }
                    .foregroundStyle(selection == item.id ? AmenLiquidGlass.accent : Color.primary)
                    .padding(.horizontal, size.horizontalPadding)
                    .frame(height: size.height)
                    .background(
                        ZStack {
                            if selection == item.id {
                                Capsule(style: .continuous)
                                    .fill(AmenLiquidGlass.accent.opacity(0.14))
                                    .matchedGeometryEffect(id: "amen.liquid.glass.selected", in: selectionNamespace)
                            }
                        }
                    )
                }
                .buttonStyle(AmenLiquidGlassPressStyle())
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(selection == item.id ? .isSelected : [])
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            AmenLiquidGlassBackground(
                variant: .default,
                isSelected: false,
                shape: AnyShape(Capsule(style: .continuous))
            )
        )
    }
}

// MARK: - View Modifier convenience

extension View {
    /// Convenience: wrap any tappable view in a Liquid Glass capsule background.
    /// Prefer the dedicated `AmenLiquidGlass*Button` types for new code — this
    /// modifier exists for restyling existing custom buttons without rewiring them.
    func amenLiquidGlassCapsule(variant: AmenLiquidGlass.Variant = .default,
                                isSelected: Bool = false) -> some View {
        self.background(
            AmenLiquidGlassBackground(
                variant: variant,
                isSelected: isSelected,
                shape: AnyShape(Capsule(style: .continuous))
            )
        )
    }
}

#if DEBUG
#Preview("Liquid Glass — Light") {
    VStack(spacing: 24) {
        HStack(spacing: 12) {
            AmenLiquidGlassIconButton(systemName: "bookmark", title: "Save post") {}
            AmenLiquidGlassIconButton(systemName: "heart.fill", title: "Liked", isSelected: true) {}
            AmenLiquidGlassIconButton(systemName: "square.and.arrow.up", title: "Share") {}
            AmenLiquidGlassIconButton(systemName: "trash", title: "Delete", variant: .destructive) {}
        }
        AmenLiquidGlassCapsuleButton(title: "Ask Berean", systemImage: "sparkles", variant: .primary) {}
        AmenLiquidGlassCapsuleButton(title: "Comment", systemImage: "bubble.left") {}
        AmenLiquidGlassCapsuleButton(title: "Working…", systemImage: "sparkles", isLoading: true) {}
        AmenLiquidGlassControlGroup(
            items: [
                .init(id: "today", systemImage: "sun.max", title: "Today"),
                .init(id: "games", systemImage: "gamecontroller", title: "Games"),
                .init(id: "apps", systemImage: "square.grid.2x2", title: "Apps")
            ],
            selection: .constant("today")
        )
    }
    .padding(40)
    .background(LinearGradient(colors: [.white, Color(.systemGray6)], startPoint: .top, endPoint: .bottom))
}
#endif
