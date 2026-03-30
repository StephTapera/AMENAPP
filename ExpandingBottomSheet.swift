//
//  ExpandingBottomSheet.swift
//  AMENAPP
//
//  Scroll-driven bottom sheet that expands as the user scrolls up.
//  Single progress value (0→1) drives every animation — no conflicting modifiers.
//
//  Usage:
//    ExpandingBottomSheet(minHeight: 220, maxHeight: UIScreen.main.bounds.height * 0.85) {
//        MyHeroView()           // headerContent
//    } expandedContent: {
//        MyDetailView()         // expandedContent
//    }
//

import SwiftUI

// MARK: - Scroll-offset preference key

private struct SheetScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - ExpandingBottomSheet

/// A scroll-driven bottom sheet.
/// `progress` (0→1) is derived from the inner ScrollView's offset and
/// drives every animation — blur, overlay, sheet height, content reveal.
struct ExpandingBottomSheet<Header: View, Expanded: View>: View {

    // MARK: Configuration
    var minHeight: CGFloat          // compact state
    var maxHeight: CGFloat          // fully expanded
    var backgroundBlurRadius: CGFloat = 6
    var overlayMaxOpacity: CGFloat   = 0.30

    @ViewBuilder var headerContent: () -> Header
    @ViewBuilder var expandedContent: () -> Expanded

    // MARK: Internal state
    @State private var scrollOffset: CGFloat = 0

    // MARK: Derived values — single source of truth
    private var progress: CGFloat {
        // scrollOffset is negative as user scrolls up inside the inner scroll view
        let travel = maxHeight - minHeight
        guard travel > 0 else { return 0 }
        return min(max(-scrollOffset / travel, 0), 1)
    }

    private var sheetHeight: CGFloat {
        minHeight + (maxHeight - minHeight) * progress
    }

    private var blurRadius: CGFloat {
        backgroundBlurRadius * progress
    }

    private var overlayOpacity: CGFloat {
        overlayMaxOpacity * progress
    }

    // Content sections reveal with staggered offsets:
    // reveal starts at 30% progress, fully visible at 80%
    private func revealProgress(delay: CGFloat = 0.0) -> CGFloat {
        let start: CGFloat = 0.25 + delay
        let end:   CGFloat = 0.75 + delay
        return min(max((progress - start) / (end - start), 0), 1)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {

                // ── Hero / background layer ─────────────────────────────
                heroLayer(geo: geo)

                // ── Expanding sheet ─────────────────────────────────────
                sheetLayer(geo: geo)
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }

    // MARK: - Hero layer

    @ViewBuilder
    private func heroLayer(geo: GeometryProxy) -> some View {
        ZStack {
            headerContent()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                // Subtle zoom-in as sheet rises (scale 1 → 1.06)
                .scaleEffect(1 + 0.06 * progress, anchor: .top)
                .animation(.interactiveSpring(response: 0.35, dampingFraction: 0.85), value: progress)

            // Progressive dark overlay for contrast
            Color.black
                .opacity(overlayOpacity)
                .ignoresSafeArea()
                .animation(.interactiveSpring(response: 0.35, dampingFraction: 0.85), value: progress)
        }
    }

    // MARK: - Sheet layer

    @ViewBuilder
    private func sheetLayer(geo: GeometryProxy) -> some View {
        VStack(spacing: 0) {

            // ── Drag handle ─────────────────────────────────────────────
            Capsule()
                .fill(Color.primary.opacity(0.20))
                .frame(width: 36, height: 4)
                .padding(.top, 10)
                .padding(.bottom, 6)
                // Fades out as sheet reaches full height
                .opacity(1 - progress)

            // ── Inner scroll view that DRIVES the animation ─────────────
            ScrollView(.vertical, showsIndicators: false) {

                // Invisible offset tracker at the top of the scroll content
                GeometryReader { inner in
                    Color.clear
                        .preference(
                            key: SheetScrollOffsetKey.self,
                            value: inner.frame(in: .named("sheetScroll")).minY
                        )
                }
                .frame(height: 0)

                // Expanded content with staggered reveal
                expandedContent()
                    .opacity(revealProgress())
                    .offset(y: (1 - revealProgress()) * 24)
                    .animation(
                        .interactiveSpring(response: 0.4, dampingFraction: 0.82),
                        value: progress
                    )
                    .padding(.bottom, geo.safeAreaInsets.bottom + 16)
            }
            .coordinateSpace(name: "sheetScroll")
            .onPreferenceChange(SheetScrollOffsetKey.self) { val in
                // Only pull-to-expand gesture: only let upward scroll grow the sheet
                scrollOffset = min(val, 0)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(height: sheetHeight, alignment: .top)
        .background {
            // Glassmorphic surface
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.18), radius: 20, y: -6)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .animation(
            .interactiveSpring(response: 0.38, dampingFraction: 0.82),
            value: sheetHeight
        )
    }
}

// MARK: - Convenience read-only wrappers

extension ExpandingBottomSheet {
    /// 0.0 (compact) → 1.0 (fully expanded)
    var expansionProgress: CGFloat { progress }

    /// True when sheet is more than 50% expanded
    var isExpanded: Bool { progress > 0.5 }
}

// MARK: - Read-More toggle (self-contained helper)

/// Drop this inside an `expandedContent` block for an in-place
/// "Read more / Show less" text expansion that doesn't re-render
/// the parent sheet.
struct ReadMoreText: View {
    let text: String
    var collapsedLineLimit: Int = 3
    var font: Font = .custom("OpenSans-Regular", size: 15)

    @State private var expanded = false
    @State private var isTruncated = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text)
                .font(font)
                .lineLimit(expanded ? nil : collapsedLineLimit)
                .background(
                    // Hidden full-height text to detect truncation
                    GeometryReader { fullGeo in
                        Text(text)
                            .font(font)
                            .lineLimit(collapsedLineLimit)
                            .background(
                                GeometryReader { truncGeo in
                                    Color.clear.onAppear {
                                        isTruncated = fullGeo.size.height > truncGeo.size.height
                                    }
                                }
                            )
                            .hidden()
                    }
                    .hidden()
                )
                .animation(.spring(response: 0.32, dampingFraction: 0.78), value: expanded)

            if isTruncated {
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                        expanded.toggle()
                    }
                } label: {
                    Text(expanded ? "Show less" : "Read more")
                        .font(.custom("OpenSans-SemiBold", size: 14))
                        .foregroundStyle(.blue)
                }
            }
        }
    }
}

// MARK: - Attribute grid row (used in demo + church)

struct SheetAttributeRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 22)

            Text(label)
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.custom("OpenSans-SemiBold", size: 14))
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 6)
    }
}
