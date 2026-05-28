// SpacesDesignSystem.swift
// AMENAPP — Spaces v2 Design System (Agent 2)
//
// Reusable Liquid Glass design layer for the Spaces feature.
// All color tokens sourced from AmenTheme.Colors — no raw system colors.
// Animation constants sourced from Motion.swift — no redeclarations.
// All corner radii from LiquidGlassTokens — no invented values.
//
// Constraints:
//   - No .glassEffect(), GlassEffectContainer, or glassEffectID (iOS 26 API).
//   - No @Namespace + matched geometry for hero morph (out of scope).
//   - ultraThinMaterial + manual overlays for all glass surfaces.
//   - AMENGlassPillButton wraps / thin-extends AmenLiquidGlassPillButton
//     rather than duplicating the capsule surface logic.

import SwiftUI

// MARK: - SpaceHeroView

/// Full-bleed hero card for a Space, shown as the top card in the Spaces
/// discovery carousel. The hero tint is drawn from the space type —
/// amenGold for Bible Study, amenPurple for community/group, amenBlue for
/// announcements — making the surface unmistakably AMEN rather than a
/// generic streaming UI.
struct SpaceHeroView: View {

    let space: AmenSpaceExtended
    /// Optional single verse line shown above the title, e.g. "Romans 8:28"
    var verseOverlay: String? = nil
    /// 0-based page position for the carousel dot indicator
    var pageIndex: Int = 0
    var totalPages: Int = 1
    var onJoin: () -> Void
    var onSave: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    // Derive the hero tint from the space type.
    private var heroTint: Color {
        switch space.type {
        case .bibleStudy:   return AmenTheme.Colors.amenGold
        case .chat:         return AmenTheme.Colors.amenPurple
        case .group:        return AmenTheme.Colors.amenPurple
        case .announcement: return AmenTheme.Colors.amenBlue
        }
    }

    // Join / Open / Request label depends on access policy.
    private var primaryActionLabel: String {
        switch space.accessPolicy {
        case .free:      return "Open"
        case .oneTime:   return "Join"
        case .recurring: return "Request"
        }
    }

