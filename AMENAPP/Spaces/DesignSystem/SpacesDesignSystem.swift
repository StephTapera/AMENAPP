// SpacesDesignSystem.swift
// AMENAPP — Spaces v2 Design System (Agent 2, iOS 26 Liquid Glass)
//
// Uses native iOS 26 APIs exclusively:
//   .glassEffect(), GlassEffectContainer, glassEffectID + @Namespace,
//   .buttonStyle(.glass / .glassProminent), .tint()
// No ultraThinMaterial fallbacks. No duplicate design system.
//
// Color tokens  → AmenTheme.Colors (amenGold / amenPurple / amenBlue / amenBlack ONLY)
// Spacing/radii → LiquidGlassTokens
// Animation     → Motion.swift

import SwiftUI

// MARK: - SpaceHeroView

/// Full-bleed hero card for a Space carousel.
/// heroTint bleeds the AMEN accent into the glass surface — never neutral white.
///   Bible Study  → amenGold
///   Community    → amenPurple
///   Announcement → amenBlue
@available(iOS 26.0, *)
struct SpaceHeroView: View {

    let space: AmenSpaceExtended
    var verseOverlay: String? = nil
    var pageIndex: Int = 0
    var totalPages: Int = 1
    var onJoin: () -> Void
    var onSave: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var heroNamespace

    private var heroTint: Color {
        switch space.type {
        case .bibleStudy:   return AmenTheme.Colors.amenGold
        case .chat, .group: return AmenTheme.Colors.amenPurple
        case .announcement: return AmenTheme.Colors.amenBlue
        }
    }

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

                if let verse = verseOverlay {
                    Text(verse)
                        .font(.caption.italic())
                        .foregroundStyle(AmenTheme.Colors.amenGold)
                        .lineLimit(1)
                        .padding(.bottom, 4)
                        .accessibilityLabel("Scripture: \(verse)")
                }

