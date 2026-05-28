// SpatialHomeView.swift
// AMENAPP
//
// Feature-flagged replacement for the flat home feed.
// Gated by AMENFeatureFlags.shared.spatialHomeEnabled.
// Renders nothing when the flag is off — the caller is responsible
// for showing the regular HomeView in that case.
//
// Design language: Liquid Glass
//   - White background, black primary text
//   - .ultraThinMaterial for floating chrome only
//   - No glass-on-glass stacking
//   - SF Symbols throughout

import SwiftUI
import Combine

// MARK: - SpatialHomeView

struct SpatialHomeView: View {

    // MARK: Dependencies

    @ObservedObject private var flags = AMENFeatureFlags.shared

    // MARK: Environment

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: View State

    @StateObject private var viewModel = SpatialHomeViewModel()
    @State private var contextRailVisible: Bool = false
    @State private var scrollVelocityFast: Bool = false

    // MARK: Body

    var body: some View {
        // Hard gate: if the flag is off this view renders nothing.
        // The parent is responsible for showing regular HomeView instead.
        if flags.spatialHomeEnabled {
            ZStack(alignment: .bottom) {
                // Layer 1 — white canvas
                Color.white
                    .ignoresSafeArea()

                // Layer 2 — primary scrollable feed
                PrimaryFocusPlane(
                    viewModel: viewModel,
                    scrollVelocityFast: $scrollVelocityFast
                )

                // Layer 3 — slide-in context rail (flag-gated)
                if flags.spatialContextRailEnabled {
                    SpatialContextRail(
                        isVisible: $contextRailVisible,
                        reduceMotion: reduceMotion
                    )
                }

                // Layer 4 — ambient session status bar (sits below nav bar in safe area)
                if flags.healthyImmersiveMediaEnabled {
                    VStack {
                        AmbientStatusBar(
                            session: viewModel.activeSession,
                            scrollVelocityFast: scrollVelocityFast
                        )
                        .padding(.top, 8)
                        Spacer()
                    }
                    .allowsHitTesting(false)  // passthrough — status bar is display-only
                }

                // Layer 5 — floating composer dock
                FloatingComposerDock(
                    onContextRailToggle: {
                        withAnimation(reduceMotion ? .none : .spring(response: 0.35, dampingFraction: 0.8)) {
                            contextRailVisible.toggle()
                        }
                        dlog("[SpatialHomeView] Context rail toggled: \(contextRailVisible)")
                    },
                    reduceMotion: reduceMotion
                )
                .padding(.bottom, 12)
            }
            .navigationTitle("AMEN")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        NotificationCenter.default.post(name: .openCreatePost, object: nil)
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .foregroundColor(.primary)
                    }
                    .accessibilityLabel("Create post")
                }
            }
        }
    }
}

// MARK: - SpatialHomeViewModel

@MainActor
final class SpatialHomeViewModel: ObservableObject {

    // Feed data — backed by PostsManager's live Firestore listener
    @Published var feedPosts: [Post] = []
    @Published var activeSession: AmenMediaSession? = nil
    @Published var isLoadingFeed: Bool = true

    private var cancellables = Set<AnyCancellable>()

    init() {
        feedPosts = PostsManager.shared.allPosts
        isLoadingFeed = feedPosts.isEmpty

        PostsManager.shared.$allPosts
            .receive(on: DispatchQueue.main)
            .sink { [weak self] posts in
                guard let self else { return }
                self.feedPosts = posts
                self.isLoadingFeed = false
                dlog("[SpatialHomeViewModel] Feed updated: \(posts.count) posts")
            }
            .store(in: &cancellables)
    }

    func refresh() {
        dlog("[SpatialHomeViewModel] Feed refresh requested")
        AMENAnalyticsService.shared.track(.feedSessionStarted)
    }
}

// MARK: - PrimaryFocusPlane

/// The main scrollable content layer — renders real PostCards from PostsManager.
private struct PrimaryFocusPlane: View {

    @ObservedObject var viewModel: SpatialHomeViewModel
    @Binding var scrollVelocityFast: Bool

