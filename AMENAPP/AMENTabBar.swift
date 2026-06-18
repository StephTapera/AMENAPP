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
    var spaces:        Int = 0
    var intelligence:  Int = 0

    func count(for tab: AMENTab) -> Int {
        switch tab {
        case .home:          return home
        case .search:        return search
        case .messages:      return messages
        case .library:       return library
        case .notifications: return notifications
        // Profile badge shows its own count + notification count
        // since notifications tab is not in the visible bar.
        case .profile:       return profile + notifications
        case .spaces:        return spaces
        case .intelligence:  return intelligence
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
    case spaces
    case intelligence

    var activeIcon: String {
        switch self {
        case .home:          return "house.fill"
        case .search:        return "magnifyingglass"
        case .messages:      return "bubble.left.and.bubble.right.fill"
        case .library:       return "books.vertical.fill"
        case .notifications: return "bell.fill"
        case .profile:       return "person.circle.fill"
        case .spaces:        return "rectangle.3.group.fill"
        case .intelligence:  return "sparkles"
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
        case .spaces:        return "rectangle.3.group"
        case .intelligence:  return "sparkles"
        }
    }

    var label: String {
        switch self {
        case .home:          return "Home"
        case .search:        return "Search"
        case .messages:      return "Messages"
        case .library:       return "Resources"
        case .notifications: return "Notifications"
        case .profile:       return "Profile"
        case .spaces:        return "Spaces"
        case .intelligence:  return "Brief"
        }
    }

    var accessibilityHint: String {
        switch self {
        case .home:          return "Shows your home feed"
        case .search:        return "Search for people, posts, and communities"
        case .messages:      return "Opens your conversations"
        case .library:       return "Browse resources, church notes, and more"
        case .notifications: return "View your notifications and activity"
        case .profile:       return "View and edit your profile"
        case .spaces:        return "Browse and join community spaces"
        case .intelligence:  return "View your personalized intelligence brief"
        }
    }

    /// The five tabs shown in the bottom bar. All other tabs remain
    /// navigable via deep links / programmatic selection.
    static let visibleTabs: [AMENTab] = [.home, .search, .messages, .library, .profile]

    var tag: Int { rawValue }
}

// MARK: - Main Tab Bar

struct AMENTabBar: View {
    @Binding var selectedTab: Int
    @Binding var badges: AMENBadgeCounts
    var onCompose: () -> Void
    var onCameraOS: (() -> Void)? = nil
    var profilePhotoURL: String? = nil
    var isMinimized: Bool = false

    @Namespace private var selectionNamespace

    /// True when the tab bar should slide off-screen. Merges the caller-supplied
    /// `isMinimized` flag with the adaptive engine's .hidden state (full-screen video).
    private var effectivelyHidden: Bool {
        isMinimized || (AMENFeatureFlags.shared.adaptiveGlassV2Enabled && effectiveState == .hidden)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // ── 5-tab pill bar — compact, icon-only liquid glass capsule ──
            HStack(spacing: 0) {
                ForEach(AMENTab.visibleTabs, id: \.rawValue) { tab in
                    tabItem(tab)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(glassBackground)
            .clipShape(Capsule())
            .shadow(color: Color.black.opacity(0.10), radius: 18, x: 0, y: 8)
            .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)

            // ── Floating compose FAB — pinned bottom-right, lifted clear of the bar ──
            composeButton
                .padding(.trailing, 4)
                .offset(y: -64)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        // Top padding so the lifted compose FAB isn't clipped by the ZStack bounds
        .padding(.top, 64)
        .offset(y: effectivelyHidden ? 100 : 0)
        .animation(.easeOut(duration: 0.18), value: effectivelyHidden)
        // Drive the active-pill slide animation
        .animation(
            Motion.adaptive(.spring(response: 0.30, dampingFraction: 0.72)),
            value: selectedTab
        )
    }

    // MARK: - Glass background (adaptive for light and dark mode)

    @Environment(\.colorScheme)        private var colorScheme
    @Environment(\.glassSurfaceState)  private var adaptiveState

    private var effectiveState: GlassSurfaceState {
        AMENFeatureFlags.shared.adaptiveGlassV2Enabled ? adaptiveState : .frosted
    }

    private var glassBackground: some View {
        Group {
            switch effectiveState {
            case .frostedStrong:
                Capsule()
                    .fill(Color(.systemBackground).opacity(colorScheme == .dark ? 0.08 : 0.60))
                    .amenProminentGlassEffect(in: Capsule())
            case .solidLight:
                Capsule()
                    .fill(Color(.systemBackground).opacity(0.97))
            case .transparent, .hidden:
                Capsule().fill(Color.clear)
            default:
                // .frosted, .collapsed — standard pill glass
                Capsule()
                    .fill(Color(.systemBackground).opacity(colorScheme == .dark ? 0.18 : 0.78))
                    .amenGlassEffect(in: Capsule())
            }
        }
        .overlay {
            Capsule()
                .strokeBorder(Color(.separator).opacity(0.18), lineWidth: 0.75)
                .allowsHitTesting(false)
        }
        .animation(
            AMENFeatureFlags.shared.adaptiveGlassV2Enabled
                ? Motion.adaptive(.spring(response: 0.32, dampingFraction: 0.80))
                : nil,
            value: effectiveState
        )
    }

    // MARK: - Tab item

    @ViewBuilder
    private func tabItem(_ tab: AMENTab) -> some View {
        let isSelected = selectedTab == tab.rawValue
        Button {
            if selectedTab == tab.rawValue {
                if tab == .home {
                    NotificationCenter.default.post(name: .homeTabTapped, object: nil)
                    HapticManager.impact(style: .light)
                }
                return
            }
            selectedTab = tab.rawValue
            clearBadge(for: tab)
        } label: {
            ZStack {
                // Active state: prominent glass tile that slides via matchedGeometryEffect
                if isSelected {
                    activePill
                        .matchedGeometryEffect(id: "activeTab", in: selectionNamespace)
                }

                // Icon + badge stack — icon-only; labels removed for the compact glass bar.
                // Tab names remain available to VoiceOver via the accessibilityLabel below.
                ZStack(alignment: .topTrailing) {
                    if tab == .profile, let url = profilePhotoURL, !url.isEmpty {
                        profileAvatar(url: url, isSelected: isSelected)
                    } else {
                        Image(systemName: isSelected ? tab.activeIcon : tab.inactiveIcon)
                            .font(.systemScaled(21, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(
                                isSelected
                                    ? AmenTheme.Colors.iconPrimary
                                    : AmenTheme.Colors.iconSecondary
                            )
                            .scaleEffect(isSelected ? 1.06 : 1.0)
                            .animation(
                                Motion.adaptive(.spring(response: 0.22, dampingFraction: 0.75)),
                                value: isSelected
                            )
                    }

                    let count = badges.count(for: tab)
                    if count > 0 {
                        BadgeView(count: count)
                            .offset(x: 9, y: -7)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityLabel(tab.label)
        .accessibilityHint(tab.accessibilityHint)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityValue({
            let count = badges.count(for: tab)
            return count > 0 ? "\(count) unread" : ""
        }())
    }

    // The glass tile that sits behind the active tab icon.
    // Matches the iOS 26 / Liquid Glass "button" aesthetic: material blur base,
    // directional top-left highlight, depth gradient on the opposite corner, fine edge stroke.
    private var activePill: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(colorScheme == .dark
                  ? AmenTheme.Colors.surfaceElevated
                  : AmenTheme.Colors.surfaceCard)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                // Top-left polish gloss
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(
                        colors: [
                            AmenTheme.Colors.glassHighlightTop.opacity(colorScheme == .dark ? 0.50 : 1.0),
                            AmenTheme.Colors.glassHighlightBottom.opacity(colorScheme == .dark ? 0.65 : 0.90),
                            Color.clear
                        ],
                        startPoint: .init(x: 0.1, y: 0),
                        endPoint: .init(x: 0.85, y: 0.55)
                    ))
            )
            .overlay(
                // Bottom-right depth shadow
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(
                        colors: [
                            Color.clear,
                            AmenTheme.Colors.glassDepth.opacity(colorScheme == .dark ? 0.75 : 0.35)
                        ],
                        startPoint: .init(x: 0.15, y: 0.5),
                        endPoint: .init(x: 1, y: 1)
                    ))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(AmenTheme.Colors.borderSoft, lineWidth: 0.5)
            )
            .shadow(color: AmenTheme.Colors.shadowCard.opacity(0.55), radius: 8, x: 0, y: 3)
            .shadow(color: AmenTheme.Colors.shadowCard.opacity(0.22), radius: 2, x: 0, y: 1)
            .frame(width: 46, height: 36)
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
    
    private func cameraButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "camera.fill")
                .font(.systemScaled(17, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(.regularMaterial)
                        .overlay(
                            Circle()
                                .stroke(AmenTheme.Colors.separatorSubtle, lineWidth: 0.5)
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Camera")
        .accessibilityHint("Opens Camera OS for photo and video capture")
    }

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
                    .font(.systemScaled(17, weight: .semibold))
                    .foregroundStyle(AmenTheme.Colors.iconPrimary)
            }
        }
        .buttonStyle(ComposeButtonStyle())
        .frame(width: 48, height: 48)
        .contentShape(Circle())
        .accessibilityLabel("Create post")
        .accessibilityHint("Opens the post composer")
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
        case .spaces:        badges.spaces = 0
        case .intelligence:  badges.intelligence = 0
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
            .background(Color(UIColor.systemRed))
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