                Text(space.title)
                    .font(.title2.bold())
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .lineLimit(2)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.bottom, 8)

                SpaceFaithMetadataRow(
                    spaceType: space.type,
                    memberCount: 0,
                    bibleVersion: space.type == .bibleStudy ? "KJV" : nil,
                    liturgicalSeason: nil,
                    churchBadge: nil
                )
                .padding(.bottom, 14)

                // GlassEffectContainer lets the join pill and bookmark morph
                // between states (e.g. Join → Leave) with liquid geometry.
                GlassEffectContainer(spacing: 12) {
                    HStack(spacing: 12) {
                        AMENGlassPillButton(
                            title: primaryActionLabel,
                            icon: actionIcon,
                            style: heroTint == AmenTheme.Colors.amenGold ? .primary : .prominent,
                            action: onJoin
                        )
                        .glassEffectID("primaryAction", in: heroNamespace)
                        .accessibilityLabel("\(primaryActionLabel) \(space.title)")

                        Button(action: onSave) {
                            Image(systemName: "bookmark.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.glass)
                        .tint(heroTint)
                        .glassEffectID("saveAction", in: heroNamespace)
                        .accessibilityLabel("Save \(space.title)")
                        .accessibilityHint("Bookmarks this Space for later.")

                        Spacer()
                    }
                }
                .padding(.bottom, 14)

                if totalPages > 1 {
                    HStack(spacing: 5) {
                        ForEach(0..<totalPages, id: \.self) { idx in
                            Capsule()
                                .fill(idx == pageIndex
                                    ? AmenTheme.Colors.amenGold
                                    : AmenTheme.Colors.glassStroke)
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

            // AMEN brand tint bleed over the hero surface
            Rectangle()
                .fill(heroTint.opacity(0.07))
                .allowsHitTesting(false)
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

    @ViewBuilder
    private var heroImage: some View {
        if let urlStr = space.avatarURL, let url = URL(string: urlStr) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    heroFallbackGradient
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 280)
            .clipped()
        } else {
            heroFallbackGradient.frame(maxWidth: .infinity, minHeight: 280)
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

/// Faith-native chip row beneath the hero title.
/// Chips are wrapped in GlassEffectContainer so adjacent chips merge their
/// glass shapes when packed close together, reading as one fluid surface.
/// Gold `·` separators make the row unmistakably AMEN, not a generic streaming UI.
@available(iOS 26.0, *)
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
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 4) {
                    ChurchBadgeChip(badge: .init(
                        icon: spaceType.systemImageName,
                        label: spaceType.displayName,
                        tint: AmenTheme.Colors.amenPurple
                    ))

                    if memberCount > 0 {
                        goldDot
                        ChurchBadgeChip(badge: .init(
                            icon: "person.2.fill",
                            label: memberCount == 1 ? "1 member" : "\(memberCount) members",
                            tint: AmenTheme.Colors.amenGold
                        ))
                    }

                    if let version = bibleVersion {
                        goldDot
                        ChurchBadgeChip(badge: .init(
                            icon: "book.closed.fill",
                            label: version,
                            tint: AmenTheme.Colors.amenGold
                        ))
                    }

                    if let season = liturgicalSeason {
                        goldDot
                        ChurchBadgeChip(badge: .init(
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
                .padding(.horizontal, 1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(a11yLabel)
    }

    private var a11yLabel: String {
        var parts: [String] = [spaceType.displayName]
        if memberCount > 0 { parts.append("\(memberCount) members") }
        if let v = bibleVersion { parts.append(v) }
        if let s = liturgicalSeason { parts.append(s) }
        return parts.joined(separator: ", ")
    }
}

// MARK: - ChurchBadgeChip

/// One piece of faith metadata as a native iOS 26 glass pill.
/// The tint bleeds directly into the Liquid Glass material — the chip reads
/// as AMEN-branded, not a flat white system chip.
@available(iOS 26.0, *)
struct ChurchBadgeChip: View {

    struct Badge {
        let icon: String   // SF Symbol name
        let label: String
        let tint: Color    // must be an AmenTheme.Colors value
    }

    let badge: Badge

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
        .glassEffect(
            .regular.tint(badge.tint),
            in: .rect(cornerRadius: LiquidGlassTokens.cornerRadiusMedium)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(badge.label)
    }
}

// MARK: - AMENGlassPillButton

/// Three AMEN-branded glass pill variants using native iOS 26 button styles.
///   .primary   → glassProminent + amenGold tint (primary faith action)
///   .secondary → glass          + amenGold tint (secondary / outline action)
///   .prominent → glassProminent + amenPurple tint (community / social action)
///
/// Press animation, touch reaction, and reduce-motion are handled by the system.
@available(iOS 26.0, *)
struct AMENGlassPillButton: View {

    enum Style {
        case primary    // glassProminent + amenGold
        case secondary  // glass          + amenGold
        case prominent  // glassProminent + amenPurple
    }

    let title: String
    var icon: String? = nil
    var style: Style = .primary
    var action: () -> Void

    var body: some View {
        pillButton
            .accessibilityLabel(title)
    }

    @ViewBuilder
    private var pillButton: some View {
        switch style {
        case .primary:
            baseButton
                .buttonStyle(.glassProminent)
                .tint(AmenTheme.Colors.amenGold)
        case .secondary:
            baseButton
                .buttonStyle(.glass)
                .tint(AmenTheme.Colors.amenGold)
        case .prominent:
            baseButton
                .buttonStyle(.glassProminent)
                .tint(AmenTheme.Colors.amenPurple)
        }
    }

    private var baseButton: some View {
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
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
        }
    }
}

// MARK: - AMENGlassCard

/// Generic glass card for horizontal rail cells.
/// `.regular.tint(tintColor)` bleeds the AMEN brand color into the Liquid Glass
/// material. `.interactive()` gives the card the same touch-reactive fluid physics
/// as a system glass button — no manual press gesture required.
@available(iOS 26.0, *)
struct AMENGlassCard<Content: View>: View {

    var width: CGFloat = 180
    var height: CGFloat = 120
    var tintColor: Color = AmenTheme.Colors.amenPurple
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(width: width, height: height)
            .glassEffect(
                .regular.tint(tintColor).interactive(),
                in: .rect(cornerRadius: LiquidGlassTokens.cornerRadiusMedium)
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

/// Horizontal glass-card rail with a faith-native section header.
/// "See All ›" uses `.buttonStyle(.glass)` + amenGold tint — never system blue.
/// Rail labels are study-native: "Continue Studying", "Your Spaces",
/// "Recommended for your walk", "Trending in your church".
@available(iOS 26.0, *)
struct SpaceRailView<Item: Identifiable, CardContent: View>: View {

    let title: String
    let items: [Item]
    var onSeeAll: (() -> Void)? = nil
    @ViewBuilder var card: (Item) -> CardContent

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Text(title)
                    .font(.headline.bold())
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                Spacer()

                Button(action: onSeeAll ?? {}) {
                    Text("See All ›")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.glass)
                .tint(AmenTheme.Colors.amenGold)
                .accessibilityLabel("See all \(title)")
                .disabled(onSeeAll == nil)
            }
            .padding(.horizontal, 20)

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
                .padding(.vertical, 4)
            }
        }
    }
}

// MARK: - AMENGlassTabBar

/// Floating faith-native tab bar using GlassEffectContainer.
///
/// Architecture: all tab buttons live inside one GlassEffectContainer with
/// spacing: 0. With zero spacing the individual glass shapes fully merge,
/// forming a single seamless capsule. The active tab carries a `.tint(amenGold)`
/// on its Glass effect, creating a gold-tinted highlight region. As selection
/// changes, `glassEffectID` + `.matchedGeometry` transition morphs that
/// highlight fluidly between tab positions — the AMEN active-state indicator,
/// not Apple's default system blue.
///
/// Scroll-driven behaviour: at scrollOffset ≥ 60pt the labels collapse via
/// Motion.liquidSpring; the bar contracts smoothly.
@available(iOS 26.0, *)
struct AMENGlassTabBar: View {

    @Binding var selectedTab: SpacesTab
    /// Drives label collapse. 0 = at top, positive = scrolled down.
    var scrollOffset: CGFloat

    @Namespace private var tabNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

    private var showLabels: Bool { reduceMotion || scrollOffset < 60 }

    var body: some View {
        GlassEffectContainer(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(SpacesTab.allCases) { tab in
                    tabItem(tab)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, showLabels ? 6 : 4)
        }
        .padding(.horizontal, 20)
        .animation(reduceMotion ? .none : Motion.liquidSpring, value: showLabels)
    }

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
                Image(systemName: tab.rawValue)
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .scaleEffect(isActive ? 1.08 : 1.0)
                    .animation(reduceMotion ? .none : Motion.popToggle, value: isActive)

                if showLabels {
                    Text(tab.label)
                        .font(.caption2.weight(.medium))
                        .lineLimit(1)
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
        }
        // Glass button with amenGold tint when active; neutral when inactive.
        // Inside GlassEffectContainer(spacing:0) the shapes merge into one bar.
        // glassEffectID + .matchedGeometry morphs the gold highlight between positions.
        .buttonStyle(.glass(.regular.tint(isActive ? AmenTheme.Colors.amenGold : .clear)))
        .glassEffectID(tab.id, in: tabNamespace)
        .glassEffectTransition(.matchedGeometry)
        .animation(reduceMotion ? .none : Motion.popToggle, value: isActive)
        .accessibilityLabel(tab.label)
        .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : .isButton)
        .accessibilityHint(isActive ? "Currently selected" : "Switch to \(tab.label)")
    }
}

// MARK: - GlassSheetModifier

/// Liquid Glass modal sheet treatment using native iOS 26 glassEffect.
/// `.regular.tint(tintColor)` bleeds the AMEN accent into the sheet material.
/// Top corners are rounded (`cornerRadiusLarge`); bottom corners are 0 so the
/// sheet seats flush against the screen edge.
///
/// Extras layered on top of the system glass:
///   - Specular sweep: tinted horizontal band plays once on appear (500ms easeOut)
///   - Rubber-band: sqrt-decay resistance on downward drag, snaps back via liquidSpring
@available(iOS 26.0, *)
struct GlassSheetModifier: ViewModifier {

    var tintColor: Color = AmenTheme.Colors.amenPurple

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragOffset: CGFloat = 0
    @State private var specularProgress: Double = 0

    func body(content: Content) -> some View {
        content
            .glassEffect(
                .regular.tint(tintColor),
                in: UnevenRoundedRectangle(
                    topLeadingRadius: LiquidGlassTokens.cornerRadiusLarge,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: LiquidGlassTokens.cornerRadiusLarge,
                    style: .continuous
                )
            )
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(AmenTheme.Colors.glassStroke)
                    .frame(width: 36, height: 4)
                    .padding(.top, 8)
                    .accessibilityHidden(true)
            }
            .overlay {
                if !reduceMotion {
                    specularSweep
                }
            }
            .offset(y: dragOffset > 0 ? sqrt(dragOffset) * 3.5 : 0)
            .gesture(rubberBandGesture)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 0.50)) {
                    specularProgress = 1.0
                }
            }
    }

    // Tinted horizontal specular band — reads as AMEN accent, not plain white gloss.
    @ViewBuilder
    private var specularSweep: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(
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
                )
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

    private var rubberBandGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { dragOffset = max(0, $0.translation.height) }
            .onEnded { _ in
                withAnimation(Motion.liquidSpring) { dragOffset = 0 }
            }
    }
}

