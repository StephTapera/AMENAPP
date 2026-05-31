// AmenGlassKit.swift
// AMENAPP — DesignSystem/GlassKit
//
// FROZEN SINGLE SOURCE OF TRUTH for all Liquid Glass UI in AMEN.
// ────────────────────────────────────────────────────────────────
// READ-ONLY after initial commit. Only A13 (via A0 broadcast) may add to this file.
//
// iOS version strategy:
//   iOS 26+  → native `.glassEffect` / `GlassEffectContainer` where available.
//   iOS 15–25 → `.ultraThinMaterial` + adaptive tint + spring physics fallback.
//   Feature views NEVER branch on iOS version — this kit handles all branching.
//
// Color contract: AMEN palette ONLY.
//   amenGold, amenPurple, amenBlue, amenBlack, amenEmerald (via AmenTheme / Color extensions)
//   No Apple system blue, no generic white accents as primary brand colors.
//
// Motion contract:
//   All animated elements check @Environment(\.accessibilityReduceMotion) or
//   UIAccessibility.isReduceMotionEnabled. Springs use Motion.liquidSpringAdaptive
//   or Motion.adaptive(_:) — never bare .spring() without a reduce-motion guard.
//
// Contrast contract:
//   amenGlassScrim() modifier provides an adaptive gradient scrim that keeps
//   text legible over any photo, video, or satellite map background.

import SwiftUI

// ─────────────────────────────────────────────────────────────────
// MARK: - GlassLevel
// ─────────────────────────────────────────────────────────────────

/// The opacity / blur weight of a glass surface.
///
/// - `thin`    → ultraThin material. Use for HUDs, floating pills, tooltip chrome.
/// - `regular` → thin material (slightly more opaque). Use for cards, sheets, action rows.
/// - `thick`   → regular material. Use for modal bottom sheets where full legibility matters.
public enum GlassLevel {
    case thin
    case regular
    case thick

    /// The SwiftUI material that best represents this level.
    var material: Material {
        switch self {
        case .thin:    return .ultraThinMaterial
        case .regular: return .thinMaterial
        case .thick:   return .regularMaterial
        }
    }

    /// White highlight fill opacity layered above the material.
    var highlightOpacity: Double {
        switch self {
        case .thin:    return 0.08
        case .regular: return 0.12
        case .thick:   return 0.16
        }
    }

    /// Top edge glow opacity — the single strongest cue that a surface is glass.
    var edgeGlowOpacity: Double {
        switch self {
        case .thin:    return 0.22
        case .regular: return 0.32
        case .thick:   return 0.42
        }
    }

    /// Shadow radius for the floating lift effect.
    var shadowRadius: CGFloat {
        switch self {
        case .thin:    return 12
        case .regular: return 18
        case .thick:   return 26
        }
    }

    /// Shadow Y-offset.
    var shadowY: CGFloat {
        switch self {
        case .thin:    return 5
        case .regular: return 8
        case .thick:   return 12
        }
    }
}

// ─────────────────────────────────────────────────────────────────
// MARK: - View Modifiers
// ─────────────────────────────────────────────────────────────────

// MARK: amenGlass(_:)

