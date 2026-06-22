//
//  CollapsibleGlassScrollView.swift
//  AMENAPP
//
//  Host scaffold for the collapsible Liquid Glass header (spec §7).
//
//  Owns the ONE scroll-offset source and pins the header as a top overlay (not the
//  first scroll row), so cards pass cleanly underneath it. The header builder receives
//  the live `progress` (0...1) and the resolved top safe-area inset.
//
//  Scroll reading prefers the native `onScrollGeometryChange` (iOS 18+, native on the
//  iOS 26 target) and falls back to the app's existing `ScrollOffsetPreferenceKey`
//  below that, so the scaffold compiles regardless of deployment target.
//
//  The tuck (spec §4): content top padding is `topInset + expandedHeaderHeight`, so the
//  first card sits exactly at the expanded header's bottom edge at rest. Because the
//  header loses `collapseDistance` (= expanded − collapsed) as it pins, and the card has
//  scrolled up by that same amount, the card meets the collapsed capsule flush — no gap,
//  no overlap.
//

import SwiftUI

struct CollapsibleGlassScrollView<Header: View, Content: View>: View {
    var metrics: GlassScrollMetrics
    var coordinateSpaceName: String
    /// Builds the pinned header. Receives `(progress 0...1, topSafeAreaInset)`.
    @ViewBuilder var header: (CGFloat, CGFloat) -> Header
    @ViewBuilder var content: () -> Content

    @State private var rawScroll: CGFloat = 0

    init(
        metrics: GlassScrollMetrics = .init(),
        coordinateSpace: String = "glassScroll",
        @ViewBuilder header: @escaping (CGFloat, CGFloat) -> Header,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.metrics = metrics
        self.coordinateSpaceName = coordinateSpace
        self.header = header
        self.content = content
    }

    var body: some View {
        GeometryReader { proxy in
            let topInset = proxy.safeAreaInsets.top
            let progress = metrics.progress(forScrolled: rawScroll)
            let headerHeight = topInset + metrics.headerContentHeight(
                progressEased: GlassScrollMath.smoothstep(0, 1, progress)
            )

            ZStack(alignment: .top) {
                scrollLayer(topInset: topInset)

                header(progress, topInset)
                    .frame(maxWidth: .infinity)
                    .frame(height: headerHeight, alignment: .bottom)
            }
            .ignoresSafeArea(edges: .top)
        }
    }

    // MARK: Scroll layer (native first, PreferenceKey fallback)

    @ViewBuilder
    private func scrollLayer(topInset: CGFloat) -> some View {
        if #available(iOS 18.0, *) {
            ScrollView {
                content()
                    .padding(.top, topInset + metrics.expandedHeaderHeight)
            }
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                // "Distance scrolled down from the top," 0 at rest.
                geo.contentOffset.y + geo.contentInsets.top
            } action: { _, scrolled in
                // Small deadband avoids redundant state writes on sub-pixel jitter.
                if abs(scrolled - rawScroll) > 0.25 { rawScroll = scrolled }
            }
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: ScrollOffsetPreferenceKey.self,
                            value: geo.frame(in: .named(coordinateSpaceName)).minY
                        )
                    }
                    .frame(height: 0)

                    content()
                        .padding(.top, topInset + metrics.expandedHeaderHeight)
                }
            }
            .coordinateSpace(name: coordinateSpaceName)
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                // minY goes negative as content scrolls up; negate to get distance.
                let scrolled = max(-value, 0)
                if abs(scrolled - rawScroll) > 0.25 { rawScroll = scrolled }
            }
        }
    }
}
