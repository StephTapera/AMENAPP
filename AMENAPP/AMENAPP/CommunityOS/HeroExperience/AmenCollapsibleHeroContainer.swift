// AmenCollapsibleHeroContainer.swift
// AMEN App — Community OS › Hero Experience
//
// Generic Apple Music-style collapsible hero container.
// Reused by Spaces, Mentor Channels, Church Hub, and Discussion threads.
//
// Glass placement rules (enforced here):
//   - nav back button:  glass circle
//   - nav more button:  glass circle
//   - action pill row:  glass capsule background
//   - content area:     plain .systemBackground — NO glass

import SwiftUI
import AVKit

// MARK: - HeroAction

struct HeroAction: Identifiable {
    let id: UUID
    let label: String
    let icon: String
    let style: HeroActionStyle
    let action: () -> Void

    init(label: String, icon: String, style: HeroActionStyle, action: @escaping () -> Void) {
        self.id = UUID()
        self.label = label
        self.icon = icon
        self.style = style
        self.action = action
    }
}

// MARK: - HeroActionStyle

enum HeroActionStyle {
    case primary
    case secondary
    case glass
}

// MARK: - Scroll offset preference key (file-private)

private struct HeroScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - AmenCollapsibleHeroContainer

struct AmenCollapsibleHeroContainer<Content: View>: View {

    // MARK: Props

    let heroURL: URL?
    let title: String
    let subtitle: String?
    let badgeText: String?
    let actions: [HeroAction]
    let onDismiss: () -> Void
    let onMoreTapped: () -> Void
    @ViewBuilder let content: () -> Content

    // MARK: Feature flag

    @AppStorage("amen_collapsible_hero_enabled") private var heroEnabled = true

    // MARK: State

    @State private var scrollOffset: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    // MARK: Constants

    private let heroHeight: CGFloat = 340
    private let collapseStart: CGFloat = 0
    private let collapseEnd: CGFloat = 200
    private let navBarThreshold: CGFloat = 180

    // MARK: Derived scroll values

    private var scrollProgress: CGFloat {
        guard collapseEnd > collapseStart else { return 0 }
        return min(1, max(0, scrollOffset / collapseEnd))
    }

    private var heroOpacity: CGFloat {
        1.0 - scrollProgress
    }

    private var parallaxOffset: CGFloat {
        reduceMotion ? 0 : min(scrollOffset * 0.4, heroHeight * 0.3)
    }

    private var isNavBarVisible: Bool {
        scrollOffset > navBarThreshold
    }

    // MARK: Body

    var body: some View {
        if heroEnabled {
            collapsibleBody
        } else {
            staticFallback
        }
    }

    // MARK: Collapsible body