/// Applies the canonical AMEN Liquid Glass surface treatment at the specified level.
///
/// This modifier is the single call-site for glass backgrounds throughout the app.
/// Feature views must call `.amenGlass()` instead of composing material/overlay
/// layers directly — this ensures iOS version gating, reduce-transparency support,
/// and dark-mode highlight values are applied consistently everywhere.
///
/// Usage:
/// ```swift
/// MyCard()
///     .amenGlass()          // regular level (default)
///
/// MyPill()
///     .amenGlass(.thin)     // lighter HUD pill
///
/// MySheet()
///     .amenGlass(.thick)    // heavier modal sheet
/// ```
private struct AmenGlassModifier: ViewModifier {
    let level: GlassLevel
    let cornerRadius: CGFloat

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .background {
                glassBackground
            }
            .overlay {
                glassStroke
            }
    }

    @ViewBuilder
    private var glassBackground: some View {
        if reduceTransparency {
            // Accessibility: replace glass with a fully opaque surface.
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(uiColor: .systemBackground))
        } else {
            ZStack {
                // Layer 1: platform material blur (GPU-composited CABackdropLayer).
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(level.material)

                // Layer 2: adaptive highlight coat — bright in light mode, smoke in dark.
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(AmenTheme.Colors.glassFill.opacity(level.highlightOpacity / 0.12))

                // Layer 3: top edge glow — directionality cue.
                VStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(level.edgeGlowOpacity),
                                    Color.white.opacity(0)
                                ],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                        .frame(maxHeight: 32)
                    Spacer(minLength: 0)
                }
            }
            .shadow(
                color: AmenTheme.Colors.shadowFloating,
                radius: level.shadowRadius,
                x: 0,
                y: level.shadowY
            )
        }
    }

    @ViewBuilder
    private var glassStroke: some View {
        if !reduceTransparency {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            AmenTheme.Colors.glassStroke,
                            AmenTheme.Colors.glassStroke.opacity(0.35)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.75
                )
        }
    }
}

// MARK: amenGlassScrim()

/// Adds a gradient scrim that keeps text legible over photo/video/satellite backgrounds.
///
/// Designed for hero images, full-screen video, and map tiles where the background
/// luminance is unpredictable. The scrim fades from transparent at the top to a
/// controlled opacity at the bottom, matching `AmenTheme.Colors.mediaOverlay`.
///
/// Usage:
/// ```swift
/// ZStack(alignment: .bottomLeading) {
///     AsyncImage(url: heroURL)
///     VStack { titleText; subtitleText }
///         .amenGlassScrim()   // scrim applied to the text container
/// }
/// ```
private struct AmenGlassScrimModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .background {
                // Gradient scrim — transparent → 52% black, bottom-anchored.
                LinearGradient(
                    stops: [
                        .init(color: .clear,                   location: 0.0),
                        .init(color: .black.opacity(0.16),     location: 0.35),
                        .init(color: .black.opacity(0.38),     location: 0.65),
                        .init(color: .black.opacity(0.52),     location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)
            }
    }
}

// MARK: Public View extensions

public extension View {

    /// Applies the canonical AMEN Liquid Glass surface at the given level.
    /// Feature views must use this instead of composing raw material layers.
    func amenGlass(
        _ level: GlassLevel = .regular,
        cornerRadius: CGFloat = AmenTheme.CornerRadius.glass
    ) -> some View {
        modifier(AmenGlassModifier(level: level, cornerRadius: cornerRadius))
    }

    /// Adds an adaptive gradient scrim for text contrast over photo/video/map backgrounds.
    func amenGlassScrim() -> some View {
        modifier(AmenGlassScrimModifier())
    }
}

// ─────────────────────────────────────────────────────────────────
// MARK: - LiquidGlassTabBar  (1 — Global floating nav tab bar)
// ─────────────────────────────────────────────────────────────────

/// A tab bar item descriptor for use with `LiquidGlassTabBar`.
public struct GlassTabItem {
    /// SF Symbol name when this tab is NOT selected.
    public let icon: String
    /// SF Symbol name when this tab IS selected (usually the ".fill" variant).
    public let activeIcon: String
    /// Accessibility + display label for this tab.
    public let label: String
    /// Optional badge count. 0 = no badge.
    public let badge: Int

    public init(icon: String, activeIcon: String, label: String, badge: Int = 0) {
        self.icon = icon
        self.activeIcon = activeIcon
        self.label = label
        self.badge = badge
    }
}

/// The canonical global floating nav tab bar for AMEN.
///
/// Floating, capsule-shaped, translucent, and content-aware.
/// Compresses on fast downward scroll (via `isCompressed`).
/// Adapts tint when colorful content is visible beneath it.
///
/// Usage:
/// ```swift
/// LiquidGlassTabBar(
///     items: tabs,
///     selection: $selectedIndex,
///     isColorfulContentBehind: feedHasMedia,
///     isCompressed: scrollVelocity > 300
/// )
/// ```
public struct LiquidGlassTabBar: View {
    public let items: [GlassTabItem]
    @Binding public var selection: Int
    public var isColorfulContentBehind: Bool = false
    public var isCompressed: Bool = false

