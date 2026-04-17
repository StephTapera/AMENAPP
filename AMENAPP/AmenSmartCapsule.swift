// AmenSmartCapsule.swift
// AMEN App — Unified Liquid Glass search/input capsule system
//
// Shared base component for all search/input surfaces.
// Configurable per-screen via AmenCapsuleStyle presets.
// Visual DNA: white fill + ultraThinMaterial + gradient stroke + soft shadow.

import SwiftUI

// MARK: - Capsule Configuration

/// Style preset controlling visual and behavioral knobs.
struct AmenCapsuleStyle {
    var cornerRadius: CGFloat = AmenRadius.composer
    var height: CGFloat = 52
    var fillOpacity: CGFloat = AmenOpacity.glassFill
    var focusedFillOpacity: CGFloat = AmenOpacity.glassFillFocused
    var shadowRadius: CGFloat = 16
    var focusedShadowRadius: CGFloat = 32
    var shadowOpacity: CGFloat = AmenOpacity.shadowIdle
    var focusedShadowOpacity: CGFloat = AmenOpacity.shadowFocused
    var useCapsuleShape: Bool = true          // true = Capsule, false = RoundedRect
    var placeholderColor: Color = AmenColor.titleText.opacity(AmenOpacity.placeholderText)
    var textColor: Color = AmenColor.titleText
    var showsClearButton: Bool = true
    var focusLiftOffset: CGFloat = -3
    var focusLiftScale: CGFloat = 1.008
    var iconName: String = "magnifyingglass"
    var iconColor: Color = AmenColor.mutedText

    // Dark variant for Settings
    var isDarkMode: Bool = false
    var darkPanelColor: Color = Color(red: 0.12, green: 0.12, blue: 0.13)
    var darkBorderColor: Color = Color.white.opacity(0.07)
    var darkTextColor: Color = Color(white: 0.95)
    var darkPlaceholderColor: Color = Color(white: 0.45)
    var darkIconColor: Color = Color(white: 0.5)
}

// MARK: - Style Presets

extension AmenCapsuleStyle {
    /// Discover search bar — capsule pill, standard glass
    static let discover = AmenCapsuleStyle(
        cornerRadius: 28,
        height: 52,
        useCapsuleShape: true,
        iconName: "magnifyingglass"
    )

    /// Messages inbox search — capsule pill, slightly tighter
    static let messages = AmenCapsuleStyle(
        cornerRadius: 100,
        height: 48,
        fillOpacity: 0.78,
        focusedFillOpacity: 0.92,
        shadowRadius: 12,
        focusedShadowRadius: 28,
        useCapsuleShape: true,
        iconName: "magnifyingglass",
        iconColor: AmenColor.mutedText
    )

    /// Settings contextual search — dark glass variant
    static let settings = AmenCapsuleStyle(
        cornerRadius: 14,
        height: 46,
        useCapsuleShape: false,
        isDarkMode: true
    )
}

// MARK: - AmenSmartCapsule

struct AmenSmartCapsule: View {
    @Binding var text: String
    var placeholder: String = "Search..."
    var style: AmenCapsuleStyle = .discover

    /// Focus binding — the hosting view owns the FocusState and passes it in.
    @FocusState.Binding var isFocused: Bool

    var onSubmit: (() -> Void)? = nil
    var onClear: (() -> Void)? = nil

    /// Optional trailing buttons (filter, mic, etc.)
    var trailingContent: AnyView? = nil

    // Internal animation state
    @State private var capsuleScale: CGFloat = 1.0
    @State private var capsuleOffsetY: CGFloat = 0
    @State private var currentShadowRadius: CGFloat = 16
    @State private var currentShadowOpacity: Double = 0.07
    @State private var currentFillOpacity: Double = 0.72

    // Entry animation
    @State private var appeared = false

