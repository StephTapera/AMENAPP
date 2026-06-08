// FindChurchGlassComponents.swift
// AMENAPP
//
// Liquid Glass UI components for the Find a Church experience.
// Uses GlassEffectModifiers and LiquidGlassMotion tokens.

import SwiftUI

// MARK: - Design Tokens

enum FindChurchDesignTokens {
    static let cardCornerRadius: CGFloat = 20
    static let headerBlur: CGFloat = 16
    static let filterPillRadius: CGFloat = 12
    static let sectionSpacing: CGFloat = 16
    static let cardPadding: CGFloat = 16
    static let headerHorizontalPadding: CGFloat = 20
    static let compressedHeaderHeight: CGFloat = 56
    static let expandedHeaderHeight: CGFloat = 120
}

// MARK: - Glass Church Search Field

/// A glass-styled search field for church discovery.
struct GlassChurchSearchField: View {
    @Binding var text: String
    var placeholder: String = "Search churches..."
    var onSubmit: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.systemScaled(16, weight: .medium))
                .foregroundStyle(.secondary)

            TextField(placeholder, text: $text)
                .font(.systemScaled(16, weight: .regular))
                .foregroundStyle(.primary)
                .focused($isFocused)
                .submitLabel(.search)
                .onSubmit(onSubmit)

            if !text.isEmpty {
                Button {
                    withAnimation(Motion.adaptive(.spring(response: 0.25, dampingFraction: 0.8))) {
                        text = ""
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.systemScaled(16))
                        .foregroundStyle(.secondary)
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding()
        .amenGlassEffect(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Glass Filter Pill

/// A glass-styled filter pill for denomination/sort/radius selection.
struct GlassFilterPill: View {
    let icon: String
    let label: String
    var isActive: Bool = false
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.systemScaled(12, weight: .medium))
                Text(label)
                    .font(.systemScaled(14, weight: .medium))
            }
            .foregroundStyle(isActive ? .white : .primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                if isActive {
                    Capsule()
                        .fill(Color.accentColor)
                } else {
                    Capsule()
                        .fill(.clear)
                        .amenGlassEffect(in: Capsule())
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

// MARK: - Glass Filter Pill (Menu variant)

/// A glass-styled filter pill that opens a menu.
struct GlassFilterMenuPill<MenuContent: View>: View {
    let icon: String
    let label: String
    @ViewBuilder let menuContent: () -> MenuContent

    var body: some View {
        Menu {
            menuContent()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.systemScaled(12, weight: .medium))
                Text(label)
                    .font(.systemScaled(14, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.systemScaled(10, weight: .semibold))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .amenGlassEffect(in: Capsule())
        }
    }
}

// MARK: - Glass AI Recommendation Module

/// Glass-wrapped expandable AI recommendations section.
struct GlassAIRecommendationModule<Content: View>: View {
    @Binding var isExpanded: Bool
    var isLoading: Bool
    var hasResults: Bool
    var onExpand: () -> Void
    @ViewBuilder let content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header button
            Button(action: onExpand) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.purple, .pink],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 40, height: 40)

                        Image(systemName: "sparkles")
                            .font(.systemScaled(18, weight: .semibold))
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("AI Recommendations")
                            .font(.systemScaled(16, weight: .semibold))
                            .foregroundStyle(.primary)

                        Text("Personalized matches for you")
                            .font(.systemScaled(13, weight: .regular))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.systemScaled(14, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(FindChurchDesignTokens.cardPadding)
                .amenGlassEffect(in: RoundedRectangle(cornerRadius: FindChurchDesignTokens.cardCornerRadius, style: .continuous)
                )
            }
            .buttonStyle(.plain)

            // Expanded content
            if isExpanded {
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding(.vertical, 32)
                } else if hasResults {
                    content()
                        .transition(.opacity.combined(with: .move(edge: .top)))
                } else {
                    Text("No AI recommendations available")
                        .font(.systemScaled(14, weight: .regular))
                        .foregroundStyle(.secondary)
                        .italic()
                        .padding(.vertical, 16)
                }
            }
        }
    }
}

// MARK: - Compressed Glass Header

/// A scroll-reactive compressed header that transitions from expanded to compact.
struct CompressedChurchHeader: View {
    @Binding var searchText: String
    let locationText: String
    let isLocationAuthorized: Bool
    var scrollOffset: CGFloat
    var onSearchSubmit: () -> Void
    var onFilterTap: () -> Void
    var onRefresh: (() -> Void)?
    var onBack: () -> Void
    var isMapMode: Bool
    var onMapToggle: () -> Void

    @FocusState private var isSearchFocused: Bool

    /// 0 = fully expanded, 1 = fully compressed
    private var compressionProgress: CGFloat {
        min(1, max(0, -scrollOffset / 80))
    }

    private var isCompressed: Bool {
        compressionProgress > 0.5
    }

    var body: some View {
        VStack(spacing: isCompressed ? 8 : 16) {
            // Title row — fades out when compressed
            if !isCompressed {
                HStack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.systemScaled(20, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Find Church")
                            .font(.systemScaled(32, weight: .bold, design: .default))
                            .foregroundStyle(.primary)

                        if isLocationAuthorized {
                            HStack(spacing: 6) {
                                Image(systemName: "location.fill")
                                    .font(.systemScaled(11, weight: .medium))
                                Text(locationText)
                                    .font(.systemScaled(13, weight: .medium))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    HStack(spacing: 12) {
                        if let refresh = onRefresh, isLocationAuthorized {
                            Button(action: refresh) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.systemScaled(18, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Button(action: onMapToggle) {
                            Image(systemName: isMapMode ? "list.bullet" : "map")
                                .font(.systemScaled(20, weight: .medium))
                                .foregroundStyle(.secondary)
                        }

                        Button(action: onFilterTap) {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                                .font(.systemScaled(24, weight: .regular))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .transition(.opacity)
            }

            // Search bar — always visible, compact when scrolled
            HStack(spacing: isCompressed ? 8 : 12) {
                if isCompressed {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.systemScaled(16, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                Image(systemName: "magnifyingglass")
                    .font(.systemScaled(isCompressed ? 14 : 16, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField("Search churches...", text: $searchText)
                    .font(.systemScaled(isCompressed ? 14 : 16, weight: .regular))
                    .foregroundStyle(.primary)
                    .focused($isSearchFocused)
                    .submitLabel(.search)
                    .onSubmit(onSearchSubmit)

                if !searchText.isEmpty {
                    Button {
                        withAnimation(Motion.adaptive(.spring(response: 0.25, dampingFraction: 0.8))) {
                            searchText = ""
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.systemScaled(isCompressed ? 14 : 16))
                            .foregroundStyle(.secondary)
                    }
                    .transition(.scale.combined(with: .opacity))
                }

                if isCompressed {
                    Button(action: onFilterTap) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.systemScaled(18, weight: .regular))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, isCompressed ? 12 : 16)
            .padding(.vertical, isCompressed ? 8 : 12)
            .amenGlassEffect(in: RoundedRectangle(cornerRadius: isCompressed ? 10 : 14, style: .continuous)
            )
        }
        .padding(.horizontal, FindChurchDesignTokens.headerHorizontalPadding)
        .padding(.top, isCompressed ? 8 : 12)
        .padding(.bottom, 8)
        .animation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.85)), value: isCompressed)
    }
}
