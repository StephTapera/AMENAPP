//
//  AMENTabBar.swift
//  AMENAPP
//
//  Floating Liquid Glass dock — Apple Developer app-style layout.
//  A glass circle on each side (Profile · Compose) flanks a center capsule
//  of destinations. Light, adaptive glass so the live feed refracts through
//  the bar as it scrolls underneath. Selection is shown by a glass pill with
//  blue accent tinting on the active icon and label.
//

import SwiftUI

// MARK: - Accent

private extension Color {
    // Forward the canonical brand token so this file needs no magic number.
    static let amenTabAccent = AmenTheme.Colors.amenBlue
}

private let useAccentForSelection = true

// MARK: - Light Glass Capsule Surface

struct LiquidGlassTabBarBackground: View {
    let isCompressed: Bool

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast: ColorSchemeContrast
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if #available(iOS 26.0, *), !reduceTransparency {
            // Real Liquid Glass: let the system handle refraction — no extra overlay layers.
            Capsule(style: .continuous)
                .fill(Color.clear)
                .glassEffect(Glass.regular.interactive(), in: Capsule(style: .continuous))
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(colorSchemeContrast == .increased ? 0.6 : 0.35),
                                      lineWidth: colorSchemeContrast == .increased ? 1.2 : 0.5)
                }
                .shadow(color: .black.opacity(0.14), radius: isCompressed ? 12 : 20,
                        x: 0, y: isCompressed ? 5 : 11)
        } else {
            // Pre-iOS 26 / Reduce Transparency: multi-layer rasterised fallback.
            Capsule(style: .continuous)
                .fill(solidFill)
                .overlay {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.10))
                }
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(colorSchemeContrast == .increased ? 0.7 : 0.45),
                                      lineWidth: colorSchemeContrast == .increased ? 1.2 : 0.6)
                }
                .drawingGroup()
                .shadow(color: .black.opacity(reduceTransparency ? 0.10 : 0.16),
                        radius: isCompressed ? 12 : 20, x: 0, y: isCompressed ? 5 : 11)
        }
    }

    private var solidFill: Color {
        reduceTransparency
            ? (colorScheme == .dark ? Color(white: 0.14) : Color(white: 0.97))
            : (colorScheme == .dark ? Color(white: 0.16).opacity(0.92) : Color(white: 0.96).opacity(0.88))
    }
}

// MARK: - Detached Orb Surface (side circles)

struct LiquidGlassOrbBackground: View {
    let isCompressed: Bool

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast: ColorSchemeContrast
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if #available(iOS 26.0, *), !reduceTransparency {
            Circle()
                .fill(Color.clear)
                .glassEffect(Glass.regular.interactive(), in: Circle())
                .overlay {
                    Circle().strokeBorder(Color.white.opacity(colorSchemeContrast == .increased ? 0.6 : 0.35),
                                          lineWidth: colorSchemeContrast == .increased ? 1.2 : 0.5)
                }
                .shadow(color: .black.opacity(0.14), radius: isCompressed ? 9 : 14,
                        x: 0, y: isCompressed ? 3 : 7)
        } else {
            Circle()
                .fill(solidFill)
                .overlay { Circle().fill(Color.white.opacity(0.10)) }
                .overlay {
                    Circle().strokeBorder(Color.white.opacity(colorSchemeContrast == .increased ? 0.7 : 0.45),
                                          lineWidth: colorSchemeContrast == .increased ? 1.2 : 0.6)
                }
                .shadow(color: .black.opacity(reduceTransparency ? 0.10 : 0.16),
                        radius: isCompressed ? 9 : 14, x: 0, y: isCompressed ? 3 : 7)
        }
    }

    private var solidFill: Color {
        reduceTransparency
            ? (colorScheme == .dark ? Color(white: 0.16) : Color(white: 0.97))
            : (colorScheme == .dark ? Color(white: 0.16).opacity(0.92) : Color(white: 0.96).opacity(0.88))
    }
}

// MARK: - Selection Pill (solid elevated surface behind the active center tab)
// Solid fill — not glass-on-glass. Glass cannot sample other glass; a solid
// lifted surface (like Threads) reads cleanly inside the glass bar.

