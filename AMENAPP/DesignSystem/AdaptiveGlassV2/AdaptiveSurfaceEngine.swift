//
//  AdaptiveSurfaceEngine.swift
//  AMEN — Adaptive Glass V2
//
//  @Observable per-scene coordinator.
//  One engine lives at each NavigationStack / TabView root (installed via
//  .adaptiveSurfaceScene()). It ingests:
//    - Scroll geometry        (throttled to 50 ms — from onScrollGeometryChange)
//    - Media metadata         (precomputed brightness/color from AdaptiveColorEngine)
//    - Keyboard state         (UIKeyboard notifications on the main queue)
//    - A11y snapshot          (read once per scene activation via .task)
//
//  Performance contract:
//    - Zero per-frame sampling. All media analysis is precomputed.
//    - Scroll updates are throttled: < 50 ms gaps are swallowed.
//    - Engine state is @MainActor — no cross-actor data races.
//    - Keyboard observers are cleaned up on stop / deinit.
//

import SwiftUI
import Observation
import UIKit

@Observable @MainActor
public final class AdaptiveSurfaceEngine {

    // MARK: - Published output

    /// The current surface context. SurfaceStateResolver reads this to
    /// produce a GlassSurfaceState for each role.
    public private(set) var context: SurfaceContext = .neutral

    // MARK: - Scroll (throttled)

    private var lastScrollUpdate: Date = .distantPast
    private static let scrollThrottle: TimeInterval = 0.050  // 50 ms

    /// Drive from `onScrollGeometryChange` on any ScrollView that owns the
    /// full-screen content. Throttled — redundant calls within 50 ms are dropped.
    public func updateScroll(offset: CGFloat, contentHeight: CGFloat = 0) {
        let now = Date()
        guard now.timeIntervalSince(lastScrollUpdate) >= Self.scrollThrottle else { return }
        lastScrollUpdate = now

        let newState: ScrollState
        if offset <= 4 {
            newState = .atTop
        } else if contentHeight > 0, offset > contentHeight * 0.55 {
            newState = .deep
        } else if offset > 500 {
            // Fallback when contentHeight is not provided.
            newState = .deep
        } else {
            // Direction: positive offset = scrolling down (content moving up).
            newState = .scrolling(direction: offset >= (lastKnownOffset ?? 0) ? .down : .up)
        }

        lastKnownOffset = offset
        if context.scrollState != newState {
            context.scrollState = newState
        }
    }

    private var lastKnownOffset: CGFloat?

    // MARK: - Media metadata (precomputed — never live)

    /// Update from the precomputed AmbientPalette for the currently-visible asset.
    /// This bridges the existing AdaptiveColorEngine / AmbientCoordinator system
    /// into the V2 engine without duplicating extraction logic.
    public func updateFromAmbientPalette(_ palette: AmbientPalette, kind: MediaKind) {
        let brightness: Brightness
        if palette.isDarkContent {
            // Check for busy: high dominant saturation + dark content = busy.
            brightness = isBusyPalette(palette) ? .busy : .dark
        } else {
            brightness = isBusyPalette(palette) ? .busy : .light
        }

        let isNeutral = (palette == .neutralLight || palette == .neutralDark)
        let dominant: Color? = isNeutral ? nil : palette.dominant

        context.backgroundBrightness = brightness
        context.dominantColor = dominant
        context.mediaType = kind
        context.contrastRisk = brightness == .busy
    }

    /// Explicit update for surfaces that compute brightness themselves
    /// (e.g. hero banners with known brightness from server metadata).
    public func updateMedia(brightness: Brightness, dominant: Color?, kind: MediaKind) {
        context.backgroundBrightness = brightness
        context.dominantColor = dominant
        context.mediaType = kind
        context.contrastRisk = brightness == .busy
    }

    /// Reset to neutral (non-media screen, plain text feed).
    public func resetMedia() {
        context.backgroundBrightness = .light
        context.dominantColor = nil
        context.mediaType = .none
        context.contrastRisk = false
    }

    // MARK: - Keyboard state

    public func updateKeyboard(visible: Bool) {
        if context.keyboardVisible != visible {
            context.keyboardVisible = visible
        }
    }

    public func updateFocus(active: Bool) {
        if context.activeInput != active {
            context.activeInput = active
        }
    }

    // MARK: - A11y snapshot

    public func updateA11y(snapshot: A11ySnapshot) {
        if context.a11y != snapshot {
            context.a11y = snapshot
        }
    }

