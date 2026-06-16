//
//  HeroSurfaceView.swift
//  AMENAPP
//
//  Flag-gated SwiftUI surface wrapping AdaptiveHeroEngine's AdaptiveHeroView.
//  When `heroSurfaceEnabled` is false (production default) this view renders
//  nothing — no layout contribution, no background loads.
//
//  Thread safety: @MainActor on the struct makes init + body both main-actor
//  isolated, matching HeroProfileViewModel's own @MainActor isolation.
//

import SwiftUI

#if canImport(AdaptiveHeroEngine)
import AdaptiveHeroEngine

/// Flag-gated wrapper for the Adaptive Hero surface.
/// Pass a pre-mapped `HeroSurface` (built via the adapter's `fromUser/fromChurch/fromSpace`).
@MainActor
struct HeroSurfaceView: View {
    let surface: HeroSurface
    let onAction: (HeroAction) -> Void

    /// ViewModel is created lazily in .task so construction is guaranteed main-actor.
    @State private var viewModel: HeroProfileViewModel?

    init(surface: HeroSurface, onAction: @escaping (HeroAction) -> Void = { _ in }) {
        self.surface = surface
        self.onAction = onAction
    }

    var body: some View {
        Group {
            if AMENFeatureFlags.shared.heroSurfaceEnabled, let vm = viewModel {
                AdaptiveHeroView(viewModel: vm, onAction: onAction)
                    .onChange(of: surface.id) {
                        vm.reloadIfSurfaceChanged(to: surface)
                    }
            }
            // Flag off → EmptyView (default). Zero layout shift, zero network activity.
        }
        .task {
            guard viewModel == nil else { return }
            viewModel = HeroProfileViewModel(
                surface: surface,
                imageLoader: URLCacheHeroImageLoader()
            )
        }
    }
}

// MARK: - Previews
// These bypass the flag gate and construct AdaptiveHeroView directly so the
// Xcode canvas renders the real hero without needing Remote Config.

#if DEBUG
#Preview("Creator hero") {
    AdaptiveHeroView(
        viewModel: HeroProfileViewModel(
            surface: HeroSurface(
                id: "preview_creator",
                kind: .creator,
                visibility: .publicAll,
                viewerRelationship: .stranger,
                title: "Jordan Pierce",
                subtitle: "Worship · Gospel",
                hero: HeroImageRef(url: nil, cacheKey: "preview_creator_hero"),
                faithTags: [.worship, .testimony, .youth]
            ),
            imageLoader: URLCacheHeroImageLoader()
        ),
        onAction: { _ in }
    )
}

#Preview("Church hero") {
    AdaptiveHeroView(
        viewModel: HeroProfileViewModel(
            surface: HeroSurface(
                id: "preview_church",
                kind: .church,
                visibility: .publicAll,
                viewerRelationship: .stranger,
                title: "The Gathering Place",
                subtitle: "Non-denominational · Atlanta",
                hero: HeroImageRef(url: nil, cacheKey: "preview_church_hero"),
                trust: .knownInCommunity,
                faithTags: [.worship, .teaching, .prayer, .outreach],
                location: "Atlanta, GA",
                modules: [
                    .about(AboutInfo(
                        mission: "A community built around Word, worship, and one another.",
                        location: "1234 Faith Ave, Atlanta, GA",
                        serviceTimes: ["Sun 9:00 AM", "Sun 11:30 AM"],
                        links: []
                    ))
                ]
            ),
            imageLoader: URLCacheHeroImageLoader()
        ),
        onAction: { _ in }
    )
}

#Preview("Space hero – member") {
    AdaptiveHeroView(
        viewModel: HeroProfileViewModel(
            surface: HeroSurface(
                id: "preview_space",
                kind: .space,
                visibility: .followersOnly,
                viewerRelationship: .member,
                title: "Morning Prayer Room",
                subtitle: "248 members",
                hero: HeroImageRef(url: nil, cacheKey: "preview_space_hero"),
                trust: .knownInCommunity,
                faithTags: [.prayer, .discipleship]
            ),
            imageLoader: URLCacheHeroImageLoader()
        ),
        onAction: { _ in }
    )
}

#Preview("Space – reduce transparency + a11y type") {
    AdaptiveHeroView(
        viewModel: HeroProfileViewModel(
            surface: HeroSurface(
                id: "preview_space_a11y",
                kind: .space,
                visibility: .publicAll,
                viewerRelationship: .stranger,
                title: "Praise & Worship",
                subtitle: "112 members",
                hero: HeroImageRef(url: nil, cacheKey: "preview_space_a11y_hero"),
                faithTags: [.worship]
            ),
            imageLoader: URLCacheHeroImageLoader()
        ),
        onAction: { _ in }
    )
    .environment(\.accessibilityReduceTransparency, true)
    .environment(\.dynamicTypeSize, .accessibility3)
}
#endif // DEBUG
#endif // canImport(AdaptiveHeroEngine)