struct LiquidGlassActiveTabCapsule: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Capsule(style: .continuous)
            .fill(selectionFill)
            .shadow(color: .black.opacity(0.10), radius: 4, x: 0, y: 2)
    }

    private var selectionFill: Color {
        colorScheme == .dark
            ? Color(white: colorSchemeContrast == .increased ? 0.32 : 0.26)
            : Color(white: colorSchemeContrast == .increased ? 0.84 : 0.90)
    }
}

// MARK: - Badge Count Model

struct AMENBadgeCounts {
    var home:          Int = 0
    var search:        Int = 0
    var messages:      Int = 0
    var library:       Int = 0
    var notifications: Int = 0
    var profile:       Int = 0
    var gatherings:    Int = 0
    // TODO: populate from AmenConnectService unread space counts when a
    // dedicated BadgeCountManager publisher is wired up for Spaces.
    var spaces:        Int = 0
    // TODO: populate from a CommunityNotes unread-count publisher when available.
    var communityNotes: Int = 0

    func count(for tab: AMENTab) -> Int {
        switch tab {
        case .home:          return home
        case .search:        return search
        case .messages:      return messages
        case .library:       return library
        case .notifications: return notifications
        case .profile:       return profile
        case .gatherings:    return gatherings
        case .spaces:        return spaces
        case .communityNotes: return communityNotes
        }
    }
}

// MARK: - Tab Definition

enum AMENTab: Int, CaseIterable {
    case home
    case search
    case messages
    case library
    case notifications
    case profile
    case gatherings    // rawValue 6 — gated on AMENFeatureFlags.gatheringsEnabled
    case spaces        // rawValue 7 — Spaces v2 (Agent C), gated on SpacesFeatureFlags.spacesLiquidGlassEnabled
    case communityNotes // rawValue 8 — gated on AMENFeatureFlags.communityNotesEnabled

    var activeIcon: String {
        switch self {
        case .home:          return "house.fill"
        case .search:        return "magnifyingglass"
        case .messages:      return "bubble.left.and.bubble.right.fill"
        case .library:       return "books.vertical.fill"
        case .notifications: return "bell.fill"
        case .profile:       return "person.crop.circle.fill"
        case .gatherings:    return "person.3.sequence.fill"
        case .spaces:        return "house.and.flag.fill"
        case .communityNotes: return "doc.text.fill"
        }
    }

    var inactiveIcon: String {
        switch self {
        case .home:          return "house"
        case .search:        return "magnifyingglass"
        case .messages:      return "bubble.left.and.bubble.right"
        case .library:       return "books.vertical"
        case .notifications: return "bell"
        case .profile:       return "person.crop.circle"
        case .gatherings:    return "person.3.sequence"
        case .spaces:        return "house.and.flag"
        case .communityNotes: return "doc.text"
        }
    }

    var label: String {
        switch self {
        case .home:          return "Home"
        case .search:        return "Explore"
        case .messages:      return "Messages"
        case .library:       return "Library"
        case .notifications: return "Notifications"
        case .profile:       return "Profile"
        case .gatherings:    return "Gather"
        case .spaces:        return "Spaces"
        case .communityNotes: return "Notes"
        }
    }

    var tag: Int { rawValue }

    /// Full spoken name for VoiceOver — differs from the compact visible label.
    var accessibilityName: String {
        switch self {
        case .home:          return "Home"
        case .search:        return "Explore"
        case .messages:      return "Messages"
        case .library:       return "Library"
        case .notifications: return "Notifications"
        case .profile:       return "Profile"
        case .gatherings:    return "Gatherings"
        case .spaces:        return "Spaces"
        case .communityNotes: return "Community Notes"
        }
    }

    /// Full VoiceOver label, appending badge count only when count > 0.
    func accessibilityLabel(badgeCount: Int) -> String {
        guard badgeCount > 0 else { return accessibilityName }
        return "\(accessibilityName), \(badgeCount) unread"
    }
}

// MARK: - Main Tab Bar

struct AMENTabBar: View {
    @Binding var selectedTab: Int
    @Binding var badges: AMENBadgeCounts
    var onCompose: () -> Void
    var profilePhotoURL: String? = nil
    var isMinimized: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var restModeGate = RestModeGate.shared
    @ObservedObject private var flags = AMENFeatureFlags.shared
    @State private var showRestModeSheet = false
    @State private var showProfileSheet = false
    @Namespace private var selectionNamespace