    // MARK: - Keyboard notifications

    private var keyboardObservers: [NSObjectProtocol] = []

    public func startObservingKeyboard() {
        guard keyboardObservers.isEmpty else { return }
        let show = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardDidShowNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.updateKeyboard(visible: true)
        }
        let hide = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardDidHideNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.updateKeyboard(visible: false)
        }
        keyboardObservers = [show, hide]
    }

    public func stopObservingKeyboard() {
        keyboardObservers.forEach { NotificationCenter.default.removeObserver($0) }
        keyboardObservers = []
    }

    deinit {
        keyboardObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    // MARK: - Helpers

    /// Heuristic: palette with high-saturation dominant color on a mid-luminance
    /// background is "busy." Delegates the actual check to the existing
    /// AdaptiveColorEngine's isDarkContent + a saturation proxy.
    private func isBusyPalette(_ palette: AmbientPalette) -> Bool {
        // We don't have direct access to the raw saturation here — use a
        // conservative proxy: if the background and dominant colors are
        // highly dissimilar, treat as busy.
        // A full implementation would read a `isBusy: Bool` field stored
        // alongside the AmbientPalette by the extraction pipeline.
        // For now this returns false (conservative: never falsely trigger busy).
        return false
    }
}

// MARK: - Environment key

private struct AdaptiveSurfaceEngineKey: EnvironmentKey {
    static let defaultValue: AdaptiveSurfaceEngine? = nil
}

public extension EnvironmentValues {
    /// The per-scene AdaptiveSurfaceEngine. Install once at the NavigationStack
    /// root via .adaptiveSurfaceScene(). Read by .adaptiveSurface() modifiers.
    var adaptiveSurfaceEngine: AdaptiveSurfaceEngine? {
        get { self[AdaptiveSurfaceEngineKey.self] }
        set { self[AdaptiveSurfaceEngineKey.self] = newValue }
    }
}

// MARK: - Scene root modifier

/// Installs one AdaptiveSurfaceEngine into the environment and wires up
/// keyboard observation + a11y snapshot tracking.
///
/// Apply once at the NavigationStack / TabView root:
///
///     MainTabView()
///         .adaptiveSurfaceScene()
///
public struct AdaptiveSurfaceSceneModifier: ViewModifier {
    @State private var engine = AdaptiveSurfaceEngine()

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion)        private var reduceMotion
    @Environment(\.colorSchemeContrast)              private var contrast
    @Environment(\.dynamicTypeSize)                  private var dynamicTypeSize

    public func body(content: Content) -> some View {
        content
            .environment(\.adaptiveSurfaceEngine, engine)
            .task(id: a11ySnapshotID) {
                engine.updateA11y(snapshot: A11ySnapshot(
                    reduceTransparency: reduceTransparency,
                    reduceMotion: reduceMotion,
                    increaseContrast: contrast == .increased,
                    dynamicTypeSize: dynamicTypeSize
                ))
            }
            .onAppear { engine.startObservingKeyboard() }
            .onDisappear { engine.stopObservingKeyboard() }
    }

    /// A stable string ID that changes whenever any a11y setting changes,
    /// triggering the .task to re-snapshot.
    private var a11ySnapshotID: String {
        "\(reduceTransparency)-\(reduceMotion)-\(contrast)-\(dynamicTypeSize)"
    }
}

public extension View {
    /// Install at the NavigationStack / TabView root to provide the
    /// AdaptiveSurfaceEngine to all descendant adaptive surfaces.
    func adaptiveSurfaceScene() -> some View {
        modifier(AdaptiveSurfaceSceneModifier())
    }
}

// MARK: - Scroll driver modifier

/// Attach to any ScrollView to automatically feed scroll offset into the engine.
///
///     ScrollView {
///         feedContent
///     }
///     .adaptiveSurfaceScrollDriver()
///
public struct AdaptiveSurfaceScrollDriver: ViewModifier {
    @Environment(\.adaptiveSurfaceEngine) private var engine

    public func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: ScrollGeometryProxy.self) { $0 } action: { _, geo in
                engine?.updateScroll(
                    offset: geo.contentOffset.y,
                    contentHeight: geo.contentSize.height
                )
            }
    }
}

public extension View {
    /// Feed scroll offset from this ScrollView into the scene's AdaptiveSurfaceEngine.
    func adaptiveSurfaceScrollDriver() -> some View {
        modifier(AdaptiveSurfaceScrollDriver())
    }
}
