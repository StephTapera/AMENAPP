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
            // All 6 tabs in original order
            ForEach(AMENTab.allCases, id: \.rawValue) { tab in
                tabItem(tab)
            }

            // Divider between tabs and compose
            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(width: 0.5, height: 24)
                .padding(.horizontal, 2)

            // Compose button at end
            composeButton
                .padding(.trailing, 4)
        }
        .padding(.horizontal, 6)
        .frame(height: 54)
        .background(glassBackground)
        .clipShape(Capsule())
        // ✨ Enhanced shadow for elevated liquid glass effect
        .shadow(color: .black.opacity(0.08), radius: 30, x: 0, y: 12)  // Soft outer shadow
        .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 6)   // Mid-range shadow
        .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)    // Subtle contact shadow
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
        .offset(y: isMinimized ? 100 : 0)
        .animation(.easeOut(duration: 0.18), value: isMinimized)
    }

    // MARK: - Glass background (Liquid Glass — visible on white)

    private var glassBackground: some View {
        ZStack {
            // Layer 1 — base material
            Capsule()
                .fill(.ultraThinMaterial)

            // Layer 2 — white luminosity overlay (keeps it light without going opaque)
            Capsule()
                .fill(Color.white.opacity(0.55))

            // Layer 3 — top specular highlight strip (inner edge light)
            Capsule()
                .inset(by: 1)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.55), Color.clear],
                        startPoint: .top,
                        endPoint: .init(x: 0.5, y: 0.38)
                    )
                )

            // Layer 4 — hairline border: visible on white, not on dark
            Capsule()
                .strokeBorder(Color(white: 0.72).opacity(0.55), lineWidth: 0.5)
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
                // Selected state glass capsule highlight
                if isSelected {
                    Capsule()
                        .fill(.thinMaterial)
                        .overlay(Capsule().fill(Color.white.opacity(0.70)))
                        .overlay(Capsule().strokeBorder(Color(white: 0.82).opacity(0.4), lineWidth: 0.5))
                        .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
                        .frame(width: 42, height: 34)
                        .transition(.scale(scale: 0.7).combined(with: .opacity))
                        .animation(.spring(response: 0.22, dampingFraction: 0.7), value: isSelected)
                }

                // Icon with badge pinned to its top-right corner
                ZStack(alignment: .topTrailing) {
                    if tab == .profile, let url = profilePhotoURL, !url.isEmpty {
                        profileAvatar(url: url, isSelected: isSelected)
                    } else {
                        Image(systemName: isSelected ? tab.activeIcon : tab.inactiveIcon)
                            .font(.system(size: 21, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.45))
                            .scaleEffect(isSelected ? 1.06 : 1.0)
                            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: isSelected)
                    }

                    let count = badges.count(for: tab)
                    if count > 0 {
                        BadgeView(count: count)
                            .offset(x: 9, y: -7)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
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
                            Color.primary.opacity(isSelected ? 0.9 : 0.25),
                            lineWidth: isSelected ? 2 : 1
                        )
                    )
            } else {
                Image(systemName: isSelected ? AMENTab.profile.activeIcon : AMENTab.profile.inactiveIcon)
                    .font(.system(size: 21, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.38))
            }
        }
    }

    // MARK: - Compose button

    private var composeButton: some View {
        Button(action: onCompose) {
            ZStack {
                // Glass ring outer layer
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(Circle().fill(Color.white.opacity(0.30)))
                    .overlay(Circle().strokeBorder(Color(white: 0.72).opacity(0.55), lineWidth: 0.5))
                    .frame(width: 38, height: 38)
                // Solid inner circle — keeps the button identifiable as primary action
                Circle()
                    .fill(Color.primary)
                    .frame(width: 30, height: 30)
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(.systemBackground))
            }
        }
        .buttonStyle(ComposeButtonStyle())
        .frame(width: 44, height: 44)
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
            .font(.system(size: 10, weight: .bold))
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
            .scaleEffect(configuration.isPressed ? 0.86 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
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
        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) { isMinimized = false }
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
