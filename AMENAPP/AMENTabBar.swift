//
//  AMENTabBar.swift
//  AMENAPP
//
//  Standard liquid glass tab bar with icons and compose button.
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

    private let haptic = UIImpactFeedbackGenerator(style: .medium)
    private let containerH: CGFloat = 80
    private let tabH: CGFloat = 62
    private let pillInset: CGFloat = 9
    private let iconSize: CGFloat = 20
    private let labelSize: CGFloat = 10.5

    @State private var pillStretch: CGFloat = 1.0
    @State private var pillStretchTask: Task<Void, Never>? = nil
    @State private var highlightPhase: CGFloat = -0.6

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            tabCapsule
            ComposeButton(onCompose: onCompose)
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
        .offset(y: isMinimized ? 18 : 0)
        .scaleEffect(isMinimized ? 0.94 : 1.0, anchor: .bottom)
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: isMinimized)
        .onAppear { haptic.prepare() }
        .onAppear {
            withAnimation(.linear(duration: 3.2).repeatForever(autoreverses: true)) {
                highlightPhase = 0.6
            }
        }
        .onChange(of: selectedTab) { _, _ in
            triggerPillStretch()
        }
    }

    // MARK: Tab capsule

    private var tabCapsule: some View {
        GeometryReader { geo in
            let W = geo.size.width
            let n = CGFloat(AMENTab.allCases.count)
            let tabW = W / n
            let safeIndex = min(max(selectedTab, 0), AMENTab.allCases.count - 1)

            ZStack {
                // Glass capsule shell
                glassShell
                    .frame(height: containerH)

                // Active pill
                Capsule()
                    .fill(Color.black.opacity(0.06))
                    .frame(width: tabW, height: containerH - (pillInset * 2))
                    .overlay(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    stops: [
                                        .init(color: .white.opacity(0.35), location: 0.0),
                                        .init(color: .white.opacity(0.08), location: 1.0)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .blendMode(.screen)
                    )
                    .overlay(
                        GeometryReader { pillGeo in
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        stops: [
                                            .init(color: .white.opacity(0.20), location: 0.0),
                                            .init(color: .white.opacity(0.02), location: 1.0)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(width: pillGeo.size.width * 0.6)
                                .offset(x: pillGeo.size.width * highlightPhase)
                                .opacity(0.35)
                        }
                    )
                    .shadow(color: .black.opacity(0.10), radius: 16, x: 0, y: 8)
                    .scaleEffect(x: pillStretch, y: 1.0, anchor: .center)
                    .offset(x: (-W / 2) + (tabW / 2) + (tabW * CGFloat(safeIndex)))
                    .animation(.spring(response: 0.48, dampingFraction: 0.78), value: selectedTab)
                    .allowsHitTesting(false)

                // Icon + label grid
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: AMENTab.allCases.count),
                    spacing: 0
                ) {
                    ForEach(AMENTab.allCases, id: \.rawValue) { tab in
                        AMENTabItemView(
                            tab: tab,
                            isSelected: selectedTab == tab.rawValue,
                            badgeCount: badges.count(for: tab),
                            profilePhotoURL: profilePhotoURL,
                            iconSize: iconSize,
                            labelSize: labelSize,
                            tabHeight: tabH
                        ) {
                            switchTo(tab)
                        }
                    }
                }
                .frame(height: tabH)
            }
            .frame(width: W, height: containerH)
        }
        .frame(height: containerH)
        .shadow(color: .black.opacity(0.10), radius: 36, x: 0, y: 14)
    }

    // MARK: - Glass capsule shell

    private var glassShell: some View {
        ZStack {
            // Base glass material - more visible
            Capsule()
                .fill(.ultraThinMaterial)

            // Glass gradient overlay
            Capsule()
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.90), location: 0.0),
                            .init(color: .white.opacity(0.70), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .allowsHitTesting(false)

            // Inner light diffusion
            Capsule()
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.40), location: 0.0),
                            .init(color: .white.opacity(0.00), location: 0.6)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .blendMode(.screen)
                .allowsHitTesting(false)

            // Subtle border
            Capsule()
                .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.8)
                .allowsHitTesting(false)

            // Specular edge
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.65), location: 0.0),
                            .init(color: .white.opacity(0.22), location: 0.55),
                            .init(color: .white.opacity(0.10), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
                .allowsHitTesting(false)
                .animation(.spring(response: 0.42, dampingFraction: 0.78), value: isMinimized)
        }
    }

    // MARK: - Tab switch

    private func switchTo(_ tab: AMENTab) {
        guard selectedTab != tab.rawValue else { return }
        haptic.impactOccurred()
        withAnimation(.spring(response: 0.46, dampingFraction: 0.76)) {
            selectedTab = tab.rawValue
        }
        withAnimation(.easeOut(duration: 0.2)) {
            clearBadge(for: tab)
        }
    }

    private func triggerPillStretch() {
        pillStretchTask?.cancel()
        pillStretchTask = Task { @MainActor in
            withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                pillStretch = 1.04
            }
            try? await Task.sleep(nanoseconds: 120_000_000)
            withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                pillStretch = 1.0
            }
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
        }
    }
}

// MARK: - Tab Item

private struct AMENTabItemView: View {
    let tab: AMENTab
    let isSelected: Bool
    let badgeCount: Int
    let profilePhotoURL: String?
    let iconSize: CGFloat
    let labelSize: CGFloat
    let tabHeight: CGFloat
    let action: () -> Void