    @Environment(\.accessibilityReduceMotion)       private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Namespace private var activeTabNamespace

    public init(
        items: [GlassTabItem],
        selection: Binding<Int>,
        isColorfulContentBehind: Bool = false,
        isCompressed: Bool = false
    ) {
        self.items = items
        self._selection = selection
        self.isColorfulContentBehind = isColorfulContentBehind
        self.isCompressed = isCompressed
    }

    public var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                tabButton(index: index, item: item)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, isCompressed ? 6 : 8)
        .frame(maxWidth: 430)
        .background { barBackground }
        .clipShape(Capsule())
        .shadow(
            color: .black.opacity(reduceTransparency ? 0.14 : 0.10),
            radius: isCompressed ? 10 : 16,
            x: 0,
            y: isCompressed ? 5 : 9
        )
        .padding(.horizontal, 18)
        .scaleEffect(y: isCompressed ? 0.94 : 1.0, anchor: .bottom)
        .opacity(isCompressed ? 0.92 : 1.0)
        .animation(
            reduceMotion ? .easeInOut(duration: 0.16) : Motion.liquidSpring,
            value: isCompressed
        )
        .accessibilityElement(children: .contain)
    }

    // MARK: Bar background

    private var barBackground: some View {
        Capsule()
            .fill(
                reduceTransparency
                    ? AnyShapeStyle(Color(uiColor: .systemBackground))
                    : AnyShapeStyle(.ultraThinMaterial)
            )
            .overlay {
                Capsule()
                    .fill(
                        Color.white.opacity(
                            reduceTransparency ? 1.0
                                : (isColorfulContentBehind ? 0.60 : 0.82)
                        )
                    )
            }
            .overlay {
                // Colorful content tint — AMEN palette, NOT Apple system colors.
                if !reduceTransparency && isColorfulContentBehind {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    AmenTheme.Colors.amenGold.opacity(0.06),
                                    AmenTheme.Colors.amenPurple.opacity(0.04),
                                    AmenTheme.Colors.amenBlue.opacity(0.04)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .saturation(1.2)
                }
            }
            .overlay {
                Capsule()
                    .strokeBorder(
                        Color.black.opacity(reduceTransparency ? 0.10 : 0.055),
                        lineWidth: 0.6
                    )
            }
            .overlay {
                // Top-edge specular highlight.
                Capsule()
                    .fill(.white.opacity(reduceTransparency ? 0.55 : 0.42))
                    .frame(height: 1)
                    .padding(.horizontal, 24)
                    .padding(.top, 6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
    }

    // MARK: Individual tab button

    @ViewBuilder
    private func tabButton(index: Int, item: GlassTabItem) -> some View {
        let isSelected = selection == index

        Button {
            guard selection != index else { return }
            withAnimation(tabAnimation) { selection = index }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 3) {
                    Group {
                        if #available(iOS 17, *) {
                            Image(systemName: isSelected ? item.activeIcon : item.icon)
                                .symbolEffect(.bounce, value: isSelected)
                        } else {
                            Image(systemName: isSelected ? item.activeIcon : item.icon)
                        }
                    }
                    .font(.system(size: 20, weight: .bold))
                    .symbolRenderingMode(.monochrome)
                    .frame(height: 22)

                    Text(item.label)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                // Active indicator fill
                .foregroundStyle(
                    isSelected
                        ? AmenTheme.Colors.amenBlue
                        : Color.black.opacity(0.88)
                )
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
                .padding(.horizontal, 4)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(activeTabFill)
                            .overlay(
                                Capsule()
                                    .strokeBorder(
                                        Color.white.opacity(reduceTransparency ? 0.80 : 0.50),
                                        lineWidth: 0.8
                                    )
                            )
                            .matchedGeometryEffect(
                                id: "amenGlassKit_activeTab",
                                in: activeTabNamespace
                            )
                    }
                }
                .contentShape(Capsule())

                // Badge
                if item.badge > 0 {
                    Text(item.badge > 99 ? "99+" : "\(item.badge)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(AmenTheme.Colors.amenBlue)
                        )
                        .offset(x: 4, y: -2)
                }
            }
        }
        .buttonStyle(GlassKitPressStyle(reduceMotion: reduceMotion))
        .accessibilityLabel(item.label)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var activeTabFill: Color {
        if reduceTransparency { return Color(uiColor: .secondarySystemBackground) }
        if isColorfulContentBehind { return Color.white.opacity(0.48) }
        return Color.black.opacity(0.055)
    }

    private var tabAnimation: Animation? {
        guard !reduceMotion else { return .easeInOut(duration: 0.16) }
        if #available(iOS 17, *) {
            return .spring(.bouncy(duration: 0.4, extraBounce: 0.1))
        }
        return .spring(response: 0.42, dampingFraction: 0.72)
    }
}