    @State private var lastScrollOffset: CGFloat = 0

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            // Scroll offset tracker
            GeometryReader { proxy in
                Color.clear
                    .preference(
                        key: SpatialScrollOffsetPreferenceKey.self,
                        value: proxy.frame(in: .named("spatialFeedScroll")).minY
                    )
            }
            .frame(height: 0)

            LazyVStack(spacing: 0) {
                if viewModel.isLoadingFeed {
                    ProgressView()
                        .padding(.vertical, 48)
                        .accessibilityLabel("Loading feed")
                } else if viewModel.feedPosts.isEmpty {
                    EmptyFeedView()
                        .padding(.top, 32)
                } else {
                    ForEach(viewModel.feedPosts) { post in
                        PostCard(post: post)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                    }
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 96) // clear the FloatingComposerDock
        }
        .coordinateSpace(name: "spatialFeedScroll")
        .onPreferenceChange(SpatialScrollOffsetPreferenceKey.self) { @MainActor value in
            let delta = abs(value - lastScrollOffset)
            scrollVelocityFast = delta > 24
            lastScrollOffset = value
        }
        .background(Color.white)
        .refreshable {
            await MainActor.run { viewModel.refresh() }
        }
    }
}

private struct SpatialScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - SpatialPostPlaceholderCard

/// Placeholder card used until PostCard is wired up with a real Post object.
/// Replace the body with `PostCard(post: realPost)` once the feed data layer
/// supplies real Post values.
struct SpatialPostPlaceholderCard: View {

    let postId: String
    let index: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Author row
            HStack(spacing: 10) {
                Circle()
                    .fill(Color.black.opacity(0.08))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Text(String(UnicodeScalar(65 + (index % 26))!))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.black.opacity(0.6))
                    )
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Community Member")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.black)
                    Text("Just now")
                        .font(.system(size: 12))
                        .foregroundColor(.black.opacity(0.45))
                }

                Spacer()

                Image(systemName: "ellipsis")
                    .font(.system(size: 15))
                    .foregroundColor(.black.opacity(0.4))
                    .accessibilityLabel("More options")
            }

            // Content body
            Text("This is a placeholder post card for spatial feed item \(index + 1). In production this will render a real PostCard(post:) with full community content.")
                .font(.system(size: 15))
                .foregroundColor(.black.opacity(0.85))
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)

            // Action row
            HStack(spacing: 20) {
                PlaceholderActionButton(icon: "hands.sparkles.fill", label: "Amen", accessLabel: "Say Amen") {
                    dlog("[SpatialPostPlaceholderCard] Amen tapped on postId: \(postId)")
                    AMENAnalyticsService.shared.track(.feedMeaningfulInteraction(type: "amen"))
                }
                PlaceholderActionButton(icon: "bubble.left", label: "Comment", accessLabel: "Comment on post") {
                    dlog("[SpatialPostPlaceholderCard] Comment tapped on postId: \(postId)")
                    AMENAnalyticsService.shared.track(.feedMeaningfulInteraction(type: "comment"))
                }
                PlaceholderActionButton(icon: "bookmark", label: "Save", accessLabel: "Save post") {
                    dlog("[SpatialPostPlaceholderCard] Save tapped on postId: \(postId)")
                    AMENAnalyticsService.shared.track(.feedMeaningfulInteraction(type: "save"))
                }
                Spacer()
                PlaceholderActionButton(icon: "square.and.arrow.up", label: "Share", accessLabel: "Share post") {
                    dlog("[SpatialPostPlaceholderCard] Share tapped on postId: \(postId)")
                    AMENAnalyticsService.shared.track(.feedMeaningfulInteraction(type: "share"))
                }
            }
        }
        .padding(14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 2)
        .accessibilityElement(children: .contain)
    }
}

private struct PlaceholderActionButton: View {
    let icon: String
    let label: String
    let accessLabel: String
    let action: () -> Void