    private var collapsibleBody: some View {
        ZStack(alignment: .top) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    heroSection
                    contentSection
                }
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .preference(
                                key: HeroScrollOffsetKey.self,
                                value: -geo.frame(in: .named("amenHeroScroll")).minY
                            )
                    }
                )
            }
            .coordinateSpace(name: "amenHeroScroll")
            .onPreferenceChange(HeroScrollOffsetKey.self) { value in
                scrollOffset = max(0, value)
            }
            .ignoresSafeArea(edges: .top)

            navOverlay
        }
        .ignoresSafeArea(edges: .top)
    }

    // MARK: Static fallback (feature flag off)

    private var staticFallback: some View {
        VStack(spacing: 0) {
            staticHeroHeader
            content()
                .background(Color(.systemBackground))
        }
    }

    private var staticHeroHeader: some View {
        ZStack(alignment: .bottom) {
            staticHeroBackground
                .frame(height: 200)
                .clipped()

            LinearGradient(
                colors: [.clear, Color.black.opacity(0.6)],
                startPoint: .center,
                endPoint: .bottom
            )
            .frame(height: 200)

            VStack(alignment: .leading, spacing: 4) {
                if let badge = badgeText {
                    badgePill(badge)
                }
                Text(title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                if let sub = subtitle {
                    Text(sub)
                        .font(.subheadline)
                        .foregroundStyle(Color.white.opacity(0.8))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private var staticHeroBackground: some View {
        if let url = heroURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    heroFallbackGradient
                }
            }
        } else {
            heroFallbackGradient
        }
    }

    // MARK: Hero section

    private var heroSection: some View {
        ZStack(alignment: .bottom) {
            heroMedia
                .frame(height: heroHeight)
                .clipped()
                .opacity(heroEnabled ? heroOpacity : 1)

            LinearGradient(
                colors: [.clear, Color.black.opacity(0.6)],
                startPoint: .init(x: 0.5, y: 0.6),
                endPoint: .bottom
            )
            .frame(height: heroHeight)
            .opacity(heroOpacity)

            VStack(spacing: 0) {
                heroTitleBlock
                    .opacity(heroOpacity)
                    .padding(.bottom, 12)

                if !actions.isEmpty {
                    heroActionPillRow
                        .opacity(heroOpacity)
                        .padding(.bottom, 20)
                }
            }
        }
        .frame(height: heroHeight)
    }

    // MARK: Hero media (image / video / fallback gradient)

    @ViewBuilder
    private var heroMedia: some View {
        if let url = heroURL {
            let path = url.pathExtension.lowercased()
            if path == "mp4" || path == "mov" {
                LoopingVideoView(url: url, parallaxOffset: parallaxOffset)
                    .frame(height: heroHeight + 60)
                    .offset(y: -parallaxOffset)
                    .accessibilityLabel(title)
                    .accessibilityHidden(true)
            } else {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(height: heroHeight + 60)
                            .offset(y: -parallaxOffset)
                            .clipped()
                            .overlay(
                                LinearGradient(
                                    colors: [.clear, Color.black.opacity(0.4)],
                                    startPoint: .init(x: 0.5, y: 0.4),
                                    endPoint: .bottom
                                )
                            )
                    case .failure:
                        heroFallbackGradient.frame(height: heroHeight + 60)
                    case .empty:
                        heroFallbackGradient.frame(height: heroHeight + 60)
                            .redacted(reason: .placeholder)
                    @unknown default:
                        heroFallbackGradient.frame(height: heroHeight + 60)
                    }
                }
                .accessibilityLabel(title)
            }
        } else {
            heroFallbackGradient
                .frame(height: heroHeight + 60)
                .offset(y: -parallaxOffset)
                .accessibilityLabel(title)
                .accessibilityHidden(true)
        }
    }

    private var heroFallbackGradient: some View {
        LinearGradient(
            stops: [
                .init(color: Color(hex: "#1A1A2E"), location: 0),
                .init(color: Color(hex: "#16213E"), location: 1)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: Hero title block (large, inside hero)

    private var heroTitleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let badge = badgeText {
                badgePill(badge)
            }
            Text(title)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if let sub = subtitle {
                Text(sub)
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.80))
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
    }

    private func badgePill(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5))
    }

    // MARK: Hero action pill row (glass capsule — approved glass placement)

    private var heroActionPillRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(actions) { heroAction in
                    HeroActionButton(heroAction: heroAction)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
        }
    }

    // MARK: Content section

    private var contentSection: some View {
        content()
            .frame(maxWidth: .infinity)
            .background(Color(.systemBackground))
    }

    // MARK: Nav overlay (always visible, not clipped by scroll)

    private var navOverlay: some View {
        VStack(spacing: 0) {
            compactNavBar
            Spacer()
        }
    }

    private var compactNavBar: some View {
        ZStack {
            if isNavBarVisible {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea(edges: .top)
                    .frame(height: 90)
                    .transition(.opacity.animation(.easeInOut(duration: 0.2)))
            }

            HStack(spacing: 0) {
                navGlassButton(icon: "chevron.left", a11yLabel: "Go back", action: onDismiss)
                    .padding(.leading, 16)

                Spacer()

                if isNavBarVisible {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color(.label))
                        .lineLimit(1)
                        .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                }

                Spacer()

                navGlassButton(icon: "ellipsis", a11yLabel: "More options", action: onMoreTapped)
                    .padding(.trailing, 16)
            }
            .padding(.top, 56)
            .padding(.bottom, 10)
        }
        .animation(.easeInOut(duration: 0.2), value: isNavBarVisible)
    }

    // MARK: Glass nav button — reuses the same pattern as MediaHeroView

    private func navGlassButton(icon: String, a11yLabel: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(reduceTransparency
                            ? Color(hex: "#1A1A2E")
                            : Color.black.opacity(0.35))
                        .overlay(
                            Circle()
                                .fill(.ultraThinMaterial)
                                .opacity(reduceTransparency ? 0 : 1)
                        )
                )
                .overlay(Circle().strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5))
                .shadow(color: Color.black.opacity(0.25), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(a11yLabel)
    }
}