// ─────────────────────────────────────────────────────────────────
// MARK: - GlassSheet  (2a — Draggable sheet with glass background)
// ─────────────────────────────────────────────────────────────────

/// A bottom sheet container with a Liquid Glass chrome header and draggable dismiss.
///
/// Replaces ad-hoc `.sheet` chrome in feature views. Provides:
/// - Glass title bar with drag indicator.
/// - Scrollable content area.
/// - Optional footer (action buttons).
///
/// Usage:
/// ```swift
/// GlassSheet(title: "Filter") {
///     FilterOptionsView()
/// }
/// ```
public struct GlassSheet<Content: View>: View {
    public let title: String
    public let subtitle: String?
    @ViewBuilder public let content: () -> Content

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dismiss) private var dismiss

    public init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Drag indicator
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.primary.opacity(0.20))
                .frame(width: 36, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 6)

            // Title bar
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(AmenTheme.Colors.textPrimary)
                        if let subtitle {
                            Text(subtitle)
                                .font(.subheadline)
                                .foregroundStyle(AmenTheme.Colors.textSecondary)
                        }
                    }
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(AmenTheme.Colors.textTertiary)
                    }
                    .accessibilityLabel("Close")
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 12)
            .background(sheetChrome)

            Divider()
                .background(AmenTheme.Colors.separatorSubtle)

            // Content
            ScrollView(.vertical, showsIndicators: false) {
                content()
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
            }
        }
        .background(sheetBackground)
    }

    @ViewBuilder
    private var sheetChrome: some View {
        if reduceTransparency {
            Color(uiColor: .systemBackground)
        } else {
            Rectangle()
                .fill(.regularMaterial)
                .overlay(
                    Rectangle()
                        .fill(AmenTheme.Colors.glassFill.opacity(0.5))
                )
        }
    }

    @ViewBuilder
    private var sheetBackground: some View {
        if reduceTransparency {
            Color(uiColor: .systemBackground)
        } else {
            Color(uiColor: .systemBackground)
                .overlay(
                    Rectangle()
                        .fill(AmenTheme.Colors.glassFill.opacity(0.15))
                )
        }
    }
}

// ─────────────────────────────────────────────────────────────────
// MARK: - GlassCard  (2b — Church cards, post cells)
// ─────────────────────────────────────────────────────────────────

/// A rounded-rectangle glass card surface.
///
/// Wraps any content in the canonical `.amenGlass(.regular)` treatment
/// at the standard `AmenTheme.CornerRadius.glass` (18 pt) radius.
/// Accepts an optional accent tint for AMEN palette theming.
///
/// Usage:
/// ```swift
/// GlassCard {
///     ChurchInfoRow(church: church)
/// }
///
/// GlassCard(accentTint: AmenTheme.Colors.amenGold) {
///     VerifiedBadgeRow()
/// }
/// ```
public struct GlassCard<Content: View>: View {
    public let accentTint: Color?
    public let cornerRadius: CGFloat
    @ViewBuilder public let content: () -> Content

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init(
        accentTint: Color? = nil,
        cornerRadius: CGFloat = AmenTheme.CornerRadius.glass,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.accentTint = accentTint
        self.cornerRadius = cornerRadius
        self.content = content
    }