    @State private var pressScale: CGFloat = 1.0
    @State private var pressTask: Task<Void, Never>? = nil

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 3) {
                    tabIcon
                        .opacity(isSelected ? 1.0 : 0.5)
                        .offset(y: isSelected ? -1.5 : 0)
                    Text(tab.label)
                        .font(.system(size: labelSize, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(isSelected ? 0.85 : 0.55))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if badgeCount > 0 {
                    BadgeView(count: badgeCount)
                        .offset(x: 8, y: 4)
                }
            }
            .frame(height: tabHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleEffect(pressScale)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    pressTask?.cancel()
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.78)) {
                        pressScale = 0.96
                    }
                }
                .onEnded { _ in
                    pressTask?.cancel()
                    pressTask = Task { @MainActor in
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.70)) {
                            pressScale = 1.02
                        }
                        try? await Task.sleep(nanoseconds: 80_000_000)
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.86)) {
                            pressScale = 1.0
                        }
                    }
                }
        )
        .animation(.spring(response: 0.30, dampingFraction: 0.80), value: isSelected)
        .accessibilityLabel(tab.label)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private var tabIcon: some View {
        if tab == .profile, let url = profilePhotoURL, !url.isEmpty {
            AsyncImage(url: URL(string: url)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: iconSize, height: iconSize)
                        .clipShape(Circle())
                        .overlay(
                            Circle().strokeBorder(
                                Color.black.opacity(isSelected ? 0.90 : 0.30),
                                lineWidth: isSelected ? 1.5 : 1.0
                            )
                        )
                default:
                    systemIcon
                }
            }
        } else {
            systemIcon
        }
    }

    private var systemIcon: some View {
        Image(systemName: isSelected ? tab.activeIcon : tab.inactiveIcon)
            .font(.system(size: iconSize, weight: .semibold))
            .foregroundStyle(Color.black.opacity(isSelected ? 0.90 : 0.55))
    }
}

// MARK: - Compose Button

private struct ComposeButton: View {
    var onCompose: () -> Void

    var body: some View {
        Button(action: onCompose) {
            ZStack {
                // Outer glass circle — matches capsule material
                Circle().fill(.thinMaterial)
                Circle()
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.52), location: 0.0),
                                .init(color: .white.opacity(0.24), location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .allowsHitTesting(false)
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.92), location: 0.0),
                                .init(color: .white.opacity(0.22), location: 0.5),
                                .init(color: .white.opacity(0.10), location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                    .allowsHitTesting(false)

                // Inner bright circle — same material language as the raised bubble
                ZStack {
                    Circle().fill(.regularMaterial)
                    Circle()
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: .white.opacity(0.90), location: 0.0),
                                    .init(color: .white.opacity(0.52), location: 1.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    Circle()
                        .strokeBorder(.white.opacity(0.95), lineWidth: 1)

                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.black)
                }
                .frame(width: 46, height: 46)
            }
            .frame(width: 62, height: 62)
            .shadow(color: .black.opacity(0.09), radius: 20, x: 0, y: 6)
            .shadow(color: .black.opacity(0.04), radius: 5,  x: 0, y: 2)
        }
        .buttonStyle(ComposeButtonStyle())
        .accessibilityLabel("Create post")
    }
}

// MARK: - Badge View

private struct BadgeView: View {
    let count: Int
    private let notifyHaptic = UINotificationFeedbackGenerator()
    @State private var previousCount: Int = 0

    private var displayText: String { count >= 100 ? "99+" : "\(count)" }
    private var isPill: Bool { count >= 100 }

    var body: some View {
        Text(displayText)
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, isPill ? 6 : 0)
            .frame(
                minWidth:  count < 10 ? 20 : count < 100 ? 22 : 0,
                minHeight: 20
            )
            .background(Color(red: 0.937, green: 0.267, blue: 0.267))
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.92), lineWidth: 2))
            .shadow(
                color: Color(red: 0.937, green: 0.267, blue: 0.267).opacity(0.28),
                radius: 8, x: 0, y: 3
            )
            .onAppear { previousCount = count }
            .onChange(of: count) { old, new in
                if new > old { notifyHaptic.notificationOccurred(.success) }
                previousCount = new
            }
    }
}

// MARK: - Compose Button Press Style

private struct ComposeButtonStyle: ButtonStyle {
    private let haptic = UIImpactFeedbackGenerator(style: .medium)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.90 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.55), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed { haptic.impactOccurred() }
            }
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

final class AMENTabBarScrollBridge: ObservableObject {
    static let shared = AMENTabBarScrollBridge()
    @Published var isMinimized: Bool = false

    private let scrollHaptic = UIImpactFeedbackGenerator(style: .soft)

    func minimize() {
        guard !isMinimized else { return }
        scrollHaptic.impactOccurred(intensity: 0.35)
        withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
            isMinimized = true
        }
    }

    func expand() {
        guard isMinimized else { return }
        scrollHaptic.impactOccurred(intensity: 0.25)
        withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
            isMinimized = false
        }
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
    @Previewable @State var badges = AMENBadgeCounts(messages: 3, notifications: 24, profile: 1)

    ZStack {
        // Simulated light content behind the bar
        LinearGradient(
            colors: [Color(UIColor.systemGroupedBackground), Color(UIColor.secondarySystemGroupedBackground)],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()

        VStack {
            Spacer()
            AMENTabBar(
                selectedTab: $tab,
                badges: $badges,
                onCompose: {},
                profilePhotoURL: nil
            )
            .padding(.bottom, 8)
        }
        .ignoresSafeArea(edges: .bottom)
    }
}