    private var actionIcon: String {
        switch space.accessPolicy {
        case .free:      return "arrow.right.circle.fill"
        case .oneTime:   return "person.badge.plus"
        case .recurring: return "envelope.fill"
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            heroImage
            scrimGradient

            VStack(alignment: .leading, spacing: 0) {
                Spacer()

                // Verse overlay (optional) — gold italic, 1 line, above the title
                if let verse = verseOverlay {
                    Text(verse)
                        .font(.caption.italic())
                        .foregroundStyle(AmenTheme.Colors.amenGold)
                        .lineLimit(1)
                        .padding(.bottom, 4)
                        .accessibilityLabel("Scripture: \(verse)")
                }

                // Space title
                Text(space.title)
                    .font(.title2.bold())
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .lineLimit(2)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.bottom, 8)

                // Faith metadata chip row
                SpaceFaithMetadataRow(
                    spaceType: space.type,
                    memberCount: 0,
                    bibleVersion: space.type == .bibleStudy ? "KJV" : nil,
                    liturgicalSeason: nil,
                    churchBadge: nil
                )
                .padding(.bottom, 14)

                // Action row: primary pill + circular save button
                HStack(spacing: 12) {
                    AMENGlassPillButton(
                        title: primaryActionLabel,
                        icon: actionIcon,
                        style: heroTint == AmenTheme.Colors.amenGold ? .primary : .prominent,
                        action: onJoin
                    )
                    .accessibilityLabel("\(primaryActionLabel) \(space.title)")

                    // Secondary circular bookmark button
                    Button(action: onSave) {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AmenTheme.Colors.amenGold)
                            .frame(width: 44, height: 44)
                            .background {
                                if reduceTransparency {
                                    Circle().fill(AmenTheme.Colors.surfaceCard)
                                } else {
                                    Circle()
                                        .fill(.ultraThinMaterial)
                                        .overlay {
                                            Circle().fill(heroTint.opacity(0.15))
                                        }
                                        .overlay {
                                            Circle().strokeBorder(
                                                AmenTheme.Colors.glassStroke,
                                                lineWidth: 0.75
                                            )
                                        }
                                }
                            }
                            .shadow(
                                color: LiquidGlassTokens.shadowSoft.color,
                                radius: LiquidGlassTokens.shadowSoft.radius,
                                y: LiquidGlassTokens.shadowSoft.y
                            )
                    }
                    .buttonStyle(.plain)
                    .amenPress(scale: 0.96)
                    .accessibilityLabel("Save \(space.title)")
                    .accessibilityHint("Bookmarks this Space for later.")

                    Spacer()
                }
                .padding(.bottom, 14)

                // Page dots
                if totalPages > 1 {
                    HStack(spacing: 5) {
                        ForEach(0..<totalPages, id: \.self) { idx in
                            Capsule()
                                .fill(
                                    idx == pageIndex
                                        ? AmenTheme.Colors.amenGold
                                        : AmenTheme.Colors.glassStroke
                                )
                                .frame(width: idx == pageIndex ? 18 : 6, height: 6)
                                .animation(
                                    reduceMotion ? .none : Motion.popToggle,
                                    value: pageIndex
                                )
                        }
                    }
                    .padding(.bottom, 18)
                    .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 20)

            // Hero glass tint layer — AMEN brand color bleeds into the surface
            if !reduceTransparency {
                RoundedRectangle(
                    cornerRadius: LiquidGlassTokens.cornerRadiusLarge,
                    style: .continuous
                )
                .fill(heroTint.opacity(0.07))
                .allowsHitTesting(false)
            }
        }
        .frame(minHeight: 280)
        .clipShape(
            RoundedRectangle(
                cornerRadius: LiquidGlassTokens.cornerRadiusLarge,
                style: .continuous
            )
        )
        .shadow(
            color: LiquidGlassTokens.shadowFloating.color,
            radius: LiquidGlassTokens.shadowFloating.radius,
            y: LiquidGlassTokens.shadowFloating.y
        )
        .accessibilityElement(children: .contain)
    }

    // MARK: - Sub-views

    @ViewBuilder
    private var heroImage: some View {
        if let urlStr = space.avatarURL, let url = URL(string: urlStr) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                default:
                    heroFallbackGradient
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 280)
            .clipped()
        } else {
            heroFallbackGradient
                .frame(maxWidth: .infinity, minHeight: 280)
        }
    }

    private var heroFallbackGradient: some View {
        LinearGradient(
            colors: [heroTint.opacity(0.70), AmenTheme.Colors.amenBlack],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var scrimGradient: some View {
        LinearGradient(
            stops: [
                .init(color: AmenTheme.Colors.amenBlack.opacity(0.00), location: 0.0),
                .init(color: AmenTheme.Colors.amenBlack.opacity(0.30), location: 0.45),
                .init(color: AmenTheme.Colors.amenBlack.opacity(0.85), location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .allowsHitTesting(false)
    }
}

// MARK: - SpaceFaithMetadataRow

/// Faith-native chip row that appears beneath the hero title.
/// Each chip communicates spiritual context — type, member count, Bible
/// version, liturgical season, or church badge — using amenGold separators
/// rather than plain system-color dots, ensuring the row reads as AMEN.
struct SpaceFaithMetadataRow: View {

    let spaceType: SpaceV2Type
    let memberCount: Int
    let bibleVersion: String?
    let liturgicalSeason: String?
    let churchBadge: ChurchBadgeChip.Badge?

    private var goldDot: some View {
        Text(" · ")
            .font(.caption.bold())
            .foregroundStyle(AmenTheme.Colors.amenGold)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {

                // Space type chip (always shown)
                ChurchBadgeChip(badge: ChurchBadgeChip.Badge(
                    icon: spaceType.systemImageName,
                    label: spaceType.displayName,
                    tint: AmenTheme.Colors.amenPurple
                ))

                if memberCount > 0 {
                    goldDot
                    ChurchBadgeChip(badge: ChurchBadgeChip.Badge(
                        icon: "person.2.fill",
                        label: memberCount == 1 ? "1 member" : "\(memberCount) members",
                        tint: AmenTheme.Colors.amenGold
                    ))
                }

                if let version = bibleVersion {
                    goldDot
                    ChurchBadgeChip(badge: ChurchBadgeChip.Badge(
                        icon: "book.closed.fill",
                        label: version,
                        tint: AmenTheme.Colors.amenGold
                    ))
                }

                if let season = liturgicalSeason {
                    goldDot
                    ChurchBadgeChip(badge: ChurchBadgeChip.Badge(
                        icon: "calendar",
                        label: season,
                        tint: AmenTheme.Colors.amenPurple
                    ))
                }

                if let badge = churchBadge {
                    goldDot
                    ChurchBadgeChip(badge: badge)
                }
            }
            .padding(.horizontal, 1) // prevent shadow clipping
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(a11yDescription)
    }

    private var a11yDescription: String {
        var parts: [String] = [spaceType.displayName]
        if memberCount > 0 { parts.append("\(memberCount) members") }
        if let v = bibleVersion { parts.append(v) }
        if let s = liturgicalSeason { parts.append(s) }
        return parts.joined(separator: ", ")
    }
}

// MARK: - ChurchBadgeChip

/// Small glass pill for one piece of faith metadata.
/// Uses `.ultraThinMaterial` with an AMEN gold icon tint — distinct from
/// plain system chips because the tint color bleeds into the glass surface
/// rather than sitting on a flat white pill background.
struct ChurchBadgeChip: View {

    struct Badge {
        let icon: String   // SF Symbol name
        let label: String
        let tint: Color    // must be an AmenTheme.Colors value
    }

    let badge: Badge

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: badge.icon)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AmenTheme.Colors.amenGold)

            Text(badge.label)
                .font(.caption.weight(.medium))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .lineLimit(1)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background {
            if reduceTransparency {
                RoundedRectangle(
                    cornerRadius: LiquidGlassTokens.cornerRadiusMedium,
                    style: .continuous
                )
                .fill(AmenTheme.Colors.surfaceCard)
            } else {
                RoundedRectangle(
                    cornerRadius: LiquidGlassTokens.cornerRadiusMedium,
                    style: .continuous
                )
                .fill(.ultraThinMaterial)
                .overlay {
                    // Tint bleed — AMEN color seeps into the glass surface
                    RoundedRectangle(
                        cornerRadius: LiquidGlassTokens.cornerRadiusMedium,
                        style: .continuous
                    )
                    .fill(badge.tint.opacity(0.10))
                }
            }
        }
        .overlay {
            RoundedRectangle(
                cornerRadius: LiquidGlassTokens.cornerRadiusMedium,
                style: .continuous
            )
            .strokeBorder(AmenTheme.Colors.glassStroke, lineWidth: 0.75)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(badge.label)
    }
}

// MARK: - AMENGlassPillButton
//
// NOTE: `AmenLiquidGlassPillButton` (AmenLiquidGlassComponents.swift) already
// provides the canonical glass capsule surface and Motion.liquidSpring press
// animation via AmenPressStyle. `AMENGlassPillButton` is a thin style-aware
// wrapper that adds the three AMEN-branded fill variants without duplicating
// the capsule surface logic.
//   .primary   → amenGold fill, amenBlack text
//   .secondary → ultraThinMaterial + amenGold stroke/text
//   .prominent → amenPurple fill, textPrimary (white in dark mode)

struct AMENGlassPillButton: View {

    enum Style {
        case primary    // amenGold fill, amenBlack text
        case secondary  // glass + amenGold stroke + amenGold text
        case prominent  // amenPurple fill, white text
    }

    let title: String
    var icon: String? = nil
    var style: Style = .primary
    var action: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let iconName = icon {
                    Image(systemName: iconName)
                        .font(.subheadline.weight(.semibold))
                }
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(labelColor)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background { pillBackground }
            .clipShape(
                RoundedRectangle(
                    cornerRadius: LiquidGlassTokens.cornerRadiusMedium,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: LiquidGlassTokens.cornerRadiusMedium,
                    style: .continuous
                )
                .strokeBorder(
                    strokeColor,
                    lineWidth: style == .secondary ? 1.0 : 0.5
                )
            }
            .shadow(
                color: LiquidGlassTokens.shadowSoft.color,
                radius: LiquidGlassTokens.shadowSoft.radius,
                y: LiquidGlassTokens.shadowSoft.y
            )
        }
        .buttonStyle(.plain)
        // Reuses AmenPressStyle from Motion.swift: 0.96 scale + haptic + reduceMotion guard.
        .amenPress(scale: 0.96)
        .accessibilityLabel(title)
    }

    // MARK: - Style helpers

    @ViewBuilder
    private var pillBackground: some View {
        switch style {
        case .primary:
            RoundedRectangle(
                cornerRadius: LiquidGlassTokens.cornerRadiusMedium,
                style: .continuous
            )
            .fill(AmenTheme.Colors.amenGold)

        case .secondary:
            if reduceTransparency {
                RoundedRectangle(
                    cornerRadius: LiquidGlassTokens.cornerRadiusMedium,
                    style: .continuous
                )
                .fill(AmenTheme.Colors.surfaceCard)
            } else {
                RoundedRectangle(
                    cornerRadius: LiquidGlassTokens.cornerRadiusMedium,
                    style: .continuous
                )
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(
                        cornerRadius: LiquidGlassTokens.cornerRadiusMedium,
                        style: .continuous
                    )
                    .fill(AmenTheme.Colors.amenGold.opacity(0.08))
                }
            }

        case .prominent:
            RoundedRectangle(
                cornerRadius: LiquidGlassTokens.cornerRadiusMedium,
                style: .continuous
            )
            .fill(AmenTheme.Colors.amenPurple)
        }
    }

    private var labelColor: Color {
        switch style {
        case .primary:   return AmenTheme.Colors.amenBlack
        case .secondary: return AmenTheme.Colors.amenGold
        case .prominent: return AmenTheme.Colors.textPrimary  // white in dark, dark in light
        }
    }

    private var strokeColor: Color {
        switch style {
        case .primary:   return AmenTheme.Colors.glassStroke
        case .secondary: return AmenTheme.Colors.amenGold
        case .prominent: return AmenTheme.Colors.amenPurple.opacity(0.40)
        }
    }
}

