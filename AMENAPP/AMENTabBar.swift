//
//  AMENTabBar.swift
//  AMENAPP
//
//  Floating liquid glass tab bar — glass pill, original button order, compose at end.
//

import SwiftUI
import Combine

// MARK: - Badge Count Model

struct AMENBadgeCounts {
    var home:          Int = 0
    var search:        Int = 0
    var messages:      Int = 0
    var library:       Int = 0
    var notifications: Int = 0
    var profile:       Int = 0

    func count(for tab: AMENTab) -> Int {
        switch tab {
        case .home:          return home
        case .search:        return search
        case .messages:      return messages
        case .library:       return library
        case .notifications: return notifications
        case .profile:       return profile
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

    var activeIcon: String {
        switch self {
        case .home:          return "house.fill"
        case .search:        return "magnifyingglass"
        case .messages:      return "bubble.left.and.bubble.right.fill"
        case .library:       return "books.vertical.fill"
        case .notifications: return "bell.fill"
        case .profile:       return "person.circle.fill"
        }
    }

    var inactiveIcon: String {
        switch self {
        case .home:          return "house"
        case .search:        return "magnifyingglass"
        case .messages:      return "bubble.left.and.bubble.right"
        case .library:       return "books.vertical"
        case .notifications: return "bell"
        case .profile:       return "person.circle"
        }
    }

    var label: String {
        switch self {
        case .home:          return "Home"
        case .search:        return "Search"
        case .messages:      return "Messages"
        case .library:       return "Library"
        case .notifications: return "Notifications"
        case .profile:       return "Profile"
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

    var body: some View {
        HStack(spacing: 0) {
            // All 6 tabs in original order (compact spacing)
            ForEach(AMENTab.allCases, id: \.rawValue) { tab in
                tabItem(tab)
                    .frame(width: 50, height: 48)
            }

            // Subtle divider between tabs and compose (monochrome)
            Rectangle()
                .fill(AmenTheme.Colors.separatorSubtle)
                .frame(width: 0.5, height: 20)
                .padding(.horizontal, 6)

            // Compose button at end
            composeButton
                .padding(.leading, 2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(glassBackground)
        .clipShape(Capsule())
        // Refined layered shadow for premium floating effect
        .shadow(color: AmenTheme.Colors.shadowFloating.opacity(0.70), radius: 20, x: 0, y: 8)
        .shadow(color: AmenTheme.Colors.shadowFloating.opacity(0.38), radius: 8, x: 0, y: 3)
        .shadow(color: AmenTheme.Colors.shadowFloating.opacity(0.20), radius: 2, x: 0, y: 1)
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
        .offset(y: isMinimized ? 100 : 0)
        .animation(.easeOut(duration: 0.18), value: isMinimized)
    }

    // MARK: - Glass background (adaptive for light and dark mode)

    @Environment(\.colorScheme) private var colorScheme

    private var glassBackground: some View {
        let isDark = colorScheme == .dark

        return ZStack {
            // Layer 1 — Material blur base (auto-adapts to dark/light)
            Capsule()
                .fill(.ultraThinMaterial)

            // Layer 2 — Adaptive highlight fill
            // Light: bright white glass | Dark: barely-there smoke
            Capsule()
                .fill(AmenTheme.Colors.glassFill)
            Capsule()
                .fill(AmenTheme.Colors.surfaceGlassDark)

            // Layer 3 — Directional top highlight (reduced in dark mode)
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            AmenTheme.Colors.glassHighlightTop.opacity(isDark ? 0.8 : 1.0),
                            AmenTheme.Colors.glassHighlightBottom.opacity(isDark ? 1.0 : 0.9),
                            Color.clear
                        ],
                        startPoint: .init(x: 0.2, y: 0),
                        endPoint: .init(x: 0.7, y: 0.4)
                    )
                )
                .allowsHitTesting(false)

            // Layer 4 — Depth pooling (more visible in dark mode for separation)
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.clear,
                            AmenTheme.Colors.glassDepth.opacity(isDark ? 0.72 : 0.40),
                            AmenTheme.Colors.glassDepth.opacity(isDark ? 1.0 : 0.65)
                        ],
                        startPoint: .init(x: 0.3, y: 0.6),
                        endPoint: .init(x: 1, y: 1)
                    )
                )
                .allowsHitTesting(false)

            // Layer 5 — Edge contour stroke
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            AmenTheme.Colors.glassStroke.opacity(isDark ? 1.0 : 0.92),
                            AmenTheme.Colors.glassStroke.opacity(isDark ? 0.45 : 0.36),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
                .allowsHitTesting(false)
        }
    }

