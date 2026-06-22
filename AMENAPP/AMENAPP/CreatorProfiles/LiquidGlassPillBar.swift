// LiquidGlassPillBar.swift
// AMEN — Creator Profiles (ministry hubs) — Wave 3
//
// Floating sticky module nav: Overview · Events · Teachings · Resources · Prayer ·
// Community · Courses · Ask AI. Backed by CreatorHubModuleKind.
//
// Matched-geometry selected indicator (caller supplies the namespace). Haptics on tap.
// Reduce-motion disables the geometry animation (instant selection swap instead).
//
// Conventions: translucent glass bar (single glass layer — pills sit ON the bar, the
// selected indicator is a fill, NOT a second glass layer → no glass-on-glass);
// AmenTheme.Colors.* tokens; Dynamic Type (text styles); VoiceOver: each pill labeled
// and selected state announced.

import SwiftUI

struct LiquidGlassPillBar: View {
    @Binding var selected: CreatorHubModuleKind
    /// Caller-owned namespace so the moving indicator animates across the bar.
    var indicatorNamespace: Namespace.ID
    /// Modules to display, in order. Defaults to the full set.
    var modules: [CreatorHubModuleKind] = CreatorHubModuleKind.allCases
    /// Optional focus callback (used by CreatorProfileView for next-module prefetch).
    var onFocus: (CreatorHubModuleKind) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(modules, id: \.self) { module in
                        pill(module)
                            .id(module)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            .background(barBackground)
            .onChange(of: selected) { _, newValue in
                onFocus(newValue)
                guard !reduceMotion else {
                    proxy.scrollTo(newValue, anchor: .center)
                    return
                }
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }

    // MARK: Pill

    private func pill(_ module: CreatorHubModuleKind) -> some View {
        let isSelected = module == selected
        return Button {
            select(module)
        } label: {
            Text(module.displayTitle)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? AmenTheme.Colors.textInverse : AmenTheme.Colors.textPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(AmenTheme.Colors.accentPrimary)
                            .matchedGeometryEffect(id: "pillSelection", in: indicatorNamespace)
                    } else {
                        Capsule()
                            .fill(AmenTheme.Colors.surfaceChip)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(module.displayTitle)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
        .accessibilityHint(isSelected ? "Selected" : "Shows the \(module.displayTitle) module")
    }

    // MARK: Bar background (single glass layer)

    private var barBackground: some View {
        Capsule()
            .fill(.ultraThinMaterial)
            .overlay(
                Capsule().strokeBorder(AmenTheme.Colors.glassStroke, lineWidth: 0.5)
            )
            .shadow(color: AmenTheme.Colors.shadowFloating, radius: 10, x: 0, y: 4)
    }

    // MARK: Selection + haptics

    private func select(_ module: CreatorHubModuleKind) {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()

        if reduceMotion {
            selected = module
        } else {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                selected = module
            }
        }
    }
}

// MARK: - Module display metadata

extension CreatorHubModuleKind: CaseIterable {
    public static var allCases: [CreatorHubModuleKind] {
        [.overview, .events, .teachings, .resources, .prayer, .community, .courses, .askAI]
    }

    var displayTitle: String {
        switch self {
        case .overview:  return "Overview"
        case .events:    return "Events"
        case .teachings: return "Teachings"
        case .resources: return "Resources"
        case .prayer:    return "Prayer"
        case .community: return "Community"
        case .courses:   return "Courses"
        case .askAI:     return "Ask AI"
        }
    }
}

// MARK: - Preview

#if DEBUG
private struct PillBarPreviewHost: View {
    @State private var selected: CreatorHubModuleKind = .overview
    @Namespace private var ns
    var body: some View {
        LiquidGlassPillBar(selected: $selected, indicatorNamespace: ns)
            .padding()
            .background(AmenTheme.Colors.backgroundPrimary)
    }
}

#Preview("Pill bar") { PillBarPreviewHost() }
#endif
