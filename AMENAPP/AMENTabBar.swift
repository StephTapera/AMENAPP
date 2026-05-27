//
//  AMENTabBar.swift
//  AMENAPP
//
//  Floating Liquid Glass dock — iOS 26 Photos-style layout.
//  A glass circle on each side (Profile · Compose) flanks a center capsule
//  of destinations. Light, adaptive glass so the live feed refracts through
//  the bar as it scrolls underneath. Selection is shown by a frosted glass pill,
//  neutral black text (no forced accent), matching the reference.
//

import SwiftUI

// MARK: - Accent

private extension Color {
    static let amenTabAccent = Color(red: 0.04, green: 0.52, blue: 1.0)
}

private let useAccentForSelection = false

// MARK: - Light Glass Capsule Surface

struct LiquidGlassTabBarBackground: View {
    let isCompressed: Bool

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast: ColorSchemeContrast
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        capsuleSurface
            .overlay { Capsule(style: .continuous).fill(innerSheen) }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(refractionStroke, lineWidth: colorSchemeContrast == .increased ? 1.2 : 0.8)
            }
            .overlay(alignment: .topLeading) {
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(reduceTransparency ? 0.5 : 0.7), lineWidth: 1)
                    .blur(radius: 0.4)
                    .mask(LinearGradient(colors: [.white, .clear, .clear],
                                        startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .shadow(color: .black.opacity(reduceTransparency ? 0.10 : 0.16),
                    radius: isCompressed ? 12 : 20, x: 0, y: isCompressed ? 5 : 11)
    }

    private var innerSheen: Color {
        if reduceTransparency {
            return colorScheme == .dark ? Color.white.opacity(0.04) : Color.white.opacity(0.10)
        }
        return colorScheme == .dark ? Color.white.opacity(0.06) : Color.white.opacity(0.14)
    }

    private var refractionStroke: LinearGradient {
        if colorSchemeContrast == .increased {
            return LinearGradient(colors: [Color.white.opacity(0.85), Color.white.opacity(0.4), Color.white.opacity(0.7)],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        return LinearGradient(
            colors: [
                Color.white.opacity(reduceTransparency ? 0.6 : 0.8),
                Color.cyan.opacity(reduceTransparency ? 0.08 : 0.16),
                Color.pink.opacity(reduceTransparency ? 0.06 : 0.14),
                Color.white.opacity(reduceTransparency ? 0.45 : 0.6)
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    @ViewBuilder
    private var capsuleSurface: some View {
        if reduceTransparency {
            Capsule(style: .continuous)
                .fill(colorScheme == .dark ? Color(white: 0.14) : Color(white: 0.97))
        } else if #available(iOS 26.0, *) {
            Capsule(style: .continuous)
                .fill(Color.clear)
                .glassEffect(Glass.regular.interactive(), in: Capsule(style: .continuous))
        } else {
            Capsule(style: .continuous).fill(.ultraThinMaterial)
        }
    }
}

// MARK: - Detached Orb Surface (side circles)

struct LiquidGlassOrbBackground: View {
    let isCompressed: Bool

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast: ColorSchemeContrast
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        surface
            .overlay { Circle().fill(Color.white.opacity(reduceTransparency ? 0.06 : 0.14)) }
            .overlay {
                Circle().strokeBorder(
                    colorSchemeContrast == .increased ? Color.white.opacity(0.85) : Color.white.opacity(0.6),
                    lineWidth: colorSchemeContrast == .increased ? 1.2 : 0.8
                )
            }
            .shadow(color: .black.opacity(reduceTransparency ? 0.10 : 0.16),
                    radius: isCompressed ? 9 : 14, x: 0, y: isCompressed ? 3 : 7)
    }

    @ViewBuilder
    private var surface: some View {
        if reduceTransparency {
            Circle().fill(colorScheme == .dark ? Color(white: 0.16) : Color(white: 0.97))
        } else if #available(iOS 26.0, *) {
            Circle().fill(Color.clear).glassEffect(Glass.regular.interactive(), in: Circle())
        } else {
            Circle().fill(.ultraThinMaterial)
        }
    }
}

// MARK: - Selection Pill (frosted glass lift behind the active center tab)

struct LiquidGlassActiveTabCapsule: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if #available(iOS 26.0, *), !reduceTransparency {
            Capsule(style: .continuous)
                .fill(Color.clear)
                .glassEffect(Glass.regular, in: Capsule(style: .continuous))
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(pillStroke, lineWidth: colorSchemeContrast == .increased ? 1.2 : 0.9)
                }
                .shadow(color: .black.opacity(0.10), radius: 6, x: 0, y: 3)
        } else {
            Capsule(style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.06))
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(
                            colorScheme == .dark ? Color.white.opacity(0.22) : Color.black.opacity(0.05),
                            lineWidth: colorSchemeContrast == .increased ? 1.0 : 0.6
                        )
                }
        }
    }

    private var pillStroke: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.72),
                Color.white.opacity(0.30),
                Color.white.opacity(0.55)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
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

    func count(for tab: AMENTab) -> Int {
        switch tab {
        case .home:          return home
        case .search:        return search
        case .messages:      return messages
        case .library:       return library
        case .notifications: return notifications
        case .profile:       return profile
        case .gatherings:    return gatherings
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

    var activeIcon: String {
        switch self {
        case .home:          return "house.fill"
        case .search:        return "magnifyingglass"
        case .messages:      return "bubble.left.and.bubble.right.fill"
        case .library:       return "books.vertical.fill"
        case .notifications: return "bell.fill"
        case .profile:       return "person.crop.circle.fill"
        case .gatherings:    return "person.3.sequence.fill"
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
        }
    }

    var label: String {
        switch self {
        case .home:          return "Home"
        case .search:        return "Explore"
        case .messages:      return "Chats"
        case .library:       return "Library"
        case .notifications: return "Alerts"
        case .profile:       return "You"
        case .gatherings:    return "Gather"
        }
    }

    var tag: Int { rawValue }
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
    @Namespace private var selectionNamespace

    private var selectedColor: Color   { useAccentForSelection ? .amenTabAccent : .primary }
    private var unselectedColor: Color { Color.primary.opacity(0.55) }

    private var centerTabs: [AMENTab] {
        var tabs: [AMENTab] = [.home, .search, .messages, .library, .notifications]
        if flags.gatheringsEnabled { tabs.append(.gatherings) }
        return tabs
    }

    private var barHeight: CGFloat { isMinimized ? 46 : 54 }

    // Physical hide: bar shrinks into the bottom edge rather than flying off-screen
    private var hideTransform: (scale: CGFloat, opacity: Double, offsetY: CGFloat) {
        if isMinimized {
            return (scale: 0.82, opacity: 0.0, offsetY: 10)
        }
        return (scale: 1.0, opacity: 1.0, offsetY: 0)
    }

    var body: some View {
        HStack(spacing: 10) {
            profileOrb
            centerCapsule
            composeOrb
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
        .scaleEffect(hideTransform.scale, anchor: .bottom)
        .opacity(hideTransform.opacity)
        .offset(y: hideTransform.offsetY)
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
    }

    // MARK: Center capsule

    private var centerCapsule: some View {
        HStack(spacing: 2) {
            ForEach(centerTabs, id: \.rawValue) { tab in
                tabColumn(tab).frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 6)
        .frame(height: barHeight)
        .frame(maxWidth: .infinity)
        .background { LiquidGlassTabBarBackground(isCompressed: isMinimized) }
        .clipShape(Capsule(style: .continuous))
    }

    @ViewBuilder
    private func tabColumn(_ tab: AMENTab) -> some View {
        let isSelected = selectedTab == tab.rawValue
        Button { handleTap(tab) } label: {
            VStack(spacing: 2) {
                ZStack(alignment: .topTrailing) {
                    iconView(for: tab, isSelected: isSelected)
                    if badges.count(for: tab) > 0 {
                        BadgeView(count: badges.count(for: tab)).offset(x: 10, y: -6)
                    }
                }
                if !isMinimized {
                    Text(tab.label)
                        .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .foregroundStyle(isSelected ? selectedColor : unselectedColor)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 5)
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
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityLabel(badges.count(for: tab) > 0
            ? "\(tab.label), \(badges.count(for: tab)) unread"
            : tab.label)
        .accessibilityHint("Opens the \(tab.label) tab")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .contextMenu { tabContextMenu(for: tab) }
    }

    @ViewBuilder
    private func iconView(for tab: AMENTab, isSelected: Bool) -> some View {
        if #available(iOS 17.0, *) {
            Image(systemName: isSelected ? tab.activeIcon : tab.inactiveIcon)
                .font(.system(size: 19, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(isSelected ? selectedColor : unselectedColor)
                .frame(width: 24, height: 22)
                .symbolEffect(.bounce, options: .speed(1.6), value: isSelected)
                .accessibilityHidden(true)
        } else {
            Image(systemName: isSelected ? tab.activeIcon : tab.inactiveIcon)
                .font(.system(size: 19, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(isSelected ? selectedColor : unselectedColor)
                .frame(width: 24, height: 22)
                .scaleEffect(isSelected ? 1.03 : 1.0)
                .animation(reduceMotion ? .none : .spring(response: 0.22, dampingFraction: 0.82), value: isSelected)
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
        let isSelected = selectedTab == AMENTab.profile.rawValue
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
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityLabel(AMENTab.profile.label)
        .accessibilityHint("Opens your profile")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private func profileContent(isSelected: Bool) -> some View {
        if let url = profilePhotoURL, !url.isEmpty {
            AsyncImage(url: URL(string: url)) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill()
                        .frame(width: barHeight - 18, height: barHeight - 18)
                        .clipShape(Circle())
                } else {
                    profileIcon(isSelected: isSelected)
                }
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
            HapticManager.impact(style: .light)
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
        .search:        .searchTabTapped,
        .messages:      .messagesTabTapped,
        .library:       .libraryTabTapped,
        .notifications: .notificationsTabTapped,
        .profile:       .profileTabTapped,
        .gatherings:    .gatheringsTabTapped,
    ]

    private func handleTap(_ tab: AMENTab) {
        if selectedTab == tab.rawValue {
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
        withAnimation(reduceMotion ? .easeInOut(duration: 0.18)
                                   : .spring(response: 0.34, dampingFraction: 0.84)) {
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
        }
    }
}

// MARK: - Badge View

private struct BadgeView: View {
    let count: Int
    private var displayText: String { count >= 100 ? "99+" : "\(count)" }
    @State private var pulsing = false

    var body: some View {
        Text(displayText)
            .font(.systemScaled(10, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, count >= 10 ? 4 : 0)
            .frame(minWidth: 17, minHeight: 17)
            .background(Color(red: 0.937, green: 0.267, blue: 0.267))
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Color(.systemBackground).opacity(0.9), lineWidth: 1.5))
            .scaleEffect(pulsing ? 1.35 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.5), value: pulsing)
            .onChange(of: count) { oldValue, newValue in
                guard newValue > oldValue else { return }
                pulsing = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { pulsing = false }
            }
    }
}

// MARK: - Button Styles

private struct ComposeButtonStyle: ButtonStyle {
    let reduceMotion: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

private struct LiquidGlassTabButtonStyle: ButtonStyle {
    let reduceMotion: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            // tighter damping = snappier, more physical rebound
            .animation(reduceMotion ? nil : .spring(response: 0.20, dampingFraction: 0.70),
                       value: configuration.isPressed)
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
        withAnimation(.easeOut(duration: 0.18)) { isMinimized = true }
    }

    func expand() {
        guard isMinimized else { return }
        withAnimation(Motion.adaptive(.spring(response: 0.28, dampingFraction: 0.78))) { isMinimized = false }
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
    static let homeTabMarkRead        = Notification.Name("amen.homeTabMarkRead")
    static let messagesTabMarkRead    = Notification.Name("amen.messagesTabMarkRead")
    static let notificationsTabClear  = Notification.Name("amen.notificationsTabClear")
    static let libraryTabRecentlySaved = Notification.Name("amen.libraryTabRecentlySaved")
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
