//
//  FeedViewModeSwitcher.swift
//  AMENAPP
//
//  Posts vs Photos & Videos toggle for profile feeds.
//  Liquid Glass segmented pill control.
//

import SwiftUI

enum FeedViewMode: String, CaseIterable {
    case posts = "Posts"
    case media = "Photos & Videos"

    var icon: String {
        switch self {
        case .posts: return "text.alignleft"
        case .media: return "photo.on.rectangle"
        }
    }
}

struct FeedViewModeSwitcher: View {
    @Binding var selectedMode: FeedViewMode
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 2) {
            ForEach(FeedViewMode.allCases, id: \.self) { mode in
                modeButton(mode)
            }
        }
        .padding(3)
        .background(outerBackground)
    }

    @ViewBuilder
    private func modeButton(_ mode: FeedViewMode) -> some View {
        let isActive = selectedMode == mode
        Button {
            withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.8))) {
                selectedMode = mode
            }
            if UIAccessibility.isReduceMotionEnabled == false {
                let haptic = UIImpactFeedbackGenerator(style: .light)
                haptic.impactOccurred()
            }
        } label: {
            modeLabel(mode, isActive: isActive)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode.rawValue)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    @ViewBuilder
    private func modeLabel(_ mode: FeedViewMode, isActive: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: mode.icon)
                .font(.systemScaled(13, weight: .semibold))
            Text(mode.rawValue)
                .font(.systemScaled(13, weight: isActive ? .bold : .medium))
        }
        .foregroundColor(isActive ? AmenTheme.Colors.iconPrimary : AmenTheme.Colors.iconSecondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(pillBackground(isActive: isActive))
    }

    @ViewBuilder
    private func pillBackground(isActive: Bool) -> some View {
        if isActive {
            Capsule()
                .fill(AmenTheme.Colors.surfaceCard)
                .overlay(
                    Capsule()
                        .strokeBorder(AmenTheme.Colors.borderSoft, lineWidth: 0.5)
                )
                .shadow(color: AmenTheme.Colors.shadowCard, radius: 8, y: 3)
        }
    }

    private var outerBackground: some View {
        Capsule()
            .fill(colorScheme == .dark ? AmenTheme.Colors.surfaceGlassDark : AmenTheme.Colors.backgroundSecondary)
            .overlay(
                Capsule()
                    .strokeBorder(AmenTheme.Colors.borderSoft, lineWidth: 0.5)
            )
    }
}