    // MARK: - Tab item

    @ViewBuilder
    private func tabItem(_ tab: AMENTab) -> some View {
        let isSelected = selectedTab == tab.rawValue
        Button {
            guard selectedTab != tab.rawValue else { return }
            selectedTab = tab.rawValue
            clearBadge(for: tab)
        } label: {
            ZStack {
                // Selected state: Ink Motion sculpted glass tile
                if isSelected {
                    Capsule()
                        .fill(colorScheme == .dark ? AmenTheme.Colors.surfaceElevated : AmenTheme.Colors.surfaceCard)
                        .background(
                            Capsule()
                                .fill(.thinMaterial)
                        )
                        .overlay(
                            // Directional top-left highlight (molded glass polish)
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            AmenTheme.Colors.glassHighlightTop.opacity(colorScheme == .dark ? 0.55 : 0.95),
                                            AmenTheme.Colors.glassHighlightBottom.opacity(colorScheme == .dark ? 0.7 : 0.9),
                                            Color.clear
                                        ],
                                        startPoint: .init(x: 0.15, y: 0),
                                        endPoint: .init(x: 0.8, y: 0.5)
                                    )
                                )
                        )
                        .overlay(
                            // Subtle black depth on opposite edge
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.clear,
                                            AmenTheme.Colors.glassDepth.opacity(colorScheme == .dark ? 0.8 : 0.45)
                                        ],
                                        startPoint: .init(x: 0.2, y: 0.5),
                                        endPoint: .init(x: 1, y: 1)
                                    )
                                )
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(
                                    AmenTheme.Colors.borderSoft,
                                    lineWidth: 0.5
                                )
                        )
                        .shadow(color: AmenTheme.Colors.shadowCard.opacity(0.65), radius: 6, x: 0, y: 2)
                        .shadow(color: AmenTheme.Colors.shadowCard.opacity(0.28), radius: 2, x: 0, y: 1)
                        .frame(width: 44, height: 36)
                        .transition(.scale(scale: 0.92).combined(with: .opacity))
                        .animation(.spring(response: 0.22, dampingFraction: 0.75), value: isSelected)
                }

                // Icon with badge pinned to its top-right corner
                ZStack(alignment: .topTrailing) {
                    if tab == .profile, let url = profilePhotoURL, !url.isEmpty {
                        profileAvatar(url: url, isSelected: isSelected)
                    } else {
                        Image(systemName: isSelected ? tab.activeIcon : tab.inactiveIcon)
                            .font(.systemScaled(19, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? AmenTheme.Colors.iconPrimary : AmenTheme.Colors.iconSecondary)
                            .scaleEffect(isSelected ? 1.03 : 1.0)
                            .animation(.spring(response: 0.22, dampingFraction: 0.75), value: isSelected)
                    }

                    let count = badges.count(for: tab)
                    if count > 0 {
                        BadgeView(count: count)
                            .offset(x: 8, y: -6)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityLabel(tab.label)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Profile avatar

    private func profileAvatar(url: String, isSelected: Bool) -> some View {
        AsyncImage(url: URL(string: url)) { phase in
            if case .success(let image) = phase {
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: 24, height: 24)
                    .clipShape(Circle())
                    .overlay(
                        Circle().strokeBorder(
                            (isSelected ? AmenTheme.Colors.iconPrimary : AmenTheme.Colors.iconSecondary).opacity(isSelected ? 0.9 : 0.5),
                            lineWidth: isSelected ? 2 : 1
                        )
                    )
            } else {
                Image(systemName: isSelected ? AMENTab.profile.activeIcon : AMENTab.profile.inactiveIcon)
                    .font(.systemScaled(21, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? AmenTheme.Colors.iconPrimary : AmenTheme.Colors.iconSecondary)
            }
        }
    }

    // MARK: - Compose button

    // MARK: - Compose button (Ink Motion Tile aesthetic — compact monochrome)
    
    private var composeButton: some View {
        Button(action: onCompose) {
            ZStack {
                // Soft outer glow (monochrome)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                AmenTheme.Colors.shadowFloating.opacity(0.32),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 20
                        )
                    )
                    .frame(width: 48, height: 48)
                
                // Main sculpted glass button
                Circle()
                    .fill(colorScheme == .dark ? AmenTheme.Colors.surfaceElevated : AmenTheme.Colors.surfaceCard)
                    .background(
                        Circle()
                            .fill(.regularMaterial)
                    )
                    .frame(width: 40, height: 40)
                    .overlay(
                        // Directional top-left polish
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        AmenTheme.Colors.glassHighlightTop.opacity(colorScheme == .dark ? 0.65 : 1.0),
                                        AmenTheme.Colors.glassHighlightBottom.opacity(colorScheme == .dark ? 0.9 : 1.0),
                                        Color.clear
                                    ],
                                    startPoint: .init(x: 0.2, y: 0.1),
                                    endPoint: .init(x: 0.8, y: 0.6)
                                )
                            )
                            .frame(width: 40, height: 40)
                    )
                    .overlay(
                        // Subtle black depth on opposite edge
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.clear,
                                        AmenTheme.Colors.glassDepth.opacity(colorScheme == .dark ? 0.85 : 0.55)
                                    ],
                                    startPoint: .init(x: 0.2, y: 0.4),
                                    endPoint: .init(x: 1, y: 1)
                                )
                            )
                            .frame(width: 40, height: 40)
                    )
                    .overlay(
                        // Refined edge
                        Circle()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        AmenTheme.Colors.glassStroke.opacity(colorScheme == .dark ? 1.0 : 0.9),
                                        AmenTheme.Colors.borderSoft.opacity(colorScheme == .dark ? 0.75 : 1.0)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.5
                            )
                    )
                    .shadow(color: AmenTheme.Colors.shadowFloating.opacity(0.60), radius: 8, x: 0, y: 3)
                    .shadow(color: AmenTheme.Colors.shadowFloating.opacity(0.24), radius: 3, x: 0, y: 1)
                
                // Plus icon (black on white)
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AmenTheme.Colors.iconPrimary)
            }
        }
        .buttonStyle(ComposeButtonStyle())
        .frame(width: 48, height: 48)
        .contentShape(Circle())
        .accessibilityLabel("Create post")
    }

    // MARK: - Helpers

    private func clearBadge(for tab: AMENTab) {
        switch tab {
        case .home:          badges.home = 0
        case .search:        badges.search = 0
        case .messages:      badges.messages = 0
        case .library:       badges.library = 0
        case .notifications: badges.notifications = 0
        case .profile:       badges.profile = 0
        }
    }
}