// MARK: - AMENGlassCard

/// Generic glass card for horizontal rail cells.
/// `.ultraThinMaterial` base + `AmenTheme.Colors.glassStroke` border + a
/// top-edge highlight gradient recreate Liquid Glass depth without iOS 26 APIs.
/// The tint bleed anchors the card to AMEN's brand palette.
struct AMENGlassCard<Content: View>: View {

    var width: CGFloat = 180
    var height: CGFloat = 120
    var tintColor: Color = AmenTheme.Colors.amenPurple
    @ViewBuilder var content: () -> Content

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var isPressed = false

    var body: some View {
        content()
            .frame(width: width, height: height)
            .background {
                if reduceTransparency {
                    RoundedRectangle(
                        cornerRadius: LiquidGlassTokens.cornerRadiusMedium,
                        style: .continuous
                    )
                    .fill(AmenTheme.Colors.surfaceCard)
                } else {
                    ZStack {
                        RoundedRectangle(
                            cornerRadius: LiquidGlassTokens.cornerRadiusMedium,
                            style: .continuous
                        )
                        .fill(.ultraThinMaterial)

                        // Tint bleed — AMEN brand color seeps into the glass
                        RoundedRectangle(
                            cornerRadius: LiquidGlassTokens.cornerRadiusMedium,
                            style: .continuous
                        )
                        .fill(tintColor.opacity(0.08))

                        // Top-edge inner highlight (specular gloss line)
                        VStack(spacing: 0) {
                            LinearGradient(
                                colors: [
                                    AmenTheme.Colors.glassHighlightTop,
                                    AmenTheme.Colors.glassHighlightBottom
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: height * 0.40)
                            Spacer()
                        }
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: LiquidGlassTokens.cornerRadiusMedium,
                                style: .continuous
                            )
                        )
                        .allowsHitTesting(false)
                    }
                }
            }
            .overlay {
                RoundedRectangle(
                    cornerRadius: LiquidGlassTokens.cornerRadiusMedium,
                    style: .continuous
                )
                .strokeBorder(AmenTheme.Colors.glassStroke, lineWidth: 1.0)
            }
            .shadow(
                color: LiquidGlassTokens.shadowSoft.color,
                radius: LiquidGlassTokens.shadowSoft.radius,
                y: LiquidGlassTokens.shadowSoft.y
            )
            .scaleEffect(isPressed && !reduceMotion ? 0.96 : 1.0)
            .animation(reduceMotion ? .none : Motion.springPress, value: isPressed)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isPressed) { _, state, _ in state = true }
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: LiquidGlassTokens.cornerRadiusMedium,
                    style: .continuous
                )
            )
    }
}

