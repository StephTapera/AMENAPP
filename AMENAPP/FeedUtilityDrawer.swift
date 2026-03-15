//
//  FeedUtilityDrawer.swift
//  AMENAPP
//
//  Left-swipe utility panel for the main Feeds screen.
//  Reveals a "Community Layer" with quick feed modes, prayer circles,
//  discipleship groups, church families, and saved spaces.
//  AMEN-native design — Liquid Glass aesthetic, spring gesture with velocity snapping.
//

import SwiftUI
import Combine

// MARK: - Data Models

enum DrawerFeedMode: String, CaseIterable, Identifiable {
    case forYou      = "For You"
    case following   = "Following"
    case prayer      = "Prayer"
    case scripture   = "Scripture"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .forYou:    return "sparkles"
        case .following: return "person.2.fill"
        case .prayer:    return "hands.sparkles.fill"
        case .scripture: return "book.closed.fill"
        }
    }

    var subtitle: String {
        switch self {
        case .forYou:    return "Curated for your walk"
        case .following: return "People you follow"
        case .prayer:    return "Prayer & intercession"
        case .scripture: return "Word-centered posts"
        }
    }
}

enum DrawerCommunityRole: String {
    case member  = "Member"
    case leader  = "Leader"
    case admin   = "Admin"
}

struct DrawerCommunity: Identifiable {
    let id: String
    let name: String
    let subtitle: String
    let icon: String          // SF Symbol name
    let memberCount: Int
    let recentActivity: Int   // new posts since last visit
    let role: DrawerCommunityRole
    let isSuggested: Bool
}

// MARK: - Sample Data (replace with Firestore-backed viewmodel later)

private extension DrawerCommunity {
    static let sampleOwned: [DrawerCommunity] = [
        DrawerCommunity(id: "pc-1", name: "Morning Prayer Circle", subtitle: "Daily intercession at 6 AM",
                        icon: "hands.sparkles.fill", memberCount: 24, recentActivity: 3, role: .leader, isSuggested: false),
        DrawerCommunity(id: "bg-1", name: "Kingdom Builders", subtitle: "Men's discipleship & accountability",
                        icon: "figure.2.arms.open", memberCount: 12, recentActivity: 1, role: .admin, isSuggested: false)
    ]

    static let sampleJoined: [DrawerCommunity] = [
        DrawerCommunity(id: "cf-1", name: "New Life Church Family", subtitle: "Austin, TX",
                        icon: "building.columns.fill", memberCount: 320, recentActivity: 7, role: .member, isSuggested: false),
        DrawerCommunity(id: "bs-1", name: "Proverbs Study Group", subtitle: "Weekly deep dive",
                        icon: "book.fill", memberCount: 18, recentActivity: 4, role: .member, isSuggested: false),
        DrawerCommunity(id: "pc-2", name: "Women of the Word", subtitle: "Scripture & sisterhood",
                        icon: "heart.text.square.fill", memberCount: 45, recentActivity: 2, role: .member, isSuggested: false)
    ]

    static let sampleSuggested: [DrawerCommunity] = [
        DrawerCommunity(id: "sg-1", name: "Worship Leaders Network", subtitle: "3.2k members",
                        icon: "music.note.list", memberCount: 3200, recentActivity: 0, role: .member, isSuggested: true),
        DrawerCommunity(id: "sg-2", name: "New Believers Circle", subtitle: "First steps in faith",
                        icon: "flame.fill", memberCount: 890, recentActivity: 0, role: .member, isSuggested: true)
    ]
}

// MARK: - Drawer State

final class FeedDrawerState: ObservableObject {
    @Published var isOpen = false
    @Published var dragOffset: CGFloat = 0
    @Published var activeFeedMode: DrawerFeedMode = .forYou

    static let drawerWidth: CGFloat = UIScreen.main.bounds.width * 0.82

    /// Progress 0→1 as drawer opens (used for parallax / dimming)
    var progress: CGFloat {
        let width = Self.drawerWidth
        let base: CGFloat = isOpen ? width : 0
        let effective = base - dragOffset
        return max(0, min(1, effective / width))
    }

    func open(animated: Bool = true) {
        if animated {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                isOpen = true
                dragOffset = 0
            }
        } else {
            isOpen = true
            dragOffset = 0
        }
    }

    func close(animated: Bool = true) {
        if animated {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                isOpen = false
                dragOffset = 0
            }
        } else {
            isOpen = false
            dragOffset = 0
        }
    }
}

// MARK: - Main Drawer View