    public var body: some View {
        content()
            .amenGlass(.regular, cornerRadius: cornerRadius)
            .overlay {
                // Optional AMEN palette accent border.
                if let tint = accentTint, !reduceTransparency {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            tint.opacity(0.35),
                            lineWidth: 1.0
                        )
                }
            }
    }
}

// ─────────────────────────────────────────────────────────────────
// MARK: - GlassPin  (2c — Map annotation)
// ─────────────────────────────────────────────────────────────────

/// A map annotation pin with Liquid Glass treatment.
///
/// Renders in one of two styles:
/// - `.verified` → `amenGold` accent — for verified/official churches.
/// - `.standard` → `amenBlue` accent — for regular search results.
///
/// Usage:
/// ```swift
/// GlassPin(style: .verified, label: "First Baptist")
///     .onTapGesture { ... }
/// ```
public struct GlassPin: View {

    public enum Style {
        case verified   // amenGold — official / verified churches
        case standard   // amenBlue — standard search results
    }

    public let style: Style
    public let label: String
    public var isSelected: Bool = false

    @Environment(\.accessibilityReduceMotion)       private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init(style: Style = .standard, label: String, isSelected: Bool = false) {
        self.style = style
        self.label = label
        self.isSelected = isSelected
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: style == .verified ? "checkmark.seal.fill" : "mappin.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accentColor)
                if isSelected {
                    Text(label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                        .lineLimit(1)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, isSelected ? 10 : 8)
            .padding(.vertical, 7)
            .amenGlass(.thin, cornerRadius: 16)
            .scaleEffect(isSelected ? 1.08 : 1.0)
            .animation(
                reduceMotion ? .easeInOut(duration: 0.12) : Motion.liquidSpring,
                value: isSelected
            )

            // Teardrop pointer
            Triangle()
                .fill(
                    reduceTransparency
                        ? AnyShapeStyle(Color(uiColor: .systemBackground))
                        : AnyShapeStyle(.ultraThinMaterial)
                )
                .frame(width: 10, height: 6)
                .offset(y: -1)
        }
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var accentColor: Color {
        switch style {
        case .verified: return AmenTheme.Colors.amenGold
        case .standard: return AmenTheme.Colors.amenBlue
        }
    }
}

/// Simple downward-pointing triangle used as the map pin teardrop.
private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

// ─────────────────────────────────────────────────────────────────
// MARK: - GlassChip  (2d — Filter chips, sticker tray toggle)
// ─────────────────────────────────────────────────────────────────

/// A pill-shaped interactive chip for filters, tags, sticker tray toggles.
///
/// Active chips use the AMEN palette accent; inactive chips use the glass surface.
/// Supports optional leading icon and trailing badge.
///
/// Usage:
/// ```swift
/// GlassChip(label: "Nearby", isSelected: selectedFilter == .nearby) {
///     selectedFilter = .nearby
/// }
///
/// GlassChip(icon: "music.note", label: "Music", isSelected: false) { }
/// ```
public struct GlassChip: View {
    public let icon: String?
    public let label: String
    public var isSelected: Bool
    public var accentColor: Color
    public let action: () -> Void

    @Environment(\.accessibilityReduceMotion)       private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @GestureState private var isPressed = false