    var body: some View {
        HStack(spacing: 10) {
            // Leading icon
            Image(systemName: style.iconName)
                .font(.systemScaled(16, weight: .medium))
                .foregroundColor(resolvedIconColor)
                .frame(width: 22)

            // Text field
            TextField("", text: $text, prompt: Text(placeholder)
                .foregroundColor(resolvedPlaceholderColor))
                .font(.systemScaled(16))
                .foregroundColor(resolvedTextColor)
                .focused($isFocused)
                .submitLabel(.search)
                .onSubmit { onSubmit?() }
                .tint(style.isDarkMode ? .white : AmenColor.titleText)

            // Clear button
            if style.showsClearButton && !text.isEmpty {
                Button {
                    HapticManager.impact(style: .light)
                    text = ""
                    onClear?()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.systemScaled(15))
                        .foregroundColor(resolvedIconColor)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }

            // Optional trailing content
            if let trailing = trailingContent {
                trailing
            }
        }
        .padding(.horizontal, 16)
        .frame(height: style.height)
        .background(capsuleBackground)
        .scaleEffect(capsuleScale)
        .offset(y: capsuleOffsetY)
        .shadow(
            color: Color.black.opacity(currentShadowOpacity),
            radius: currentShadowRadius,
            x: 0,
            y: currentShadowRadius * 0.3
        )
        // Entry animation
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
        .onAppear {
            currentShadowRadius = style.shadowRadius
            currentShadowOpacity = style.shadowOpacity
            currentFillOpacity = style.fillOpacity
            withAnimation(.amenSpringEntry) {
                appeared = true
            }
        }
        // Focus lift animation
        .onChange(of: isFocused) { _, focused in
            withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.72))) {
                capsuleScale = focused ? style.focusLiftScale : 1.0
                capsuleOffsetY = focused ? style.focusLiftOffset : 0
                currentShadowRadius = focused ? style.focusedShadowRadius : style.shadowRadius
                currentShadowOpacity = focused ? style.focusedShadowOpacity : style.shadowOpacity
                currentFillOpacity = focused ? style.focusedFillOpacity : style.fillOpacity
            }
        }
        .animation(.amenEaseQuick, value: text.isEmpty)
    }

    // MARK: - Background

    @ViewBuilder
    private var capsuleBackground: some View {
        if style.isDarkMode {
            darkBackground
        } else {
            lightBackground
        }
    }

    private var lightBackground: some View {
        Group {
            if style.useCapsuleShape {
                Capsule()
                    .fill(Color.white.opacity(currentFillOpacity))
                    .background(Capsule().fill(.ultraThinMaterial))
                    .overlay(
                        Capsule()
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.80), Color.white.opacity(0.10)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.75
                            )
                    )
            } else {
                RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(currentFillOpacity))
                    .background(
                        RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.80), Color.white.opacity(0.10)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.75
                            )
                    )
            }
        }
    }

    private var darkBackground: some View {
        RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
            .fill(style.darkPanelColor)
            .overlay(
                RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                    .stroke(style.darkBorderColor, lineWidth: 1)
            )
    }

    // MARK: - Resolved Colors

    private var resolvedTextColor: Color {
        style.isDarkMode ? style.darkTextColor : style.textColor
    }

    private var resolvedPlaceholderColor: Color {
        style.isDarkMode ? style.darkPlaceholderColor : style.placeholderColor
    }

    private var resolvedIconColor: Color {
        style.isDarkMode ? style.darkIconColor : style.iconColor
    }
}

// MARK: - Suggestion Panel

/// Floating glass suggestion panel that appears below the capsule.
struct AmenCapsuleSuggestionPanel<Content: View>: View {
    var style: AmenCapsuleStyle = .discover
    @ViewBuilder var content: () -> Content

    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(panelBackground)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : -6)
        .scaleEffect(appeared ? 1 : 0.98, anchor: .top)
        .onAppear {
            withAnimation(Motion.adaptive(.spring(response: 0.35, dampingFraction: 0.72))) {
                appeared = true
            }
        }
        .onDisappear { appeared = false }
    }

    @ViewBuilder
    private var panelBackground: some View {
        if style.isDarkMode {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(style.darkPanelColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(style.darkBorderColor, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.2), radius: 16, y: 6)
        } else {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.88))
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.80), Color.white.opacity(0.10)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.75
                        )
                )
                .shadow(color: .black.opacity(0.09), radius: 20, y: 8)
        }
    }
}