// MARK: - SpaceRailView

/// Horizontal scrolling rail of content cards with a faith-native section header.
/// The "See All ›" affordance uses amenGold — consistent with every other
/// secondary action in AMEN — not Apple's default system tint blue.
struct SpaceRailView<Item: Identifiable, CardContent: View>: View {

    /// Faith-native labels: "Continue Studying", "Your Spaces",
    /// "Recommended for your walk", "Trending in your church"
    let title: String
    let items: [Item]
    @ViewBuilder var card: (Item) -> CardContent

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // Section header
            HStack(alignment: .center) {
                Text(title)
                    .font(.headline.bold())
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                Spacer()

                Button {
                    // Caller wires destination via .onPreferenceChange or closure if needed
                } label: {
                    Text("See All ›")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AmenTheme.Colors.amenGold)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("See all \(title)")
            }
            .padding(.horizontal, 20)

            // Horizontal rail
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        card(item)
                            .staggeredReveal(
                                index: index,
                                baseDelay: 0.04,
                                maxDelay: 0.20
                            )
                    }
                }
                .padding(.leading, 20)
                .padding(.trailing, 20)
                .padding(.vertical, 4) // room for card shadow
            }
        }
    }
}

// MARK: - AMENGlassTabBar

/// Floating faith-native tab bar for Spaces navigation.
/// Blur intensity increases as `scrollOffset` grows (0→100pt maps to a 0.15
/// opacity boost on the glass layer). The active tab is marked with amenGold
/// — not Apple's default system tint — so the bar reads as AMEN at a glance.
struct AMENGlassTabBar: View {