struct FeedUtilityDrawerView: View {
    @ObservedObject var state: FeedDrawerState
    let onClose: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                drawerHeader
                    .padding(.top, 20)
                    .padding(.bottom, 8)

                feedModesSection
                    .padding(.bottom, 4)

                Divider()
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .opacity(0.3)

                if !DrawerCommunity.sampleOwned.isEmpty {
                    communitySection(
                        title: "Led by You",
                        icon: "crown.fill",
                        communities: DrawerCommunity.sampleOwned
                    )
                    .padding(.bottom, 4)
                }

                if !DrawerCommunity.sampleJoined.isEmpty {
                    communitySection(
                        title: "Your Communities",
                        icon: "person.3.fill",
                        communities: DrawerCommunity.sampleJoined
                    )
                    .padding(.bottom, 4)
                }

                if !DrawerCommunity.sampleSuggested.isEmpty {
                    suggestedSection
                        .padding(.bottom, 4)
                }

                Spacer(minLength: 40)
            }
        }
        .frame(width: FeedDrawerState.drawerWidth)
        .background(drawerBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.18), radius: 28, x: -4, y: 0)
    }

    // MARK: - Header

    private var drawerHeader: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Your Feed")
                    .font(.custom("OpenSans-Bold", size: 20))
                    .foregroundStyle(.primary)
                Text("Communities & spaces")
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Feed Modes

    private var feedModesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Feed Mode", icon: "slider.horizontal.3")

            VStack(spacing: 0) {
                ForEach(DrawerFeedMode.allCases) { mode in
                    feedModeRow(mode)
                    if mode != DrawerFeedMode.allCases.last {
                        Divider()
                            .padding(.leading, 52)
                            .opacity(0.25)
                    }
                }
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 16)
        }
    }

    private func feedModeRow(_ mode: DrawerFeedMode) -> some View {
        let isActive = state.activeFeedMode == mode
        return Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                state.activeFeedMode = mode
            }
            HapticManager.impact(style: .light)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: mode.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isActive ? Color.white : Color.primary)
                    .frame(width: 32, height: 32)
                    .background(isActive ? Color.accentColor : Color.clear, in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.rawValue)
                        .font(.custom("OpenSans-SemiBold", size: 14))
                        .foregroundStyle(.primary)
                    Text(mode.subtitle)
                        .font(.custom("OpenSans-Regular", size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isActive {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Community Section

    private func communitySection(title: String, icon: String, communities: [DrawerCommunity]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(title, icon: icon)

            VStack(spacing: 0) {
                ForEach(communities) { community in
                    communityRow(community)
                    if community.id != communities.last?.id {
                        Divider()
                            .padding(.leading, 56)
                            .opacity(0.25)
                    }
                }
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 16)
        }
    }

    private func communityRow(_ community: DrawerCommunity) -> some View {
        Button {
            HapticManager.impact(style: .light)
            // TODO: Navigate to community feed
        } label: {
            HStack(spacing: 12) {
                // Community icon circle
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 36, height: 36)
                    Image(systemName: community.icon)
                        .font(.system(size: 15))
                        .foregroundStyle(.primary.opacity(0.8))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(community.name)
                        .font(.custom("OpenSans-SemiBold", size: 13))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(community.subtitle)
                        .font(.custom("OpenSans-Regular", size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // Activity badge
                if community.recentActivity > 0 {
                    Text("\(community.recentActivity)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor, in: Capsule())
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary.opacity(0.5))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Suggested Section

    private var suggestedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Suggested Spaces", icon: "sparkle")

            VStack(spacing: 0) {
                ForEach(DrawerCommunity.sampleSuggested) { community in
                    suggestedRow(community)
                    if community.id != DrawerCommunity.sampleSuggested.last?.id {
                        Divider()
                            .padding(.leading, 56)
                            .opacity(0.25)
                    }
                }
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 16)
        }
    }

    private func suggestedRow(_ community: DrawerCommunity) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 36, height: 36)
                Image(systemName: community.icon)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(community.name)
                    .font(.custom("OpenSans-SemiBold", size: 13))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(community.subtitle)
                    .font(.custom("OpenSans-Regular", size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                HapticManager.impact(style: .medium)
                // TODO: Join community
            } label: {
                Text("Join")
                    .font(.custom("OpenSans-SemiBold", size: 12))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Helpers

    private func sectionLabel(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.custom("OpenSans-SemiBold", size: 12))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
    }

    private var drawerBackground: some View {
        ZStack {
            Color(UIColor.systemBackground).opacity(0.7)
            Rectangle().fill(.regularMaterial)
        }
    }
}

// MARK: - Gesture Wrapper

/// Wraps any content view and adds a left-swipe gesture that reveals
/// `FeedUtilityDrawerView` from the trailing edge with parallax + dim.
struct FeedDrawerGestureWrapper<Content: View>: View {
    @StateObject private var drawerState = FeedDrawerState()

    // Minimum horizontal velocity (pts/s) to trigger open/close snap
    private let velocityThreshold: CGFloat = 400
    // Minimum drag distance before direction is decided
    private let horizontalDecisionThreshold: CGFloat = 12
    // Max vertical movement while still counting as a horizontal gesture
    private let verticalMaxForHorizontal: CGFloat = 20

    @State private var isHorizontalGesture: Bool? = nil  // nil = not yet determined

    // Observe the active tab so we can force-close the drawer when the user
    // switches tabs while a swipe gesture is in progress. Without this, the
    // interactiveSpring animation gets interrupted mid-flight, leaving the
    // main content permanently offset (the "half-screen white split" bug).
    @Environment(\.mainTabSelection) private var mainTabSelection

    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        let drawerWidth = FeedDrawerState.drawerWidth
        let progress = drawerState.progress

        ZStack(alignment: .trailing) {
            // Main content with parallax shift
            content()
                .offset(x: -progress * 28)
                .scaleEffect(1.0 - progress * 0.02)
                .animation(.interactiveSpring(response: 0.35, dampingFraction: 0.85), value: progress)
                .allowsHitTesting(!drawerState.isOpen)

            // Dim overlay
            if progress > 0 {
                Color.black
                    .opacity(progress * 0.3)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            // Drawer panel
            FeedUtilityDrawerView(state: drawerState) {
                drawerState.close()
            }
            .offset(x: drawerState.isOpen
                    ? max(0, drawerState.dragOffset)
                    : drawerWidth - max(0, -drawerState.dragOffset)
            )
            .ignoresSafeArea(edges: .vertical)

            // Tap-outside-to-close overlay
            if drawerState.isOpen {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { drawerState.close() }
                    .padding(.trailing, drawerWidth)
            }
        }
        .gesture(
            DragGesture(minimumDistance: 10, coordinateSpace: .local)
                .onChanged { value in
                    let dx = value.translation.width
                    let dy = value.translation.height

                    // Determine gesture direction once per drag
                    if isHorizontalGesture == nil {
                        if abs(dx) > horizontalDecisionThreshold {
                            isHorizontalGesture = abs(dx) > abs(dy) * 1.5
                        } else if abs(dy) > verticalMaxForHorizontal {
                            isHorizontalGesture = false
                        }
                        return
                    }

                    guard isHorizontalGesture == true else { return }

                    if drawerState.isOpen {
                        // Drawer open: only allow dragging right (closing)
                        drawerState.dragOffset = max(0, dx)
                    } else if dx < 0 {
                        // Drawer closed, dragging left: open drawer
                        drawerState.dragOffset = min(0, dx)
                    }
                }
                .onEnded { value in
                    defer {
                        isHorizontalGesture = nil
                        drawerState.dragOffset = 0
                    }

                    guard isHorizontalGesture == true else { return }

                    let velocity = value.velocity.width

                    if drawerState.isOpen {
                        let shouldClose = drawerState.dragOffset > drawerWidth * 0.35 || velocity > velocityThreshold
                        if shouldClose { drawerState.close() } else { drawerState.open() }
                    } else if value.translation.width < 0 {
                        // Swiped left → open drawer
                        let dragLeft = -value.translation.width
                        let shouldOpen = dragLeft > drawerWidth * 0.25 || velocity < -velocityThreshold
                        if shouldOpen { drawerState.open() }
                    }
                }
        )
        // Force-reset drawer state instantly when the user switches tabs.
        // This prevents the interactiveSpring from being interrupted mid-flight,
        // which would leave content stuck at a non-zero offset (half-screen white split).
        .onChange(of: mainTabSelection.wrappedValue) { _, _ in
            guard drawerState.isOpen || drawerState.dragOffset != 0 else { return }
            isHorizontalGesture = nil
            // Disable animations so the reset is immediate — no spring fighting the tab transition
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                drawerState.isOpen = false
                drawerState.dragOffset = 0
            }
        }
        .environment(\.feedDrawerState, drawerState)
    }
}

// MARK: - Environment Key

private struct FeedDrawerStateKey: EnvironmentKey {
    static let defaultValue: FeedDrawerState? = nil
}

extension EnvironmentValues {
    var feedDrawerState: FeedDrawerState? {
        get { self[FeedDrawerStateKey.self] }
        set { self[FeedDrawerStateKey.self] = newValue }
    }
}
