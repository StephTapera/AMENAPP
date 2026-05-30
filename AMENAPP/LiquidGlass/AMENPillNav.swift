// AMENPillNav.swift
// AMEN App — Floating glass center-capsule tab bar.
//
// Drop-in replacement for the center section of AMENTabBar when the
// liquidGlassPillNav feature flag is ON.  Orbs (profile / compose)
// remain in AMENTabBar and flank this view unchanged.
//
// Design: icon-only, amenGold active tint, light frosted glass surface.
// iOS 26+: native glassEffect.  iOS 17-25: ultraThinMaterial fallback.

import SwiftUI

// MARK: - AMENPillNav

struct AMENPillNav: View {
    let tabs: [AMENTab]
    @Binding var selectedTab: Int
    @Binding var badges: AMENBadgeCounts
    var onTabTap: (AMENTab) -> Void
    var barHeight: CGFloat
    var isMinimized: Bool

    @Namespace private var pillNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2) {
            ForEach(tabs, id: \.rawValue) { tab in
                pillButton(tab).frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 6)
        .frame(height: barHeight)
        .frame(maxWidth: .infinity)
        .background {
            LiquidGlassTabBarBackground(isCompressed: isMinimized)
                .clipShape(Capsule(style: .continuous))
        }
    }

    // MARK: - Per-tab button

    @ViewBuilder
    private func pillButton(_ tab: AMENTab) -> some View {
        // Discover (tab 1) is a sub-destination of Home — keep Home highlighted while on it.
        let visibleTab = selectedTab == AMENTab.search.rawValue ? AMENTab.home.rawValue : selectedTab
        let isSelected = visibleTab == tab.rawValue
        let badgeCount = badges.count(for: tab)

        Button { onTabTap(tab) } label: {
            ZStack(alignment: .topTrailing) {
                iconCell(tab: tab, isSelected: isSelected)
                if badgeCount > 0 {
                    AMENPillNavBadge(count: badgeCount).offset(x: 8, y: -8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(AMENPillNavButtonStyle(reduceMotion: reduceMotion))
        .accessibilityLabel(tab.accessibilityLabel(badgeCount: badgeCount))
        .accessibilityHint("Double tap to open \(tab.accessibilityName)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func iconCell(tab: AMENTab, isSelected: Bool) -> some View {
        Image(systemName: isSelected ? tab.activeIcon : tab.inactiveIcon)
            .font(.system(size: 20, weight: .semibold))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(isSelected ? Color.amenGold : Color.primary.opacity(0.55))
            .frame(width: 26, height: 24)
            .padding(.horizontal, 5)
            .padding(.vertical, isMinimized ? 5 : 9)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                if isSelected {
                    LiquidGlassActiveTabCapsule()
                        .matchedGeometryEffect(id: "amen_pillnav_pill", in: pillNamespace)
                }
            }
            .contentShape(Capsule(style: .continuous))
            // Selection bounce
            .symbolEffect(.bounce, options: .speed(1.6), value: isSelected)
    }
}

// MARK: - Badge

private struct AMENPillNavBadge: View {
    let count: Int
    private var text: String { count > 9 ? "9+" : "\(count)" }

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, count > 9 ? 4 : 0)
            .frame(minWidth: 16, minHeight: 16)
            .background(AmenTheme.Colors.statusError)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Color(.systemBackground).opacity(0.9), lineWidth: 1.2))
    }
}

// MARK: - Button Style

private struct AMENPillNavButtonStyle: ButtonStyle {
    let reduceMotion: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? AmenGlassBehavior.pressedScale : 1.0)
            .opacity(configuration.isPressed ? 0.88 : 1.0)
            .animation(reduceMotion ? nil : Motion.liquidSpring, value: configuration.isPressed)
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var tab: Int = 0
    @Previewable @State var badges = AMENBadgeCounts(messages: 3, notifications: 1)
    let tabs: [AMENTab] = [.home, .messages, .library, .notifications]

    ZStack {
        LinearGradient(
            colors: [Color(red: 0.9, green: 0.85, blue: 0.75), Color(red: 0.97, green: 0.94, blue: 0.88)],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()

        VStack {
            Spacer()
            HStack(spacing: 10) {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 54, height: 54)
                AMENPillNav(
                    tabs: tabs,
                    selectedTab: $tab,
                    badges: $badges,
                    onTabTap: { tab = $0.rawValue },
                    barHeight: 54,
                    isMinimized: false
                )
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 54, height: 54)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 20)
        }
    }
}
