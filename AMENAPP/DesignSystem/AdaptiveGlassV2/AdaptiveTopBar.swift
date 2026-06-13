//
//  AdaptiveTopBar.swift
//  AMEN — Adaptive Glass V2
//
//  Wave 2: Adaptive navigation chrome.
//
//  Wire to the child view of a NavigationStack — same level as
//  .navigationTitle, .toolbar, etc.:
//
//      mainScrollContent
//          .navigationTitle("Home")
//          .adaptiveNavigation(title: "Home")
//
//  Optionally wire the scroll edge blur and toolbar minimize:
//
//      ScrollView { content }
//          .adaptiveScrollEdgeEffect()           // iOS 26 edge blur under status bar
//          .adaptiveToolbarMinimize()            // iOS 26 bar compress-on-scroll
//
//  For hero images on profile / space headers:
//
//      Image(bannerURL)
//          .heroBackgroundExtension()            // iOS 26 blur-and-fill under bars
//

import SwiftUI

// MARK: - Adaptive navigation bar

/// Controls toolbar background transparency based on the AdaptiveSurfaceEngine.
/// On iOS 26 the system handles the Liquid Glass rendering; this modifier
/// just controls whether the bar is transparent or opaque.
///
/// Flag OFF → zero-cost passthrough.
public struct AdaptiveNavigationModifier: ViewModifier {

    let title: String

    @Environment(\.adaptiveSurfaceEngine) private var engine
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public func body(content: Content) -> some View {
        guard AMENFeatureFlags.shared.adaptiveGlassV2Enabled, let engine else {
            return AnyView(content)
        }

        let state = SurfaceStateResolver.resolve(context: engine.context, role: .topBar)
        // Transparent / hidden / collapsed → hide the bar background so the
        // content shows through. Frosted / solidLight → make the bar visible
        // and let the system apply the appropriate glass or material.
        let barsHidden = state == .transparent || state == .hidden || state == .collapsed

        return AnyView(
            content
                .toolbarBackground(barsHidden ? .hidden : .visible, for: .navigationBar)
                .animation(
                    reduceMotion
                        ? .easeInOut(duration: 0.15)
                        : Motion.adaptive(.spring(response: 0.32, dampingFraction: 0.80)),
                    value: state
                )
        )
    }
}

// MARK: - Scroll edge blur (iOS 26)

/// Applies `.scrollEdgeEffectStyle(.hard, for: .top)` so content blurs as it
/// scrolls under the status bar. No-op on iOS 17/18 where the system's default
/// toolbar chrome handles the edge.
public struct AdaptiveScrollEdgeModifier: ViewModifier {
    public func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.scrollEdgeEffectStyle(.hard, for: .top)
        } else {
            content
        }
    }
}

// MARK: - Toolbar minimize on scroll (iOS 26)

/// Applies `.toolbarMinimizeBehavior(.onScrollDown, for: .navigationBar)` so the
/// navigation bar shrinks when the user scrolls down and re-expands on scroll up.
/// This is the system implementation of the spec's `.collapsed` state.
///
/// Apply to the ScrollView (or its container) inside a NavigationStack.
/// No-op on iOS 17/18.
public struct AdaptiveToolbarMinimizeModifier: ViewModifier {
    public func body(content: Content) -> some View {
        guard AMENFeatureFlags.shared.adaptiveGlassV2Enabled else {
            return AnyView(content)
        }
        if #available(iOS 27, *) {
            return AnyView(content.toolbarMinimizeBehavior(.onScrollDown, for: .navigationBar))
        } else {
            return AnyView(content)
        }
    }
}

// MARK: - Hero background extension (iOS 26)

/// Extends a hero/banner image under sidebar or inspector panels using the
/// iOS 26 `backgroundExtensionEffect()`. Typically applied to profile banners
/// and Space header images. No-op on iOS 17/18.
///
/// Apply to the image view itself, not to an overlay:
///
///     Image(bannerURL)
///         .resizable()
///         .scaledToFill()
///         .heroBackgroundExtension()   // extend under adjacent panels
///         .overlay { titleRow }
///
public struct HeroBackgroundExtensionModifier: ViewModifier {
    public func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.backgroundExtensionEffect()
        } else {
            content
        }
    }
}

// MARK: - View extensions

public extension View {

    /// Declare this view as the NavigationStack child content to enable the
    /// adaptive navigation bar. The engine resolves context + role into a
    /// GlassSurfaceState and controls toolbar background visibility accordingly.
    ///
    /// No-op when `adaptiveGlassV2Enabled` is OFF.
    func adaptiveNavigation(title: String) -> some View {
        modifier(AdaptiveNavigationModifier(title: title))
    }

    /// Apply the iOS 26 scroll edge blur effect to a ScrollView so content
    /// fades as it passes under the status bar. Safe no-op on iOS 17/18.
    func adaptiveScrollEdgeEffect() -> some View {
        modifier(AdaptiveScrollEdgeModifier())
    }

    /// Compress the navigation bar when the user scrolls down and re-expand
    /// on scroll up (iOS 26 `toolbarMinimizeBehavior`). Apply to the ScrollView
    /// inside a NavigationStack. No-op on iOS 17/18 or when flag is OFF.
    func adaptiveToolbarMinimize() -> some View {
        modifier(AdaptiveToolbarMinimizeModifier())
    }

    /// Extend a hero/banner image under adjacent panels using iOS 26
    /// `backgroundExtensionEffect`. Apply to the image only, not the overlay.
    /// No-op on iOS 17/18.
    func heroBackgroundExtension() -> some View {
        modifier(HeroBackgroundExtensionModifier())
    }
}