    @Binding var selectedTab: SpacesTab
    /// Drives blur/opacity intensification. 0 = at top, positive = scrolled down.
    var scrollOffset: CGFloat

    @Namespace private var tabNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    // MARK: - SpacesTab

    enum SpacesTab: String, CaseIterable, Identifiable {
        case feed    = "house.fill"
        case study   = "book.fill"
        case prayer  = "hands.sparkles.fill"
        case spaces  = "rectangle.3.group.fill"
        case search  = "magnifyingglass"

        var id: String { rawValue }

        var label: String {
            switch self {
            case .feed:   return "Feed"
            case .study:  return "Study"
            case .prayer: return "Prayer"
            case .spaces: return "Spaces"
            case .search: return "Search"
            }
        }
    }

    // MARK: - Scroll-driven values (reduced-motion: always static)

    /// 0→100pt scroll maps to a 0→0.15 opacity boost on the glass layer.
    private var scrollBlurBoost: Double {
        guard !reduceMotion else { return 0 }
        return min(scrollOffset / 100.0, 1.0) * 0.15
    }

    /// Labels collapse after 60pt scroll (contracts bar height via Motion.liquidSpring).
    private var showLabels: Bool {
        reduceMotion || scrollOffset < 60
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            ForEach(SpacesTab.allCases) { tab in
                tabItem(tab)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .background {
            if reduceTransparency {
                Capsule(style: .continuous)
                    .fill(AmenTheme.Colors.surfaceElevated)
            } else {
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Capsule(style: .continuous)
                            .fill(AmenTheme.Colors.glassFill.opacity(scrollBlurBoost))
                    }
            }
        }
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(AmenTheme.Colors.glassStroke, lineWidth: 0.75)
        }
        .shadow(
            color: LiquidGlassTokens.shadowFloating.color,
            radius: LiquidGlassTokens.shadowFloating.radius,
            y: LiquidGlassTokens.shadowFloating.y
        )
        .padding(.horizontal, 20)
        .animation(
            reduceMotion ? .none : Motion.liquidSpring,
            value: showLabels
        )
    }

    // MARK: - Individual tab item

    @ViewBuilder
    private func tabItem(_ tab: SpacesTab) -> some View {
        let isActive = selectedTab == tab

        Button {
            withAnimation(reduceMotion ? .none : Motion.popToggle) {
                selectedTab = tab
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            VStack(spacing: 3) {
                ZStack(alignment: .bottom) {
                    Image(systemName: tab.rawValue)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(
                            isActive
                                ? AmenTheme.Colors.amenGold
                                : AmenTheme.Colors.textSecondary
                        )
                        .frame(width: 28, height: 28)
                        .scaleEffect(isActive ? 1.08 : 1.0)
                        .animation(
                            reduceMotion ? .none : Motion.popToggle,
                            value: isActive
                        )

                    // amenGold 2pt underline dot — active tab marker
                    if isActive {
                        Circle()
                            .fill(AmenTheme.Colors.amenGold)
                            .frame(width: 4, height: 4)
                            .offset(y: 6)
                            .matchedGeometryEffect(
                                id: "activeTabDot",
                                in: tabNamespace
                            )
                    }
                }

                if showLabels {
                    Text(tab.label)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(
                            isActive
                                ? AmenTheme.Colors.amenGold
                                : AmenTheme.Colors.textSecondary
                        )
                        .lineLimit(1)
                        .transition(
                            .opacity.combined(with: .scale(scale: 0.85))
                        )
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? .none : Motion.popToggle, value: isActive)
        .accessibilityLabel(tab.label)
        .accessibilityAddTraits(
            isActive ? [.isSelected, .isButton] : .isButton
        )
        .accessibilityHint(
            isActive ? "Currently selected" : "Switch to \(tab.label)"
        )
    }
}

// MARK: - GlassSheetModifier

/// View modifier for Liquid Glass modal sheets.
/// `.ultraThinMaterial` + tint bleed + specular sweep on appear (500ms easeOut)
/// + rubber-band edge deformation via DragGesture + Motion.liquidSpring snap-back.
/// Top corners use `cornerRadiusLarge` (32); bottom corners are 0 so the sheet
/// seats flush against the screen edge.
struct GlassSheetModifier: ViewModifier {

    var tintColor: Color = AmenTheme.Colors.amenPurple

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var dragOffset: CGFloat = 0
    @State private var specularProgress: Double = 0

    func body(content: Content) -> some View {
        content
            .background {
                sheetBackground
            }
            .overlay(alignment: .top) {
                // Drag indicator pill
                RoundedRectangle(cornerRadius: 3)
                    .fill(AmenTheme.Colors.glassStroke)
                    .frame(width: 36, height: 4)
                    .padding(.top, 8)
                    .accessibilityHidden(true)
            }
            .overlay {
                // Specular sweep: horizontal light band, plays once on appear
                if !reduceMotion {
                    GeometryReader { geo in
                        Rectangle()
                            .fill(specularGradient)
                            .frame(width: geo.size.width * 0.50, height: 2)
                            .offset(
                                x: specularProgress * geo.size.width - geo.size.width * 0.25,
                                y: LiquidGlassTokens.cornerRadiusLarge * 0.5
                            )
                            .opacity(1.0 - specularProgress * 0.8)
                            .allowsHitTesting(false)
                    }
                    .frame(height: 2)
                    .clipped()
                    .allowsHitTesting(false)
                }
            }
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: LiquidGlassTokens.cornerRadiusLarge,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: LiquidGlassTokens.cornerRadiusLarge,
                    style: .continuous
                )
            )
            .overlay(alignment: .top) {
                UnevenRoundedRectangle(
                    topLeadingRadius: LiquidGlassTokens.cornerRadiusLarge,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: LiquidGlassTokens.cornerRadiusLarge,
                    style: .continuous
                )
                .strokeBorder(AmenTheme.Colors.glassStroke, lineWidth: 0.75)
                .allowsHitTesting(false)
            }
            // Rubber-band: sqrt decay gives stiff resistance to downward drag
            .offset(y: dragOffset > 0 ? sqrt(dragOffset) * 3.5 : 0)
            .gesture(rubberBandGesture)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 0.50)) {
                    specularProgress = 1.0
                }
            }
    }

    // MARK: - Sub-views

    @ViewBuilder
    private var sheetBackground: some View {
        if reduceTransparency {
            Rectangle().fill(AmenTheme.Colors.surfaceElevated)
        } else {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Rectangle().fill(tintColor.opacity(0.05))
            }
        }
    }

    private var specularGradient: LinearGradient {
        LinearGradient(
            colors: [
                tintColor.opacity(0),
                tintColor.opacity(0.18),
                AmenTheme.Colors.glassHighlightTop,
                tintColor.opacity(0.18),
                tintColor.opacity(0)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var rubberBandGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                dragOffset = max(0, value.translation.height)
            }
            .onEnded { _ in
                withAnimation(Motion.liquidSpring) {
                    dragOffset = 0
                }
            }
    }
}