    @State private var isPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            action()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                Text(label)
                    .font(.system(size: 12))
            }
            .foregroundColor(.black.opacity(0.55))
        }
        .scaleEffect(isPressed && !reduceMotion ? 0.88 : 1.0)
        .animation(reduceMotion ? .none : .spring(response: 0.2, dampingFraction: 0.6), value: isPressed)
        ._onButtonGesture(
            pressing: { pressing in isPressed = pressing },
            perform: {}
        )
        .accessibilityLabel(accessLabel)
    }
}

// MARK: - SpatialContextRail

/// Slide-in panel from the trailing edge showing related content context.
/// Visible when `isVisible` is true; hidden by default.
private struct SpatialContextRail: View {

    @Binding var isVisible: Bool
    let reduceMotion: Bool

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                Spacer()

                if isVisible {
                    VStack(alignment: .leading, spacing: 0) {
                        // Rail header
                        HStack {
                            Text("Context")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.black)
                            Spacer()
                            Button {
                                let generator = UIImpactFeedbackGenerator(style: .light)
                                generator.impactOccurred()
                                withAnimation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.8)) {
                                    isVisible = false
                                }
                                dlog("[SpatialContextRail] Dismissed")
                                AMENAnalyticsService.shared.track(.feedMeaningfulInteraction(type: "context_rail_dismiss"))
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(.black.opacity(0.35))
                            }
                            .accessibilityLabel("Close context rail")
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 12)

                        Divider()
                            .background(Color.black.opacity(0.08))

                        // Related content chips
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                ContextRailSection(
                                    title: "Related Topics",
                                    chips: [
                                        ("tag", "Faith"),
                                        ("tag", "Community"),
                                        ("tag", "Worship"),
                                    ]
                                )

                                ContextRailSection(
                                    title: "From This Community",
                                    chips: [
                                        ("person.2", "12 members active"),
                                        ("bell", "Service at 10am"),
                                    ]
                                )

                                ContextRailSection(
                                    title: "Trust Signals",
                                    chips: [
                                        ("checkmark.seal.fill", "Verified Creator"),
                                        ("building.columns", "Church Affiliated"),
                                    ]
                                )
                            }
                            .padding(16)
                        }
                    }
                    .frame(width: min(geo.size.width * 0.72, 280))
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: Color.black.opacity(0.12), radius: 16, x: -4, y: 0)
                    .padding(.trailing, 8)
                    .padding(.vertical, 60)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .move(edge: .trailing).combined(with: .opacity)
                    )
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Content context panel")
                }
            }
        }
        .ignoresSafeArea(edges: .vertical)
        .allowsHitTesting(isVisible)
        .animation(reduceMotion ? .none : .spring(response: 0.35, dampingFraction: 0.82), value: isVisible)
    }
}

private struct ContextRailSection: View {
    let title: String
    let chips: [(String, String)] // (SF Symbol, label)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.black.opacity(0.4))
                .textCase(.uppercase)
                .kerning(0.4)

            SpatialFlowLayout(spacing: 6) {
                ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in
                    HStack(spacing: 4) {
                        Image(systemName: chip.0)
                            .font(.system(size: 11))
                        Text(chip.1)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.black.opacity(0.75))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.06))
                    .clipShape(Capsule())
                }
            }
        }
    }
}

// MARK: - AmbientStatusBar

/// Floating capsule at the top of the feed that shows current session info.
/// Non-interactive. Fades out when the user is scrolling fast.
private struct AmbientStatusBar: View {

    let session: AmenMediaSession?
    let scrollVelocityFast: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var sessionLabel: String {
        guard let session = session, session.finiteQueue else { return "" }
        let current = min(session.currentIndex + 1, session.maxItems)
        return "Session: \(current) of \(session.maxItems)"
    }

    private var shouldShow: Bool {
        guard let session = session else { return false }
        return session.finiteQueue && !sessionLabel.isEmpty
    }