// MARK: - Suggestion Row

/// Standard suggestion row used inside AmenCapsuleSuggestionPanel.
struct AmenCapsuleSuggestionRow: View {
    let icon: String
    let text: String
    var subtitle: String? = nil
    var isDarkMode: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: {
            HapticManager.impact(style: .light)
            action()
        }) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.systemScaled(14, weight: .medium))
                    .foregroundColor(isDarkMode ? Color(white: 0.5) : AmenColor.mutedText)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 1) {
                    Text(text)
                        .font(.systemScaled(15, weight: .regular))
                        .foregroundColor(isDarkMode ? Color(white: 0.95) : AmenColor.titleText)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(.systemScaled(12))
                            .foregroundColor(isDarkMode ? Color(white: 0.45) : AmenColor.mutedText)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Image(systemName: "arrow.up.left")
                    .font(.systemScaled(11, weight: .medium))
                    .foregroundColor(isDarkMode ? Color(white: 0.3) : AmenColor.mutedText.opacity(0.5))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Recent Search Chip

/// Horizontal pill for recent search terms.
struct AmenRecentSearchChip: View {
    let text: String
    var isDarkMode: Bool = false
    let onTap: () -> Void
    var onRemove: (() -> Void)? = nil

    var body: some View {
        Button(action: {
            HapticManager.impact(style: .light)
            onTap()
        }) {
            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.systemScaled(11, weight: .medium))
                Text(text)
                    .font(.systemScaled(13, weight: .medium))
                    .lineLimit(1)

                if let onRemove {
                    Button {
                        HapticManager.impact(style: .light)
                        onRemove()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.systemScaled(8, weight: .bold))
                    }
                    .buttonStyle(.plain)
                }
            }
            .foregroundColor(isDarkMode ? Color(white: 0.85) : AmenColor.titleText)
            .padding(.horizontal, AmenSpacing.chipH)
            .padding(.vertical, AmenSpacing.chipV)
            .background(chipBackground)
        }
        .buttonStyle(GlassPressStyle())
    }

    @ViewBuilder
    private var chipBackground: some View {
        if isDarkMode {
            Capsule()
                .fill(Color.white.opacity(0.08))
                .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 0.5))
        } else {
            Capsule()
                .fill(Color.white.opacity(0.84))
                .background(Capsule().fill(.ultraThinMaterial))
                .overlay(Capsule().stroke(Color.white.opacity(0.50), lineWidth: 0.75))
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 3)
        }
    }
}

// MARK: - Preview

#Preview("Light Capsule") {
    @Previewable @FocusState var focused: Bool
    @Previewable @State var text = ""

    VStack(spacing: 20) {
        AmenSmartCapsule(
            text: $text,
            placeholder: "Verses, people, news...",
            style: .discover,
            isFocused: $focused
        )
        .padding(.horizontal, 16)

        AmenSmartCapsule(
            text: $text,
            placeholder: "Search conversations",
            style: .messages,
            isFocused: $focused
        )
        .padding(.horizontal, 16)
    }
    .padding(.top, 40)
    .background(AmenColor.background)
}

#Preview("Dark Capsule") {
    @Previewable @FocusState var focused: Bool
    @Previewable @State var text = ""

    AmenSmartCapsule(
        text: $text,
        placeholder: "Search settings...",
        style: .settings,
        isFocused: $focused
    )
    .padding(.horizontal, 16)
    .padding(.top, 40)
    .background(Color(red: 0.07, green: 0.07, blue: 0.08))
}