// MARK: - HeroActionButton

private struct HeroActionButton: View {
    let heroAction: HeroAction

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Button(action: heroAction.action) {
            HStack(spacing: 6) {
                Image(systemName: heroAction.icon)
                    .font(.system(size: 14, weight: .semibold))
                Text(heroAction.label)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(labelColor)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(buttonBackground)
        }
        .buttonStyle(GlassPressStyle())
        .accessibilityLabel(heroAction.label)
    }

    private var labelColor: Color {
        switch heroAction.style {
        case .primary:   return .white
        case .secondary: return .white
        case .glass:     return .white
        }
    }

    @ViewBuilder
    private var buttonBackground: some View {
        switch heroAction.style {
        case .primary:
            Capsule()
                .fill(Color.black.opacity(0.85))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5))

        case .secondary:
            Capsule()
                .fill(Color.clear)
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.65), lineWidth: 1))

        case .glass:
            Capsule()
                .fill(reduceTransparency
                    ? Color(hex: "#1A1A2E")
                    : Color.white.opacity(0.15))
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .opacity(reduceTransparency ? 0 : 1)
                )
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.30), lineWidth: 0.5))
        }
    }
}

// MARK: - LoopingVideoView

private struct LoopingVideoView: UIViewRepresentable {
    let url: URL
    let parallaxOffset: CGFloat

    func makeUIView(context: Context) -> UIView {
        let containerView = UIView()
        containerView.clipsToBounds = true
        containerView.backgroundColor = UIColor(Color(hex: "#1A1A2E"))

        let player = AVPlayer(url: url)
        player.isMuted = true
        player.actionAtItemEnd = .none
        context.coordinator.player = player

        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspectFill
        containerView.layer.addSublayer(playerLayer)
        context.coordinator.playerLayer = playerLayer

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.playerDidReachEnd(_:)),
            name: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem
        )

        player.play()
        return containerView
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.playerLayer?.frame = uiView.bounds
        }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.player?.pause()
        NotificationCenter.default.removeObserver(coordinator)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject {
        var player: AVPlayer?
        var playerLayer: AVPlayerLayer?

        @objc func playerDidReachEnd(_ notification: Notification) {
            player?.seek(to: .zero)
            player?.play()
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Collapsible Hero — image") {
    AmenCollapsibleHeroContainer(
        heroURL: URL(string: "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?w=800"),
        title: "Sunday Morning Worship",
        subtitle: "Grace Fellowship · Live",
        badgeText: "Live",
        actions: [
            HeroAction(label: "Join", icon: "person.badge.plus", style: .primary, action: { }),
            HeroAction(label: "Discuss", icon: "bubble.left", style: .secondary, action: { }),
            HeroAction(label: "Pray", icon: "hands.sparkles", style: .glass, action: { })
        ],
        onDismiss: { },
        onMoreTapped: { }
    ) {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(0..<12, id: \.self) { i in
                HStack {
                    Image(systemName: "text.bubble")
                        .foregroundStyle(Color(.secondaryLabel))
                    Text("Content row \(i + 1)")
                        .font(.body)
                        .foregroundStyle(Color(.label))
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                Divider().padding(.horizontal, 16)
            }
        }
        .padding(.top, 16)
    }
}

#Preview("Static fallback — flag off") {
    AmenCollapsibleHeroContainer(
        heroURL: nil,
        title: "Mentor Channel",
        subtitle: "Pastor James",
        badgeText: nil,
        actions: [
            HeroAction(label: "Follow", icon: "star", style: .primary, action: { })
        ],
        onDismiss: { },
        onMoreTapped: { }
    ) {
        Text("Content area")
            .padding()
    }
}
#endif