    var body: some View {
        if shouldShow {
            HStack(spacing: 6) {
                Image(systemName: "infinity.circle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.black.opacity(0.6))
                    .accessibilityHidden(true)
                Text(sessionLabel)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.black.opacity(0.75))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 2)
            .opacity(scrollVelocityFast ? 0 : 1)
            .animation(
                reduceMotion ? .none : .easeInOut(duration: scrollVelocityFast ? 0.15 : 0.35),
                value: scrollVelocityFast
            )
            .padding(.top, 4)
            .accessibilityLabel(sessionLabel)
            .accessibilityAddTraits(.isStaticText)
        }
    }
}

// MARK: - FloatingComposerDock

/// Floating action dock anchored above the bottom safe area.
/// Capsule shape with .ultraThinMaterial fill and four composer actions.
private struct FloatingComposerDock: View {

    let onContextRailToggle: () -> Void
    let reduceMotion: Bool

    var body: some View {
        HStack(spacing: 0) {
            DockButton(
                icon: "sparkles",
                label: "Create",
                reduceMotion: reduceMotion
            ) {
                dlog("[FloatingComposerDock] Create tapped")
                AMENAnalyticsService.shared.track(.feedMeaningfulInteraction(type: "dock_create"))
                NotificationCenter.default.post(name: .openCreatePost, object: nil)
            }

            DockButton(
                icon: "camera.fill",
                label: "Camera",
                reduceMotion: reduceMotion
            ) {
                dlog("[FloatingComposerDock] Camera tapped")
                AMENAnalyticsService.shared.track(.feedMeaningfulInteraction(type: "dock_camera"))
                NotificationCenter.default.post(name: .openCreatePost, object: nil)
            }

            DockButton(
                icon: "hands.sparkles.fill",
                label: "Pray",
                reduceMotion: reduceMotion
            ) {
                dlog("[FloatingComposerDock] Pray tapped")
                AMENAnalyticsService.shared.track(.feedMeaningfulInteraction(type: "dock_pray"))
                NotificationCenter.default.post(name: Notification.Name("amen.openPrayerComposer"), object: nil)
            }

            DockButton(
                icon: "antenna.radiowaves.left.and.right",
                label: "Live",
                reduceMotion: reduceMotion
            ) {
                dlog("[FloatingComposerDock] Live tapped")
                AMENAnalyticsService.shared.track(.feedMeaningfulInteraction(type: "dock_live"))
                NotificationCenter.default.post(name: .openCreatePost, object: nil)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.10), radius: 12, x: 0, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Composer actions")
    }
}

private struct DockButton: View {

    let icon: String
    let label: String
    let reduceMotion: Bool
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            action()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.black.opacity(0.8))
                    .frame(width: 28, height: 28)
                    .accessibilityHidden(true)

                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.black.opacity(0.55))
            }
            .frame(minWidth: 60)
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
        }
        .scaleEffect(isPressed && !reduceMotion ? 0.84 : 1.0)
        .animation(reduceMotion ? .none : .spring(response: 0.22, dampingFraction: 0.55), value: isPressed)
        ._onButtonGesture(
            pressing: { pressing in isPressed = pressing },
            perform: {}
        )
        .accessibilityLabel(label)
    }
}

// MARK: - FlowLayout

/// A simple flow layout (left-to-right wrapping) used for context chips.
private struct SpatialFlowLayout: Layout {

    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let containerWidth = proposal.width ?? .infinity
        var height: CGFloat = 0
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width + (rowWidth > 0 ? spacing : 0) > containerWidth {
                height += rowHeight + spacing
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + (rowWidth > 0 ? spacing : 0)
            rowHeight = max(rowHeight, size.height)
        }
        height += rowHeight

        return CGSize(width: containerWidth, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Spatial Home — Flag On") {
    // Demonstrate the view in isolation; in production the caller
    // checks AMENFeatureFlags.shared.spatialHomeEnabled first.
    SpatialHomeView()
}

#Preview("Placeholder Card") {
    VStack(spacing: 12) {
        SpatialPostPlaceholderCard(postId: "preview_1", index: 0)
        SpatialPostPlaceholderCard(postId: "preview_2", index: 1)
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
#endif