    private var selectedColor: Color   { useAccentForSelection ? .amenTabAccent : .primary }
    private var unselectedColor: Color { Color.primary.opacity(0.55) }

    /// Center capsule destinations. Profile lives in the left orb; compose is the right orb.
    private var centerTabs: [AMENTab] {
        [.home, .search, .messages, .library, .notifications]
    }

    private var barHeight: CGFloat { isMinimized ? 36 : 44 }

    var body: some View {
        HStack(spacing: 7) {
            profileOrb
            centerCapsule
            composeOrb
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
        .scaleEffect(y: isMinimized ? 0.97 : 1.0, anchor: .bottom)
        .animation(reduceMotion ? .easeOut(duration: 0.16)
                                : .spring(response: 0.34, dampingFraction: 0.86),
                   value: isMinimized)
        .sheet(isPresented: $showRestModeSheet) {
            SundayRestModeSheet(
                onFindChurch:    { NotificationCenter.default.post(name: .navigateToFindChurch, object: nil) },
                onChurchNotes:   { NotificationCenter.default.post(name: .navigateToChurchNotes, object: nil) },
                onDailyVerse:    { selectedTab = AMENTab.library.rawValue },
                onPrayerRequest: { selectedTab = AMENTab.home.rawValue },
                onDismiss:       { showRestModeSheet = false }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(24)
        }
        .sheet(isPresented: $showProfileSheet) {
            AmenProfileGlassActionSheet { _ in
                showProfileSheet = false
            }
        }
    }

    // MARK: Center capsule

    @ViewBuilder
    private var centerCapsule: some View {
        if flags.liquidGlassPillNav {
            AMENPillNav(
                tabs: centerTabs,
                selectedTab: $selectedTab,
                badges: $badges,
                onTabTap: handleTap,
                barHeight: barHeight,
                isMinimized: isMinimized
            )
        } else {
            HStack(spacing: 2) {
                ForEach(centerTabs, id: \.rawValue) { tab in
                    tabColumn(tab).frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 6)
            .frame(height: barHeight)
            .frame(maxWidth: .infinity)
            // Apply clipShape to the background only, NOT the HStack content.
            // This allows badge views (which offset outside the capsule bounds) to render
            // unclipped while the glass surface still gets a proper capsule shape.
            .background {
                LiquidGlassTabBarBackground(isCompressed: isMinimized)
                    .clipShape(Capsule(style: .continuous))
            }
        }
    }

    @ViewBuilder
    private func tabColumn(_ tab: AMENTab) -> some View {
        let isSelected = visibleSelectedTab(for: selectedTab) == tab.rawValue
        Button { handleTap(tab) } label: {
            VStack(spacing: 2) {
                ZStack(alignment: .topTrailing) {
                    iconView(for: tab, isSelected: isSelected)
                    if badges.count(for: tab) > 0 {
                        // Offset positions badge center at top-trailing corner of the icon.
                        // x: half badge width (~8.5pt) to clear the icon edge.
                        // y: -half badge height (~8.5pt) to sit above the icon top edge.
                        BadgeView(count: badges.count(for: tab)).offset(x: 9, y: -9)
                    }
                }
            }
            .padding(.horizontal, 3)
            .padding(.vertical, isMinimized ? 5 : 7)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                if isSelected {
                    LiquidGlassActiveTabCapsule()
                        .matchedGeometryEffect(id: "amen_selected_pill", in: selectionNamespace)
                }
            }
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(LiquidGlassTabButtonStyle(reduceMotion: reduceMotion))
        .accessibilityLabel(tab.accessibilityLabel(badgeCount: badges.count(for: tab)))
        .accessibilityHint("Double tap to open \(tab.accessibilityName)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .contextMenu { tabContextMenu(for: tab) }
    }

    @ViewBuilder
    private func iconView(for tab: AMENTab, isSelected: Bool) -> some View {
        let badgeCount = badges.count(for: tab)
        if #available(iOS 17.0, *) {
            Image(systemName: isSelected ? tab.activeIcon : tab.inactiveIcon)
                .font(.system(size: 19, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(isSelected ? selectedColor : unselectedColor)
                .frame(width: 24, height: 22)
                // Pattern 8: selection bounce + badge-arrival bounce for bell/messages
                .symbolEffect(.bounce, options: .speed(1.6), value: isSelected)
                .symbolEffect(.bounce, options: .speed(1.2), value: badgeCount)
                .accessibilityHidden(true)
        } else {
            Image(systemName: isSelected ? tab.activeIcon : tab.inactiveIcon)
                .font(.system(size: 19, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(isSelected ? selectedColor : unselectedColor)
                .frame(width: 24, height: 22)
                .scaleEffect(isSelected ? 1.03 : 1.0)
                .animation(reduceMotion ? .none : Motion.liquidSpring, value: isSelected)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func tabContextMenu(for tab: AMENTab) -> some View {
        switch tab {
        case .home:
            Button {
                badges.home = 0
                NotificationCenter.default.post(name: .homeTabMarkRead, object: nil)
            } label: {
                Label("Mark All Read", systemImage: "checkmark.circle")
            }
        case .messages:
            Button {
                HapticManager.impact(style: .light)
                onCompose()
            } label: {
                Label("New Message", systemImage: "square.and.pencil")
            }
            Divider()
            Button {
                badges.messages = 0
                NotificationCenter.default.post(name: .messagesTabMarkRead, object: nil)
            } label: {
                Label("Mark All Read", systemImage: "checkmark.circle")
            }
        case .notifications:
            Button(role: .destructive) {
                badges.notifications = 0
                NotificationCenter.default.post(name: .notificationsTabClear, object: nil)
            } label: {
                Label("Clear All Alerts", systemImage: "xmark.circle")
            }
        case .library:
            Button {
                NotificationCenter.default.post(name: .libraryTabRecentlySaved, object: nil)
            } label: {
                Label("Recently Saved", systemImage: "clock")
            }
        default:
            EmptyView()
        }
    }

    // MARK: Left circle — Profile

    private var profileOrb: some View {
        let isSelected = visibleSelectedTab(for: selectedTab) == AMENTab.profile.rawValue
        let badge = badges.profile
        return Button { handleTap(.profile) } label: {
            ZStack {
                LiquidGlassOrbBackground(isCompressed: isMinimized)
                ZStack(alignment: .topTrailing) {
                    profileContent(isSelected: isSelected)
                    if badge > 0 { BadgeView(count: badge).offset(x: 11, y: -11) }
                }
            }
            .frame(width: barHeight, height: barHeight)
            .overlay {
                if isSelected {
                    Circle().strokeBorder(selectedColor.opacity(0.9), lineWidth: 2)
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(ComposeButtonStyle(reduceMotion: reduceMotion))
        .accessibilityLabel(AMENTab.profile.accessibilityLabel(badgeCount: badge))
        .accessibilityHint("Double tap to open Profile. Long press for quick actions.")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                HapticManager.impact(style: .medium)
                withAnimation(.spring(response: 0.30, dampingFraction: 0.82)) {
                    showProfileSheet = true
                }
            }
        )
    }

    @ViewBuilder
    private func profileContent(isSelected: Bool) -> some View {
        if let url = profilePhotoURL, !url.isEmpty {
            CachedAsyncImage(url: URL(string: url)) { image in
                image.resizable().scaledToFill()
                    .frame(width: barHeight - 18, height: barHeight - 18)
                    .clipShape(Circle())
            } placeholder: {
                profileIcon(isSelected: isSelected)
            }
            .accessibilityHidden(true)
        } else {
            profileIcon(isSelected: isSelected)
        }
    }

    private func profileIcon(isSelected: Bool) -> some View {
        Image(systemName: isSelected ? AMENTab.profile.activeIcon : AMENTab.profile.inactiveIcon)
            .font(.system(size: 21, weight: .semibold))
            .foregroundStyle(isSelected ? selectedColor : Color.primary.opacity(0.72))
            .accessibilityHidden(true)
    }

    // MARK: Right circle — Compose

    private var composeOrb: some View {
        Button {
            HapticManager.impact(style: .medium)
            onCompose()
        } label: {
            ZStack {
                LiquidGlassOrbBackground(isCompressed: isMinimized)
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.primary)
                    .accessibilityHidden(true)
            }
            .frame(width: barHeight, height: barHeight)
            .contentShape(Circle())
        }
        .buttonStyle(ComposeButtonStyle(reduceMotion: reduceMotion))
        .accessibilityLabel("Create post")
        .accessibilityHint("Compose a new post")
    }

    // MARK: Tap handling

    private static let retapNotification: [AMENTab: Notification.Name] = [
        .home:          .homeTabTapped,
        .messages:      .messagesTabTapped,
        .library:       .libraryTabTapped,
        .notifications: .notificationsTabTapped,
        .profile:       .profileTabTapped,
    ]

    /// Maps a raw selectedTab index to the tab that should appear highlighted in the bar.
    private func visibleSelectedTab(for rawTab: Int) -> Int {
        return rawTab
    }

    private func handleTap(_ tab: AMENTab) {
        if selectedTab == tab.rawValue {
            // Retap (same tab): selection haptic signals scroll-to-top, then post notification.
            HapticManager.selection()
            if let name = Self.retapNotification[tab] {
                NotificationCenter.default.post(name: name, object: nil)
            }
            return
        }
        let tabRoute = route(for: tab)
        if restModeGate.isActive && !restModeGate.canOpen(tabRoute) {
            showRestModeSheet = true
            return
        }
        PerformanceLog.event("tab_switch", String(tab.rawValue))
        withAnimation(reduceMotion ? .easeInOut(duration: 0.18) : Motion.liquidSpring) {
            selectedTab = tab.rawValue
        }
        HapticManager.impact(style: .light)
        clearBadge(for: tab)
    }

    private func route(for tab: AMENTab) -> AmenRoute {
        switch tab {
        case .home:          return .feed
        case .search:        return .search
        case .messages:      return .messages
        case .library:       return .resources
        case .notifications: return .notifications
        case .profile:       return .profile
        case .gatherings:    return .gatherings
        case .spaces:        return .spaces
        case .communityNotes: return .communityNotes
        }
    }

    private func clearBadge(for tab: AMENTab) {
        switch tab {
        case .home:          badges.home = 0
        case .search:        badges.search = 0
        case .messages:      badges.messages = 0
        case .library:       badges.library = 0
        case .notifications: badges.notifications = 0
        case .profile:       badges.profile = 0
        case .gatherings:    badges.gatherings = 0
        case .spaces, .communityNotes: break
        }
    }
}

// MARK: - Badge View

private struct BadgeView: View {
    let count: Int
    // Cap at "9+": counts 1–9 show the digit, 10+ shows "9+".
    private var displayText: String { count > 9 ? "9+" : "\(count)" }
    @State private var pulsing = false
    // Spring scale state for appear (0→1) and disappear (1→0) transitions.
    @State private var badgeScale: CGFloat = 1.0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(displayText)
            .font(.systemScaled(10, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, count > 9 ? 4 : 0)
            .frame(minWidth: 17, minHeight: 17)
            .background(AmenTheme.Colors.statusError)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Color(.systemBackground).opacity(0.9), lineWidth: 1.5))
            // Compose pulse (increment) and appear/disappear scale together.
            .scaleEffect(pulsing ? 1.35 : badgeScale)
            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.5), value: pulsing)
            .animation(Motion.adaptive(Motion.popToggle), value: badgeScale)
            .onAppear {
                // Animate in when badge first appears (0→positive).
                if count > 0 {
                    badgeScale = 0.01
                    withAnimation(Motion.adaptive(Motion.popToggle)) {
                        badgeScale = 1.0
                    }
                }
            }
            .accessibilityValue("\(count) new items")
            .onChange(of: count) { oldValue, newValue in
                // Increment pulse: existing badge gets a bounce on any count increase.
                // Skip the bounce pulse when Reduce Motion is enabled.
                if !reduceMotion && newValue > oldValue && newValue > 0 && oldValue > 0 {
                    pulsing = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { pulsing = false }
                }
                // Appear: count transitions from 0 → positive — spring pop in.
                if oldValue == 0 && newValue > 0 {
                    badgeScale = 0.01
                    withAnimation(Motion.adaptive(Motion.popToggle)) {
                        badgeScale = 1.0
                    }
                }
                // Disappear: count transitions to 0 — spring shrink out.
                // The parent conditionally renders BadgeView only when count > 0,
                // so this handles cases where the view persists briefly during transition.
                if newValue == 0 {
                    withAnimation(Motion.adaptive(Motion.springPress)) {
                        badgeScale = 0.01
                    }
                }
            }
    }
}

// MARK: - Button Styles

private struct ComposeButtonStyle: ButtonStyle {
    let reduceMotion: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.90 : 1.0)
            .animation(reduceMotion ? nil : Motion.liquidSpring, value: configuration.isPressed)
    }
}

private struct LiquidGlassTabButtonStyle: ButtonStyle {
    let reduceMotion: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.90 : 1.0)
            // Pattern 7: unified 0.96 press-shrink with canonical bouncy spring
            .animation(reduceMotion ? nil : Motion.liquidSpring, value: configuration.isPressed)
    }
}

// MARK: - Host Wrapper

struct AMENTabBarHost: View {
    @Binding var selectedTab: Int
    @Binding var badges: AMENBadgeCounts
    var onCompose: () -> Void
    var profilePhotoURL: String? = nil
    var isMinimized: Bool = false