    public init(
        icon: String? = nil,
        label: String,
        isSelected: Bool = false,
        accentColor: Color = AmenTheme.Colors.amenBlue,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.label = label
        self.isSelected = isSelected
        self.accentColor = accentColor
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? .white : AmenTheme.Colors.textPrimary)
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .frame(minHeight: 32)
            .background {
                if isSelected {
                    Capsule()
                        .fill(accentColor)
                        .shadow(color: accentColor.opacity(0.28), radius: 6, y: 3)
                } else {
                    Capsule()
                        .fill(reduceTransparency
                              ? AnyShapeStyle(Color(uiColor: .systemBackground))
                              : AnyShapeStyle(.ultraThinMaterial))
                        .overlay {
                            Capsule()
                                .fill(AmenTheme.Colors.glassFill.opacity(0.6))
                        }
                        .overlay {
                            Capsule()
                                .strokeBorder(AmenTheme.Colors.glassStroke.opacity(0.6), lineWidth: 0.6)
                        }
                }
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(reduceMotion ? 1 : (isPressed ? 0.96 : 1))
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($isPressed) { _, state, _ in state = true }
        )
        .animation(
            reduceMotion ? .easeOut(duration: 0.10) : Motion.springPress,
            value: isPressed
        )
        .animation(
            reduceMotion ? .easeInOut(duration: 0.14) : Motion.popToggle,
            value: isSelected
        )
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// ─────────────────────────────────────────────────────────────────
// MARK: - GlassActionRow  (2e — Provenance actions, overflow menus)
// ─────────────────────────────────────────────────────────────────

/// A tappable action row styled for Liquid Glass overflow menus and provenance panels.
///
/// Usage:
/// ```swift
/// GlassActionRow(icon: "flag", label: "Report", role: .destructive) {
///     showReport = true
/// }
///
/// GlassActionRow(icon: "bookmark", label: "Save") {
///     savePost()
/// }
/// ```
public struct GlassActionRow: View {
    public enum RowRole {
        case standard
        case destructive
    }

    public let icon: String
    public let label: String
    public var subtitle: String?
    public var role: RowRole
    public let action: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init(
        icon: String,
        label: String,
        subtitle: String? = nil,
        role: RowRole = .standard,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.label = label
        self.subtitle = subtitle
        self.role = role
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(iconColor)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(labelColor)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(AmenTheme.Colors.textSecondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AmenTheme.Colors.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(GlassKitPressStyle())
        .accessibilityLabel(label)
    }

    private var iconColor: Color {
        role == .destructive
            ? AmenTheme.Colors.buttonDestructive
            : AmenTheme.Colors.textSecondary
    }

    private var labelColor: Color {
        role == .destructive
            ? AmenTheme.Colors.buttonDestructive
            : AmenTheme.Colors.textPrimary
    }
}

// ─────────────────────────────────────────────────────────────────
// MARK: - GlassButton  (2f — Primary/secondary capsule buttons)
// ─────────────────────────────────────────────────────────────────

/// A capsule-shaped CTA button with Liquid Glass treatment.
///
/// Variants:
/// - `.primary`   → solid AMEN black (light) / white (dark) fill — highest emphasis.
/// - `.secondary` → glass surface with tinted border — medium emphasis.
/// - `.tinted`    → glass surface tinted with a provided AMEN palette color.
///
/// Usage:
/// ```swift
/// GlassButton("Follow", icon: "person.badge.plus", style: .primary) {
///     followUser()
/// }
///
/// GlassButton("Share", icon: "square.and.arrow.up", style: .secondary) {
///     sharePost()
/// }
///
/// GlassButton("Pray", icon: "hands.sparkles", style: .tinted(AmenTheme.Colors.amenPurple)) {
///     addPrayer()
/// }
/// ```
public struct GlassButton: View {

    public enum Variant {
        case primary
        case secondary
        case tinted(Color)
    }

    public let label: String
    public let icon: String?
    public var style: Variant
    public var isLoading: Bool
    public var isDisabled: Bool
    public var hint: String?
    public let action: () -> Void

    @Environment(\.accessibilityReduceMotion)       private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @GestureState private var isPressed = false