extension View {
    /// Applies the Liquid Glass sheet treatment: ultraThinMaterial + tint bleed +
    /// specular sweep on appear + rubber-band dismiss gesture.
    func amenGlassSheet(tint: Color = AmenTheme.Colors.amenPurple) -> some View {
        modifier(GlassSheetModifier(tintColor: tint))
    }
}

// MARK: - Previews

#if DEBUG

#Preview("SpaceHeroView — Bible Study") {
    SpaceHeroView(
        space: AmenSpaceExtended(
            communityId: "c1",
            type: .bibleStudy,
            title: "Deep Dive: Romans",
            description: "A weekly study of Paul's letter to the Romans.",
            avatarURL: nil,
            createdBy: "u1",
            createdAt: Date(),
            accessPolicy: .free,
            priceConfig: nil,
            sharedWith: [],
            isDeleted: false
        ),
        verseOverlay: "Romans 8:28",
        pageIndex: 0,
        totalPages: 3,
        onJoin: {},
        onSave: {}
    )
    .padding()
    .background(AmenTheme.Colors.amenBlack)
}

#Preview("AMENGlassTabBar") {
    struct PreviewWrapper: View {
        @State private var tab: AMENGlassTabBar.SpacesTab = .feed
        var body: some View {
            ZStack(alignment: .bottom) {
                AmenTheme.Colors.amenBlack.ignoresSafeArea()
                AMENGlassTabBar(selectedTab: $tab, scrollOffset: 0)
                    .padding(.bottom, 16)
            }
        }
    }
    return PreviewWrapper()
}