@available(iOS 26.0, *)
extension View {
    /// Applies the AMEN Liquid Glass sheet: native glassEffect tint bleed +
    /// specular sweep on appear + rubber-band dismiss.
    func amenGlassSheet(tint: Color = AmenTheme.Colors.amenPurple) -> some View {
        modifier(GlassSheetModifier(tintColor: tint))
    }
}

// MARK: - Previews

#if DEBUG

@available(iOS 26.0, *)
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

@available(iOS 26.0, *)
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

@available(iOS 26.0, *)
#Preview("AMENGlassPillButton — three styles") {
    VStack(spacing: 16) {
        AMENGlassPillButton(title: "Open", icon: "arrow.right.circle.fill", style: .primary, action: {})
        AMENGlassPillButton(title: "Join Space", icon: "person.badge.plus", style: .secondary, action: {})
        AMENGlassPillButton(title: "Request Access", icon: "envelope.fill", style: .prominent, action: {})
    }
    .padding()
    .background(AmenTheme.Colors.backgroundPrimary)
}

@available(iOS 26.0, *)
#Preview("SpaceRailView") {
    struct DemoItem: Identifiable {
        let id: String; let label: String
    }
    let items = (1...6).map { DemoItem(id: "item\($0)", label: "Space \($0)") }
    return ScrollView {
        VStack(spacing: 24) {
            SpaceRailView(title: "Continue Studying", items: items) { item in
                AMENGlassCard(tintColor: AmenTheme.Colors.amenPurple) {
                    VStack(spacing: 8) {
                        Image(systemName: "books.vertical.fill").font(.title2)
                            .foregroundStyle(AmenTheme.Colors.amenGold)
                        Text(item.label).font(.caption.bold())
                            .foregroundStyle(AmenTheme.Colors.textPrimary)
                    }
                }
            }
            SpaceRailView(title: "Trending in your church", items: items) { item in
                AMENGlassCard(width: 160, height: 100, tintColor: AmenTheme.Colors.amenGold) {
                    VStack(spacing: 8) {
                        Image(systemName: "flame.fill").font(.title2)
                            .foregroundStyle(AmenTheme.Colors.amenGold)
                        Text(item.label).font(.caption.bold())
                            .foregroundStyle(AmenTheme.Colors.textPrimary)
                    }
                }
            }
        }
        .padding(.vertical)
    }
    .background(AmenTheme.Colors.backgroundPrimary)
}

@available(iOS 26.0, *)
#Preview("GlassSheetModifier") {
    struct PreviewWrapper: View {
        var body: some View {
            ZStack(alignment: .bottom) {
                AmenTheme.Colors.amenBlack.ignoresSafeArea()
                VStack(spacing: 16) {
                    Text("Bible Study Context")
                        .font(.headline)
                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                    Text("amenGold tint bleed into native Liquid Glass sheet.")
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
    return PreviewWrapper()
}

#endif