// MARK: - Badge View

private struct BadgeView: View {
    let count: Int
    @State private var previousCount: Int = 0

    private var displayText: String { count >= 100 ? "99+" : "\(count)" }

    var body: some View {
        Text(displayText)
            .font(.systemScaled(10, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, count >= 10 ? 4 : 0)
            .frame(minWidth: 17, minHeight: 17)
            .background(Color(red: 0.937, green: 0.267, blue: 0.267))
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Color(.systemBackground).opacity(0.9), lineWidth: 1.5))
            .onAppear { previousCount = count }
            .onChange(of: count) { _, new in previousCount = new }
    }
}

// MARK: - Compose Button Style

private struct ComposeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Host Wrapper

struct AMENTabBarHost: View {
    @Binding var selectedTab: Int
    @Binding var badges: AMENBadgeCounts
    var onCompose: () -> Void
    var profilePhotoURL: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            AMENTabBar(
                selectedTab: $selectedTab,
                badges: $badges,
                onCompose: onCompose,
                profilePhotoURL: profilePhotoURL
            )
        }
        .ignoresSafeArea(edges: .bottom)
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

private struct AMENScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct AMENScrollTrackingModifier: ViewModifier {
    @State private var lastOffset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: AMENScrollOffsetKey.self,
                        value: geo.frame(in: .named("amenScroll")).minY
                    )
                }
            )
            .onPreferenceChange(AMENScrollOffsetKey.self) { offset in
                let delta = offset - lastOffset
                if offset > -12 {
                    AMENTabBarScrollBridge.shared.expand()
                } else if delta < -4 {
                    AMENTabBarScrollBridge.shared.minimize()
                } else if delta > 3 {
                    AMENTabBarScrollBridge.shared.expand()
                }
                lastOffset = offset
            }
    }
}

extension View {
    func amenTabBarScrollTracking() -> some View {
        modifier(AMENScrollTrackingModifier())
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var tab: Int = 0
    @Previewable @State var badges = AMENBadgeCounts(messages: 3, notifications: 24)

    ZStack {
        Color(.systemGroupedBackground).ignoresSafeArea()
        VStack {
            Spacer()
            AMENTabBar(selectedTab: $tab, badges: $badges, onCompose: {})
        }
    }
}
