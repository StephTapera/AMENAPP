//
//  AmbientEnvironment.swift
//  AMEN — Adaptive Ambient UI System (Phase 2A)
//
//  One coordinator per ambient *scope* (a screen, a pager page, a feed). Owns the live
//  palette, debounces updates (250ms — scroll-safe, C7/perf), animates transitions, and
//  honors all a11y traits: Reduce Motion ⇒ instant palette apply (C4); .off ⇒ neutral (C2).
//

import SwiftUI

/// One coordinator per ambient *scope*. Owns the live palette, debounces updates,
/// animates transitions, honors all a11y traits.
@MainActor
public final class AmbientCoordinator: ObservableObject {
    @Published public private(set) var palette: AmbientPalette = .neutralLight

    @AppStorage(AmbientStorageKeys.mode) private var modeRaw: String = AdaptiveColorsMode.balanced.rawValue
    public var mode: AdaptiveColorsMode { AdaptiveColorsMode(rawValue: modeRaw) ?? .balanced }

    private var pendingTask: Task<Void, Never>?
    private var activeKey: AmbientSourceKey?

    public init() {}

    /// Drive ambient from an image. Debounced 250ms — scroll-safe.
    public func drive(with image: UIImage?, key: AmbientSourceKey,
                      scheme: ColorScheme, reduceMotion: Bool) {
        guard mode != .off else { apply(.neutral(for: scheme), reduceMotion: true); return }   // C2
        guard key != activeKey || image == nil else { return }
        activeKey = key
        pendingTask?.cancel()
        pendingTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self else { return }
            guard let image else { self.apply(.neutral(for: scheme), reduceMotion: reduceMotion); return }
            let p = await AdaptiveColorEngine.shared.palette(for: image, key: key, colorScheme: scheme)
            guard !Task.isCancelled, self.activeKey == key else { return }
            self.apply(p, reduceMotion: reduceMotion)
        }
    }

    public func reset(scheme: ColorScheme, reduceMotion: Bool) {
        activeKey = nil
        apply(.neutral(for: scheme), reduceMotion: reduceMotion)
    }

    private func apply(_ p: AmbientPalette, reduceMotion: Bool) {
        if reduceMotion { palette = p }                                  // C4 — instant, no crossfade
        else { withAnimation(.easeInOut(duration: 0.6)) { palette = p } } // smooth crossfade, no flicker
    }
}

/// Root modifier: installs coordinator output into the environment for a scope.
public struct AmbientScope<Content: View>: View {
    @StateObject private var coordinator = AmbientCoordinator()
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let content: (AmbientCoordinator) -> Content

    public init(@ViewBuilder content: @escaping (AmbientCoordinator) -> Content) {
        self.content = content
    }

    public var body: some View {
        content(coordinator)
            .environment(\.ambientPalette, coordinator.palette)
            .environment(\.ambientIntensity, coordinator.mode.intensity)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: coordinator.palette)
    }
}

/// Feed activation: only the centered/visible item drives chrome (Rules §6).
///
/// iOS 18+ uses `onScrollVisibilityChange(threshold:)` for precise 62%-visibility activation.
/// On iOS 17 (deployment target) we degrade gracefully: the item drives chrome on appear
/// and the coordinator's 250ms debounce + activeKey gate absorb fast-scroll churn.
public struct AmbientFeedItem: ViewModifier {
    let image: UIImage?
    let key: AmbientSourceKey
    @ObservedObject var coordinator: AmbientCoordinator
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollVisibilityChange(threshold: 0.62) { visible in
                if visible { drive() }
            }
        } else {
            content.onAppear { drive() }
        }
    }

    private func drive() {
        coordinator.drive(with: image, key: key, scheme: scheme, reduceMotion: reduceMotion)
    }
}

public extension View {
    func ambientFeedItem(image: UIImage?, key: AmbientSourceKey,
                         coordinator: AmbientCoordinator) -> some View {
        modifier(AmbientFeedItem(image: image, key: key, coordinator: coordinator))
    }
}