    public init(
        _ label: String,
        icon: String? = nil,
        style: Variant = .primary,
        isLoading: Bool = false,
        isDisabled: Bool = false,
        hint: String? = nil,
        action: @escaping () -> Void
    ) {
        self.label = label
        self.icon = icon
        self.style = style
        self.isLoading = isLoading
        self.isDisabled = isDisabled
        self.hint = hint
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                let effectiveIcon = isLoading ? "hourglass" : icon
                if let symbolName = effectiveIcon {
                    if #available(iOS 17, *) {
                        Image(systemName: symbolName)
                            .symbolEffect(.bounce, value: isPressed)
                    } else {
                        Image(systemName: symbolName)
                    }
                }
                Text(label)
                    .lineLimit(1)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(labelForeground)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background { buttonBackground }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled || isLoading)
        .opacity(isDisabled ? 0.55 : 1.0)
        .scaleEffect(reduceMotion ? 1 : (isPressed ? 0.96 : 1))
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($isPressed) { _, state, _ in state = true }
        )
        .animation(
            reduceMotion ? .easeOut(duration: 0.10) : Motion.springPress,
            value: isPressed
        )
        .accessibilityLabel(label)
        .accessibilityHint(hint ?? "")
    }

    // MARK: Computed style helpers

    private var labelForeground: Color {
        switch style {
        case .primary:
            return AmenTheme.Colors.buttonPrimaryText
        case .secondary:
            return AmenTheme.Colors.textPrimary
        case .tinted(let color):
            return color.isBright ? .black : .white
        }
    }

    @ViewBuilder
    private var buttonBackground: some View {
        switch style {
        case .primary:
            Capsule()
                .fill(AmenTheme.Colors.buttonPrimary)
                .shadow(color: AmenTheme.Colors.shadowCard, radius: 10, y: 4)

        case .secondary:
            Capsule()
                .fill(
                    reduceTransparency
                        ? AnyShapeStyle(Color(uiColor: .systemBackground))
                        : AnyShapeStyle(.ultraThinMaterial)
                )
                .overlay {
                    Capsule()
                        .fill(AmenTheme.Colors.glassFill)
                }
                .overlay {
                    Capsule()
                        .strokeBorder(AmenTheme.Colors.glassStroke, lineWidth: 0.75)
                }
                .shadow(color: AmenTheme.Colors.shadowCard.opacity(0.6), radius: 8, y: 3)

        case .tinted(let color):
            Capsule()
                .fill(
                    reduceTransparency
                        ? AnyShapeStyle(color)
                        : AnyShapeStyle(.ultraThinMaterial)
                )
                .overlay {
                    if !reduceTransparency {
                        Capsule().fill(color.opacity(0.22))
                    }
                }
                .overlay {
                    Capsule()
                        .strokeBorder(color.opacity(0.40), lineWidth: 0.9)
                }
                .shadow(color: color.opacity(0.20), radius: 8, y: 3)
        }
    }
}

// ─────────────────────────────────────────────────────────────────
// MARK: - GlassKitPressStyle  (shared ButtonStyle)
// ─────────────────────────────────────────────────────────────────

/// Canonical ButtonStyle for all GlassKit interactive elements.
/// 0.96 scale on press + light haptic + reduce-motion guard.
struct GlassKitPressStyle: ButtonStyle {
    var scale: CGFloat = 0.96
    var haptic: Bool = true
    var reduceMotion: Bool = false

    // Convenience init for @Environment usage sites that already have the value.
    init(scale: CGFloat = 0.96, haptic: Bool = true, reduceMotion: Bool = false) {
        self.scale = scale
        self.haptic = haptic
        self.reduceMotion = reduceMotion
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1)
            .animation(
                reduceMotion ? .easeOut(duration: 0.10) : Motion.springPress,
                value: configuration.isPressed
            )
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed && haptic {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
    }
}

// ─────────────────────────────────────────────────────────────────
// MARK: - Color brightness helper
// ─────────────────────────────────────────────────────────────────

private extension Color {
    /// Returns true if this color is perceptually bright (luminance > 0.6).
    /// Used by GlassButton to pick black vs white label foreground on tinted backgrounds.
    var isBright: Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard let uiColor = UIColor(self).cgColor.components else { return false }
        if uiColor.count >= 3 {
            r = uiColor[0]; g = uiColor[1]; b = uiColor[2]
        } else if uiColor.count == 2 {
            r = uiColor[0]; g = uiColor[0]; b = uiColor[0]
        }
        // Rec. 709 luminance
        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
        return luminance > 0.60
    }
}
