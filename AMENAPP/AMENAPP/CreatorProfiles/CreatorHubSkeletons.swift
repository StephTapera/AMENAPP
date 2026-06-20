// CreatorHubSkeletons.swift
// AMEN — Creator Profiles (ministry hubs) — Wave 3
//
// Skeleton-first rendering primitives for the Creator Hub. Every surface renders these
// IMMEDIATELY (no spinner) while the payload assembles, then swaps to real content.
//
// Reduce-motion: shimmer animation is disabled (static fill) when
// accessibilityReduceMotion is on. Otherwise a subtle gray gradient sweeps across.
//
// Conventions: white bg / translucent surfaces; AmenTheme.Colors.* tokens only;
// no glass-on-glass; Dynamic-Type-safe (these carry no text).

import SwiftUI

// MARK: - Shimmer modifier (reduce-motion aware)

/// A subtle left-to-right gray gradient sweep. Static when reduce-motion is on.
private struct CreatorHubShimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay {
                if reduceMotion {
                    // Static fallback — no animation, just the base skeleton tone.
                    AmenTheme.Colors.shimmerBase
                } else {
                    GeometryReader { geo in
                        LinearGradient(
                            stops: [
                                .init(color: AmenTheme.Colors.shimmerBase, location: 0.0),
                                .init(color: AmenTheme.Colors.shimmerHighlight, location: 0.5),
                                .init(color: AmenTheme.Colors.shimmerBase, location: 1.0),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: geo.size.width * 2)
                        .offset(x: phase * geo.size.width * 1.5)
                        .onAppear {
                            withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) {
                                phase = 1
                            }
                        }
                    }
                }
            }
            .clipped()
            .accessibilityHidden(true)
    }
}

private extension View {
    func creatorHubShimmer() -> some View { modifier(CreatorHubShimmer()) }
}

// MARK: - SkeletonBlock

/// A single rounded skeleton rectangle.
struct SkeletonBlock: View {
    var width: CGFloat?
    var height: CGFloat
    var cornerRadius: CGFloat

    init(width: CGFloat? = nil, height: CGFloat, cornerRadius: CGFloat = 8) {
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(AmenTheme.Colors.shimmerBase)
            .frame(width: width, height: height)
            .creatorHubShimmer()
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .accessibilityHidden(true)
    }
}

// MARK: - SkeletonHeroPlaceholder

/// Full-bleed hero placeholder shown before the real hero hydrates.
struct SkeletonHeroPlaceholder: View {
    var height: CGFloat = 340

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Rectangle()
                .fill(AmenTheme.Colors.shimmerBase)
                .creatorHubShimmer()

            VStack(alignment: .leading, spacing: 10) {
                SkeletonBlock(width: 200, height: 28, cornerRadius: 8)   // display name
                SkeletonBlock(width: 130, height: 16, cornerRadius: 6)   // role labels
                HStack(spacing: 10) {
                    ForEach(0..<4, id: \.self) { _ in
                        SkeletonBlock(width: 56, height: 36, cornerRadius: 18) // quick actions
                    }
                }
                .padding(.top, 6)
            }
            .padding(20)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipped()
        .accessibilityHidden(true)
        .accessibilityLabel("Loading creator profile")
    }
}

// MARK: - SkeletonCardRow

/// A horizontally laid-out skeleton card row (icon block + two text lines).
struct SkeletonCardRow: View {
    var showsLeadingThumb: Bool = true

    var body: some View {
        HStack(spacing: 12) {
            if showsLeadingThumb {
                SkeletonBlock(width: 64, height: 64, cornerRadius: 12)
            }
            VStack(alignment: .leading, spacing: 8) {
                SkeletonBlock(height: 16, cornerRadius: 6)
                SkeletonBlock(width: 180, height: 14, cornerRadius: 6)
                SkeletonBlock(width: 110, height: 12, cornerRadius: 6)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AmenTheme.Colors.surfaceCard)
        )
        .accessibilityHidden(true)
    }
}

// MARK: - SkeletonPillBar

/// Placeholder for the sticky module pill bar.
struct SkeletonPillBar: View {
    var pillCount: Int = 6

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(0..<pillCount, id: \.self) { _ in
                    SkeletonBlock(width: 84, height: 36, cornerRadius: 18)
                }
            }
            .padding(.horizontal, 16)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Skeletons") {
    ScrollView {
        VStack(spacing: 16) {
            SkeletonHeroPlaceholder()
            SkeletonPillBar()
            ForEach(0..<3, id: \.self) { _ in
                SkeletonCardRow()
                    .padding(.horizontal, 16)
            }
        }
    }
    .background(AmenTheme.Colors.backgroundPrimary)
}

#Preview("Skeletons – reduce motion") {
    ScrollView {
        VStack(spacing: 16) {
            SkeletonHeroPlaceholder()
            SkeletonPillBar()
        }
    }
    .environment(\.accessibilityReduceMotion, true)
}
#endif