    var body: some View {
        AMENTabBar(selectedTab: $selectedTab, badges: $badges,
                   onCompose: onCompose, profilePhotoURL: profilePhotoURL,
                   isMinimized: isMinimized)
    }
}

// MARK: - Scroll-Reactive Tab Bar Bridge

@MainActor
final class AMENTabBarScrollBridge: ObservableObject {
    static let shared = AMENTabBarScrollBridge()
    @Published var isMinimized: Bool = false

    func minimize() {
        guard !isMinimized else { return }
        // Pattern 2: use canonical bouncy spring for size/position change
        withAnimation(Motion.liquidSpringAdaptive) { isMinimized = true }
    }

    func expand() {
        guard isMinimized else { return }
        withAnimation(Motion.liquidSpringAdaptive) { isMinimized = false }
    }
}

// MARK: - Scroll Tracking
//
// Uses a 44pt cumulative threshold so the bar only hides when the user has
// genuinely scrolled down — not on micro-jitter. Upward scroll resets the
// accumulator so the threshold must be crossed again to re-hide.

private struct AMENScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private let hideThreshold: CGFloat  = 44   // points of sustained downward scroll to trigger hide
private let expandThreshold: CGFloat = 6   // points of upward scroll to trigger expand

private struct AMENScrollTrackingModifier: ViewModifier {
    @State private var lastOffset: CGFloat = 0
    @State private var downwardAccumulator: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: AMENScrollOffsetKey.self,
                                           value: geo.frame(in: .named("amenScroll")).minY)
                }
            )
            .onPreferenceChange(AMENScrollOffsetKey.self) { offset in
                let delta = offset - lastOffset
                lastOffset = offset

                // Near the top — always show
                if offset > -12 {
                    downwardAccumulator = 0
                    AMENTabBarScrollBridge.shared.expand()
                    return
                }

                if delta < 0 {
                    // Scrolling down — accumulate
                    downwardAccumulator += abs(delta)
                    if downwardAccumulator >= hideThreshold {
                        AMENTabBarScrollBridge.shared.minimize()
                    }
                } else if delta > expandThreshold {
                    // Meaningful upward scroll — reset accumulator and show
                    downwardAccumulator = 0
                    AMENTabBarScrollBridge.shared.expand()
                }
            }
    }
}

extension View {
    func amenTabBarScrollTracking() -> some View {
        modifier(AMENScrollTrackingModifier())
    }
}

// MARK: - Notification Names (context menu actions)

extension Notification.Name {
    static let homeTabMarkRead         = Notification.Name("amen.homeTabMarkRead")
    static let messagesTabMarkRead     = Notification.Name("amen.messagesTabMarkRead")
    static let notificationsTabClear   = Notification.Name("amen.notificationsTabClear")
    static let libraryTabRecentlySaved = Notification.Name("amen.libraryTabRecentlySaved")
    static let communityNotesTabTapped = Notification.Name("amen.communityNotesTabTapped")
    static let navigateToCommunityNotes = Notification.Name("amen.navigateToCommunityNotes")
}

// MARK: - Preview

#Preview {
    @Previewable @State var tab: Int = 0
    @Previewable @State var badges = AMENBadgeCounts(messages: 3, notifications: 24)

    ZStack {
        LinearGradient(colors: [.orange, .pink, .purple],
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
        VStack {
            Spacer()
            AMENTabBar(selectedTab: $tab, badges: $badges, onCompose: {})
        }
    }
}