#Preview("AMENGlassPillButton — styles") {
    VStack(spacing: 16) {
        AMENGlassPillButton(title: "Open", icon: "arrow.right.circle.fill", style: .primary, action: {})
        AMENGlassPillButton(title: "Join Space", icon: "person.badge.plus", style: .secondary, action: {})
        AMENGlassPillButton(title: "Request Access", icon: "envelope.fill", style: .prominent, action: {})
    }
    .padding()
    .background(AmenTheme.Colors.backgroundPrimary)
}

#Preview("SpaceRailView") {
    struct DemoItem: Identifiable {
        let id: String
        let label: String
    }
    let items = (1...6).map { DemoItem(id: "item\($0)", label: "Space \($0)") }
    return ScrollView {
        VStack(spacing: 24) {
            SpaceRailView(title: "Continue Studying", items: items) { item in
                AMENGlassCard(tintColor: AmenTheme.Colors.amenPurple) {
                    VStack(spacing: 8) {
                        Image(systemName: "books.vertical.fill")
                            .font(.title2)
                            .foregroundStyle(AmenTheme.Colors.amenGold)
                        Text(item.label)
                            .font(.caption.bold())
                            .foregroundStyle(AmenTheme.Colors.textPrimary)
                    }
                }
            }
            SpaceRailView(title: "Trending in your church", items: items) { item in
                AMENGlassCard(
                    width: 160,
                    height: 100,
                    tintColor: AmenTheme.Colors.amenGold
                ) {
                    VStack(spacing: 8) {
                        Image(systemName: "flame.fill")
                            .font(.title2)
                            .foregroundStyle(AmenTheme.Colors.amenGold)
                        Text(item.label)
                            .font(.caption.bold())
                            .foregroundStyle(AmenTheme.Colors.textPrimary)
                    }
                }
            }
        }
        .padding(.vertical)
    }
    .background(AmenTheme.Colors.backgroundPrimary)
}

#Preview("GlassSheetModifier") {
    struct PreviewWrapper: View {
        @State private var show = true
        var body: some View {
            ZStack(alignment: .bottom) {
                AmenTheme.Colors.amenBlack.ignoresSafeArea()
                if show {
                    VStack(spacing: 16) {
                        Text("Gold Tinted Sheet")
                            .font(.headline)
                            .foregroundStyle(AmenTheme.Colors.textPrimary)
                        Text("Bible Study context — amenGold tint bleed.")
                            .font(.subheadline)
                            .foregroundStyle(AmenTheme.Colors.textSecondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 340)
                    .padding(.top, 24)
                    .padding(.horizontal, 20)
                    .amenGlassSheet(tint: AmenTheme.Colors.amenGold)
                }
            }
        }
    }
    return PreviewWrapper()
}

#endif
