// FindChurchGlassComponents.swift
// AMENAPP
//
// Liquid Glass UI components for the Find a Church experience.
// Uses GlassEffectModifiers and LiquidGlassMotion tokens.

import SwiftUI

// MARK: - Stubs for ChurchDiscovery Phase 2/3 types not yet migrated to Swift

enum ChurchDiscoverySheetState: Equatable {
    case collapsed, medium, expanded, searchFocused
}

enum ChurchDiscoveryIntent: String, CaseIterable, Hashable {
    case nearby, liveNow, deeperTeaching, youngAdults, kidsMinistry
    case prayer, accessibility, translation, quietSpace, saved, upcomingService, askBerean
}

struct BereanChurchSuggestion: Identifiable {
    let id: String
    let iconName: String
    let title: String
    let subtitle: String?
}

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

private struct FindChurchPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .brightness(configuration.isPressed ? -0.02 : 0)
            .animation(.interactiveSpring(response: 0.22, dampingFraction: 0.8), value: configuration.isPressed)
    }
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
        .glassEffect(.subtle, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Phase 2 Discovery Sheet

struct ChurchDiscoveryBottomSheet<Content: View>: View {
    @Binding var state: ChurchDiscoverySheetState
    var content: (_ currentHeight: CGFloat) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var dragOffset: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let height = resolvedHeight(for: state, in: geo.size.height)
            let currentOffset = max(geo.size.height - height + dragOffset, 0)

            content(height)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(sheetBackground)
                .clipShape(
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .stroke(Color.white.opacity(0.76), lineWidth: 0.9)
                )
                .shadow(color: Color.black.opacity(0.12), radius: 24, y: -2)
                .offset(y: currentOffset)
                .gesture(
                    DragGesture(minimumDistance: 5, coordinateSpace: .global)
                        .updating($dragOffset) { value, state, _ in
                            state = value.translation.height
                        }
                        .onEnded { value in
                            let proposedHeight = height - value.translation.height
                            let next = nearestState(for: proposedHeight, totalHeight: geo.size.height)
                            if reduceMotion {
                                state = next
                            } else {
                                withAnimation(Motion.adaptive(.interactiveSpring(response: 0.34, dampingFraction: 0.82))) {
                                    state = next
                                }
                            }
                        }
                )
                .animation(reduceMotion ? .none : Motion.adaptive(.interactiveSpring(response: 0.34, dampingFraction: 0.82)), value: state)
        }
    }

    private var sheetBackground: some View {
        ZStack {
            if UIAccessibility.isReduceTransparencyEnabled {
                Color.white
            } else {
                Color.white.opacity(0.72)
                Rectangle().fill(.ultraThinMaterial)
            }
        }
    }

    private func resolvedHeight(for state: ChurchDiscoverySheetState, in totalHeight: CGFloat) -> CGFloat {
        switch state {
        case .collapsed:
            return min(260, totalHeight * 0.3)
        case .medium:
            return totalHeight * 0.56
        case .expanded:
            return totalHeight * 0.82
        case .searchFocused:
            return totalHeight * 0.9
        }
    }

    private func nearestState(for proposedHeight: CGFloat, totalHeight: CGFloat) -> ChurchDiscoverySheetState {
        let candidates: [(ChurchDiscoverySheetState, CGFloat)] = [
            (.collapsed, resolvedHeight(for: .collapsed, in: totalHeight)),
            (.medium, resolvedHeight(for: .medium, in: totalHeight)),
            (.expanded, resolvedHeight(for: .expanded, in: totalHeight)),
            (.searchFocused, resolvedHeight(for: .searchFocused, in: totalHeight)),
        ]
        return candidates.min(by: { abs($0.1 - proposedHeight) < abs($1.1 - proposedHeight) })?.0 ?? .medium
    }
}

struct ChurchDiscoverySheetHandle: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 999, style: .continuous)
            .fill(Color.black.opacity(0.14))
            .frame(width: 40, height: 5)
            .padding(.top, 10)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }
}

struct ChurchSearchGlassCapsule: View {
    @Binding var text: String
    @Binding var isFocused: Bool
    var placeholder: String
    var onSubmit: () -> Void

    @FocusState private var localFocus: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: localFocus ? "magnifyingglass.circle.fill" : "magnifyingglass")
                .font(.systemScaled(localFocus ? 18 : 16, weight: .medium))
                .foregroundStyle(localFocus ? .blue : Color.black.opacity(0.42))

            TextField(placeholder, text: $text)
                .font(.systemScaled(16, weight: .regular))
                .foregroundStyle(Color.black.opacity(0.82))
                .submitLabel(.search)
                .focused($localFocus)
                .onSubmit(onSubmit)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.systemScaled(16))
                        .foregroundStyle(Color.black.opacity(0.36))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            Capsule(style: .continuous)
                .fill(UIAccessibility.isReduceTransparencyEnabled ? Color.white : Color.white.opacity(localFocus ? 0.94 : 0.76))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(localFocus ? Color.blue.opacity(0.35) : Color.white.opacity(0.82), lineWidth: localFocus ? 1.3 : 0.9)
                )
                .shadow(color: Color.black.opacity(localFocus ? 0.1 : 0.05), radius: localFocus ? 16 : 10, y: 6)
        )
        .onChange(of: localFocus) { _, newValue in
            isFocused = newValue
        }
        .onChange(of: isFocused) { _, newValue in
            localFocus = newValue
        }
    }
}

struct ChurchDiscoveryChipRow: View {
    let intents: [ChurchDiscoveryIntent]
    @Binding var selectedIntent: ChurchDiscoveryIntent?
    let onTap: (ChurchDiscoveryIntent) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(intents, id: \.self) { intent in
                    let isSelected = selectedIntent == intent
                    Button {
                        onTap(intent)
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: intent.iconName)
                                .font(.systemScaled(12, weight: .semibold))
                            Text(intent.displayTitle)
                                .font(.systemScaled(14, weight: isSelected ? .semibold : .medium))
                        }
                        .foregroundStyle(isSelected ? Color.blue : Color.black.opacity(0.72))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            Capsule(style: .continuous)
                                .fill(isSelected ? Color.blue.opacity(0.1) : Color.white.opacity(0.66))
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(isSelected ? Color.blue.opacity(0.22) : Color.black.opacity(0.06), lineWidth: 0.9)
                                )
                        )
                    }
                    .buttonStyle(FindChurchPressStyle())
                }
            }
            .padding(.horizontal, 20)
        }
    }
}

struct ChurchRecentsSection: View {
    let searches: [String]
    let onTap: (String) -> Void

    var body: some View {
        DiscoverySection(title: "Recents") {
            if searches.isEmpty {
                Text("Recent church searches will appear here.")
                    .font(.systemScaled(14, weight: .medium))
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(searches, id: \.self) { item in
                        Button {
                            onTap(item)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .foregroundStyle(Color.black.opacity(0.45))
                                Text(item)
                                    .font(.systemScaled(15, weight: .medium))
                                    .foregroundStyle(Color.black.opacity(0.82))
                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(Color.white.opacity(0.56), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(FindChurchPressStyle())
                    }
                }
            }
        }
    }
}

struct BereanSuggestionsSection: View {
    let suggestions: [BereanChurchSuggestion]
    let onTap: (BereanChurchSuggestion) -> Void

    var body: some View {
        DiscoverySection(title: "Berean Suggestions") {
            VStack(spacing: 12) {
                ForEach(suggestions) { suggestion in
                    Button {
                        onTap(suggestion)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: suggestion.iconName)
                                .font(.systemScaled(16, weight: .semibold))
                                .foregroundStyle(Color.black.opacity(0.76))
                                .frame(width: 34, height: 34)
                                .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(suggestion.title)
                                    .font(.systemScaled(15, weight: .semibold))
                                    .foregroundStyle(Color.black.opacity(0.84))
                                if let subtitle = suggestion.subtitle {
                                    Text(subtitle)
                                        .font(.systemScaled(13, weight: .medium))
                                        .foregroundStyle(Color.black.opacity(0.54))
                                        .multilineTextAlignment(.leading)
                                }
                            }
                            Spacer()
                        }
                        .padding(14)
                        .background(Color.white.opacity(0.64), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(FindChurchPressStyle())
                }
            }
        }
    }
}

struct SuggestedChurchesSection: View {
    let churches: [Church]
    let onSelect: (Church) -> Void

    var body: some View {
        DiscoverySection(title: "Suggested Churches") {
            VStack(spacing: 10) {
                ForEach(churches.prefix(3)) { church in
                    Button {
                        onSelect(church)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "building.columns.fill")
                                .foregroundStyle(Color.black.opacity(0.68))
                                .frame(width: 34, height: 34)
                                .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(church.name)
                                    .font(.systemScaled(15, weight: .semibold))
                                    .foregroundStyle(Color.black.opacity(0.84))
                                Text("\(church.denomination) • \(church.distance)")
                                    .font(.systemScaled(13, weight: .medium))
                                    .foregroundStyle(Color.black.opacity(0.54))
                            }
                            Spacer()
                        }
                        .padding(14)
                        .background(Color.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(FindChurchPressStyle())
                }
            }
        }
    }
}

struct NearbyChurchesSection: View {
    let churches: [Church]
    let onSelect: (Church) -> Void

    var body: some View {
        DiscoverySection(title: "Nearby Churches") {
            VStack(spacing: 10) {
                ForEach(churches.prefix(3)) { church in
                    Button {
                        onSelect(church)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(church.name)
                                    .font(.systemScaled(15, weight: .semibold))
                                    .foregroundStyle(Color.black.opacity(0.84))
                                Text(church.distance)
                                    .font(.systemScaled(13, weight: .medium))
                                    .foregroundStyle(Color.black.opacity(0.54))
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .foregroundStyle(Color.black.opacity(0.35))
                        }
                        .padding(14)
                        .background(Color.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(FindChurchPressStyle())
                }
            }
        }
    }
}

private struct DiscoverySection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.systemScaled(14, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.48))
            content
        }
        .padding(.horizontal, 20)
    }
}

private extension ChurchDiscoveryIntent {
    var displayTitle: String {
        switch self {
        case .nearby: return "Nearby"
        case .liveNow: return "Live Now"
        case .deeperTeaching: return "Deeper Teaching"
        case .youngAdults: return "Young Adults"
        case .kidsMinistry: return "Kids Ministry"
        case .prayer: return "Prayer"
        case .accessibility: return "Accessible"
        case .translation: return "Translation"
        case .quietSpace: return "Quiet Space"
        case .saved: return "Saved"
        case .upcomingService: return "Service Soon"
        case .askBerean: return "Ask Berean"
        }
    }

    var iconName: String {
        switch self {
        case .nearby: return "location.fill"
        case .liveNow: return "dot.radiowaves.left.and.right"
        case .deeperTeaching: return "book.closed"
        case .youngAdults: return "person.3.fill"
        case .kidsMinistry: return "figure.and.child.holdinghands"
        case .prayer: return "hands.sparkles"
        case .accessibility: return "figure.roll"
        case .translation: return "captions.bubble"
        case .quietSpace: return "moon.stars"
        case .saved: return "bookmark.fill"
        case .upcomingService: return "calendar"
        case .askBerean: return "sparkles"
        }
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
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.systemScaled(12, weight: .medium))
                Text(label)
                    .font(.systemScaled(14, weight: isActive ? .semibold : .medium))
            }
            .foregroundStyle(isActive ? .white : .primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                if isActive {
                    Capsule()
                        .fill(Color.accentColor)
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.8)
                        )
                        .shadow(color: Color.accentColor.opacity(0.22), radius: 8, y: 3)
                } else {
                    Capsule()
                        .fill(Color.white.opacity(0.72))
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.black.opacity(0.07), lineWidth: 0.8)
                        )
                        .glassEffect(.subtle, in: Capsule())
                }
            }
        }
        .buttonStyle(FCPressButtonStyle())
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .animation(
            reduceMotion ? .none : .spring(response: 0.22, dampingFraction: 0.78),
            value: isActive
        )
    }
}

/// Internal tactile button style for glass components — press compresses + dims.
private struct FCPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .brightness(configuration.isPressed ? -0.03 : 0)
            .animation(.interactiveSpring(response: 0.20, dampingFraction: 0.76), value: configuration.isPressed)
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
            .glassEffect(.subtle, in: Capsule())
        }
    }
}

// MARK: - Glass AI Recommendation Module

/// Glass-wrapped expandable AI recommendations section with icon breathing and staggered reveal.
struct GlassAIRecommendationModule<Content: View>: View {
    @Binding var isExpanded: Bool
    var isLoading: Bool
    var hasResults: Bool
    var onExpand: () -> Void
    @ViewBuilder let content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var iconBreathing = false
    @State private var sheenPhase: CGFloat = 0
    @State private var contentVisible = false

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
                            .shadow(color: .purple.opacity(0.18), radius: 8, y: 3)

                        Image(systemName: "sparkles")
                            .font(.systemScaled(18, weight: .semibold))
                            .foregroundStyle(.white)
                            .scaleEffect(iconBreathing ? 1.10 : 1.0)
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
                        .rotationEffect(.degrees(isExpanded ? 0 : 0))
                }
                .padding(FindChurchDesignTokens.cardPadding)
                .background(
                    RoundedRectangle(cornerRadius: FindChurchDesignTokens.cardCornerRadius, style: .continuous)
                        .fill(Color.white.opacity(isExpanded ? 0.92 : 0.82))
                        .overlay(
                            RoundedRectangle(cornerRadius: FindChurchDesignTokens.cardCornerRadius, style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [Color.purple.opacity(0.22), Color.white.opacity(0.60)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: isExpanded ? 1.0 : 0.8
                                )
                        )
                        .shadow(color: Color.purple.opacity(isExpanded ? 0.10 : 0.05), radius: isExpanded ? 22 : 14, y: isExpanded ? 8 : 4)
                )
                .glassEffect(
                    GlassEffectStyle.regular.tint(.purple.opacity(isExpanded ? 0.08 : 0.04)),
                    in: RoundedRectangle(cornerRadius: FindChurchDesignTokens.cardCornerRadius, style: .continuous)
                )
            }
            .buttonStyle(FCPressButtonStyle())

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
                        .opacity(contentVisible ? 1 : 0)
                        .offset(y: contentVisible ? 0 : 8)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                        .onAppear {
                            withAnimation(reduceMotion ? .none : .spring(response: 0.38, dampingFraction: 0.82).delay(0.05)) {
                                contentVisible = true
                            }
                        }
                        .onDisappear { contentVisible = false }
                } else {
                    Text("No AI recommendations available")
                        .font(.systemScaled(14, weight: .regular))
                        .foregroundStyle(.secondary)
                        .italic()
                        .padding(.vertical, 16)
                }
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                iconBreathing = true
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
            .glassEffect(
                isCompressed ? .prominent : .subtle,
                in: RoundedRectangle(cornerRadius: isCompressed ? 10 : 14, style: .continuous)
            )
        }
        .padding(.horizontal, FindChurchDesignTokens.headerHorizontalPadding)
        .padding(.top, isCompressed ? 8 : 12)
        .padding(.bottom, 8)
        .animation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.85)), value: isCompressed)
    }
}

// MARK: - Animated Stats Row

/// Premium glass stats summary with count-up animation on first appear.
struct AnimatedChurchStatsRow: View {
    let count: Int
    let nearest: String

    @State private var displayCount = 0
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(appeared ? displayCount : 0)")
                    .font(.systemScaled(30, weight: .bold))
                    .foregroundStyle(Color(red: 0.16, green: 0.16, blue: 0.16))
                Text("Churches nearby")
                    .font(.systemScaled(12, weight: .regular))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.black.opacity(0.03), Color.black.opacity(0.09), Color.black.opacity(0.03)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: 1, height: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text(nearest.replacingOccurrences(of: " away", with: ""))
                    .font(.systemScaled(22, weight: .bold))
                    .foregroundStyle(Color(red: 0.16, green: 0.16, blue: 0.16))
                Text("Nearest match")
                    .font(.systemScaled(12, weight: .regular))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 20)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.88))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.90), Color.black.opacity(0.06)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.9
                        )
                )
                .shadow(color: Color.black.opacity(0.07), radius: 18, y: 6)
        )
        .glassEffect(.subtle, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .offset(y: appeared ? 0 : 6)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            guard !appeared else { return }
            withAnimation(reduceMotion ? .none : .spring(response: 0.48, dampingFraction: 0.82)) {
                appeared = true
            }
            animateCount(to: count)
        }
        .onChange(of: count) { _, newCount in
            animateCount(to: newCount)
        }
    }

    private func animateCount(to target: Int) {
        guard !reduceMotion else { displayCount = target; return }
        let steps = min(target, 24)
        for i in 1...max(1, steps) {
            let delay = Double(i) * (0.55 / Double(steps))
            Task {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.06)) {
                        displayCount = Int((Double(target) * Double(i) / Double(steps)).rounded())
                    }
                }
            }
        }
    }
}

// MARK: - Church Notes + PostCard State-Aware Action Block

/// State-aware action block showing Church Notes and PostCard actions inside an expanded church card.
/// Reads from ChurchInteractionService to show "Continue" vs "Create" states.
struct ChurchNotePostCardActionBlock: View {
    let churchId: String
    let churchName: String

    var onCreateNote: () -> Void
    var onOpenPostCard: () -> Void

    @ObservedObject private var interactions = ChurchInteractionService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private var interaction: ChurchInteraction? {
        interactions.interaction(for: churchId)
    }

    private var hasNote: Bool {
        interaction?.noteIds.isEmpty == false
    }

    private var hasPostCard: Bool {
        interaction?.postCardDraftIds.isEmpty == false
    }

    var body: some View {
        VStack(spacing: 10) {
            // Church Notes action
            Button(action: onCreateNote) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(hasNote ? Color.indigo.opacity(0.14) : Color(.systemGray6))
                            .frame(width: 36, height: 36)
                        Image(systemName: hasNote ? "note.text" : "note.text.badge.plus")
                            .font(.systemScaled(15, weight: .medium))
                            .foregroundStyle(hasNote ? Color.indigo : Color.secondary)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(hasNote ? "Continue Church Note" : "Send to Church Notes")
                            .font(.systemScaled(14, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text(hasNote ? "Your note is in progress" : "Capture sermon & reflections")
                            .font(.systemScaled(12))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: hasNote ? "arrow.right.circle.fill" : "chevron.right")
                        .font(.systemScaled(14, weight: hasNote ? .semibold : .regular))
                        .foregroundStyle(hasNote ? Color.indigo : Color(.systemGray3))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(hasNote ? Color.indigo.opacity(0.07) : Color.white.opacity(0.72))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(
                                    hasNote ? Color.indigo.opacity(0.22) : Color.black.opacity(0.06),
                                    lineWidth: 0.9
                                )
                        )
                )
            }
            .buttonStyle(FCPressButtonStyle())
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 6)

            // PostCard action
            Button(action: onOpenPostCard) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(hasPostCard ? Color.pink.opacity(0.14) : Color(.systemGray6))
                            .frame(width: 36, height: 36)
                        Image(systemName: hasPostCard ? "envelope.fill" : "envelope.badge.person.crop")
                            .font(.systemScaled(14, weight: .medium))
                            .foregroundStyle(hasPostCard ? Color.pink : Color.secondary)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(hasPostCard ? "Open PostCard Draft" : "Prepare PostCard")
                            .font(.systemScaled(14, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text(hasPostCard ? "Your draft is waiting" : "Invite a friend or share gratitude")
                            .font(.systemScaled(12))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: hasPostCard ? "arrow.right.circle.fill" : "chevron.right")
                        .font(.systemScaled(14, weight: hasPostCard ? .semibold : .regular))
                        .foregroundStyle(hasPostCard ? Color.pink : Color(.systemGray3))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(hasPostCard ? Color.pink.opacity(0.07) : Color.white.opacity(0.72))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(
                                    hasPostCard ? Color.pink.opacity(0.22) : Color.black.opacity(0.06),
                                    lineWidth: 0.9
                                )
                        )
                )
            }
            .buttonStyle(FCPressButtonStyle())
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 6)
        }
        .onAppear {
            guard !appeared else { return }
            withAnimation(reduceMotion ? .none : .spring(response: 0.42, dampingFraction: 0.84).delay(0.12)) {
                appeared = true
            }
        }
        .onDisappear { appeared = false }
    }
}

// MARK: - Apple Maps-style Church Result Card

/// Full-width result card matching the Apple Maps POI card pattern.
/// Shows church icon, name + distance + address + next service time + optional rating,
/// with a trailing Directions button that opens Apple Maps driving directions.
///
/// A5 augmentation (2026-05-31):
///   - Optional rating star row (shown when rating > 0)
///   - Directions hand-off via maps:// URL (driving mode, https fallback)
///   - Full VoiceOver label: name + distance + address + service time + rating
///   - 0.97 scale pressed spring feedback via FCPressButtonStyle
///   - accessibilityReduceMotion guard on selection highlight animation
struct ChurchAppleMapResultCard: View {
    let church: Church
    var isSelected: Bool = false
    var isLive: Bool = false
    /// Optional star rating 0–5. Pass nil or 0 to hide the rating row.
    var rating: Double? = nil
    let onTap: () -> Void
    /// Tap handler for the Directions button.
    /// When nil the built-in Maps URL hand-off fires automatically.
    var onDirections: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var voiceOverLabel: String {
        var parts: [String] = [church.name, church.distance, church.address]
        parts.append(isLive ? "Service live now" : church.serviceTime)
        if let r = rating, r > 0 { parts.append(String(format: "%.1f stars", r)) }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Church icon badge
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(isSelected ? Color.amenGold.opacity(0.18) : Color.amenGold.opacity(0.10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .strokeBorder(Color.amenGold.opacity(isSelected ? 0.35 : 0.18), lineWidth: 0.9)
                        )
                    Image(systemName: "building.columns.fill")
                        .font(.systemScaled(17, weight: .semibold))
                        .foregroundStyle(Color.amenGold)
                }
                .frame(width: 44, height: 44)

                // Name + distance/address + service time + optional rating
                VStack(alignment: .leading, spacing: 3) {
                    Text(church.name)
                        .font(.systemScaled(15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text("\(church.distance) · \(church.address)")
                        .font(.systemScaled(12, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if isLive {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 6, height: 6)
                            Text("Service live now")
                                .font(.systemScaled(12, weight: .medium))
                                .foregroundStyle(Color.red)
                        }
                    } else {
                        Text(church.serviceTime)
                            .font(.systemScaled(12, weight: .regular))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    // Rating stars — only shown when rating > 0
                    if let r = rating, r > 0 {
                        ChurchResultCardRatingStars(rating: r)
                            .padding(.top, 1)
                    }
                }

                Spacer(minLength: 6)

                // Directions button — Apple Maps driving hand-off
                Button {
                    if let custom = onDirections {
                        custom()
                    } else {
                        ChurchAppleMapResultCard.openMapsDirections(
                            latitude: church.latitude,
                            longitude: church.longitude
                        )
                    }
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                            .font(.systemScaled(22))
                            .foregroundStyle(Color.amenBlue)
                        Text("Go")
                            .font(.systemScaled(10, weight: .semibold))
                            .foregroundStyle(Color.amenBlue)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Directions to \(church.name)")
                .accessibilityHint("Opens Apple Maps with driving directions")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(FCPressButtonStyle())
        .background(isSelected ? Color.amenGold.opacity(0.04) : Color.clear)
        .animation(
            reduceMotion ? .none : .spring(response: 0.22, dampingFraction: 0.8),
            value: isSelected
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(voiceOverLabel)
        .accessibilityHint("Double-tap to focus on map")
    }
}

// MARK: - Map Sheet Filter Bar

/// Horizontal filter chip row for the Apple Maps-style bottom sheet.
/// Chips: Open Now · Denomination ⌄ · Sort by Best ⌄
struct ChurchMapSheetFilterBar: View {
    @Binding var showOpenNowOnly: Bool
    @Binding var localDenomination: String?
    @Binding var sortByDistance: Bool

    private let denominations = ["Non-Denominational", "Baptist", "Methodist", "Pentecostal", "Presbyterian", "Catholic", "Episcopal", "Lutheran"]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                GlassFilterPill(
                    icon: "clock",
                    label: "Open Now",
                    isActive: showOpenNowOnly
                ) {
                    showOpenNowOnly.toggle()
                }
                .accessibilityHint(showOpenNowOnly ? "Currently filtering to open churches" : "Filter to currently open churches")

                GlassFilterMenuPill(
                    icon: "building.columns",
                    label: localDenomination ?? "Denomination"
                ) {
                    Button("All Denominations") { localDenomination = nil }
                    Divider()
                    ForEach(denominations, id: \.self) { denom in
                        Button(denom) { localDenomination = denom }
                    }
                }

                GlassFilterMenuPill(
                    icon: "arrow.up.arrow.down",
                    label: sortByDistance ? "Nearest" : "Sort by Best"
                ) {
                    Button("Best Match") { sortByDistance = false }
                    Button("Nearest First") { sortByDistance = true }
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - Rating Stars (A5 internal helper)

/// Compact 0–5 star row for church result cards.
/// Displays filled, half, and empty stars using SF Symbols.
private struct ChurchResultCardRatingStars: View {
    let rating: Double   // 0.0 – 5.0

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { index in
                Image(systemName: starSymbol(for: index))
                    .font(.systemScaled(10, weight: .medium))
                    .foregroundStyle(Color.amenGold)
            }
            Text(String(format: "%.1f", rating))
                .font(.systemScaled(10, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private func starSymbol(for index: Int) -> String {
        let threshold = rating - Double(index)
        if threshold >= 0.75 { return "star.fill" }
        if threshold >= 0.25 { return "star.leadinghalf.filled" }
        return "star"
    }
}

// MARK: - Find Church Load State (A5)

/// Driving enum for the bottom sheet content area.
/// Passed to FindChurchSheetContent to render the correct state UI.
enum FindChurchLoadState: Equatable {
    case loading
    case results([Church])   // non-empty result set
    case empty               // fetch succeeded but no results
    case error(String)       // fetch failed — carries user-facing message
    case offline             // device has no network
}

// MARK: - Find Church Sheet Content (A5)

/// Stateful interior of the church result bottom sheet.
/// Switches on FindChurchLoadState to show distinct loading / results / empty / error / offline UIs.
/// A4 owns the filter chip row above this view — do NOT add filter chips here.
struct FindChurchSheetContent: View {
    let state: FindChurchLoadState
    var onSelectChurch: (Church) -> Void = { _ in }
    var onRetry: () -> Void = {}
    /// Optional limit for the displayed card count (used in .medium sheet detent: first 5 only).
    var resultLimit: Int? = nil

    var body: some View {
        Group {
            switch state {
            case .loading:
                loadingView
            case .results(let churches):
                let displayed = resultLimit.map { Array(churches.prefix($0)) } ?? churches
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(displayed) { church in
                            ChurchAppleMapResultCard(
                                church: church,
                                isSelected: false,
                                isLive: false,
                                onTap: { onSelectChurch(church) },
                                onDirections: {
                                    let mapsURL = URL(
                                        string: "maps://?daddr=\(church.latitude),\(church.longitude)&dirflg=d"
                                    )!
                                    if UIApplication.shared.canOpenURL(mapsURL) {
                                        UIApplication.shared.open(mapsURL)
                                    } else {
                                        UIApplication.shared.open(
                                            URL(string: "https://maps.apple.com/?daddr=\(church.latitude),\(church.longitude)&dirflg=d")!
                                        )
                                    }
                                }
                            )
                            if church.id != displayed.last?.id {
                                Divider().padding(.leading, 74)
                            }
                        }
                    }
                }
            case .empty:
                emptyView
            case .error(let message):
                errorView(message: message)
            case .offline:
                offlineView
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: State views

    private var loadingView: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
                .scaleEffect(1.2)
                .tint(Color.amenGold)
            Text("Searching nearby...")
                .font(.systemScaled(14, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Searching for nearby churches")
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "xmark.circle")
                .font(.systemScaled(36, weight: .light))
                .foregroundStyle(.secondary)
            Text("No churches found")
                .font(.systemScaled(15, weight: .semibold))
                .foregroundStyle(.primary)
            Text("Try widening your search or adjusting your filters.")
                .font(.systemScaled(13, weight: .regular))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No churches found. Try widening your search or adjusting your filters.")
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.systemScaled(36, weight: .light))
                .foregroundStyle(Color.amenGold)
            Text(message)
                .font(.systemScaled(14, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button(action: onRetry) {
                Text("Retry")
                    .font(.systemScaled(14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.amenGold))
            }
            .buttonStyle(FCPressButtonStyle())
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .accessibilityElement(children: .contain)
    }

    private var offlineView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "wifi.slash")
                .font(.systemScaled(36, weight: .light))
                .foregroundStyle(.secondary)
            Text("You're offline")
                .font(.systemScaled(15, weight: .semibold))
                .foregroundStyle(.primary)
            Text("Check your connection and try again.")
                .font(.systemScaled(13, weight: .regular))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("You're offline. Check your connection and try again.")
    }
}

// MARK: - Find Church Result Sheet (A5)

/// Draggable bottom sheet that shows the church result list.
///
/// Three detent positions controlled by sheetState:
///   .collapsed      — "N churches nearby" summary pill; tap expands to .medium
///   .medium         — filter chip row (A4 injects via filterContent) + first 5 result cards
///   .expanded       — filter chip row + full scrollable result list
///   .searchFocused  — same as expanded
///
/// Usage:
///   FindChurchResultSheet(state: $sheetState, loadState: vm.loadState,
///       onSelectChurch: { … }, onRetry: { … }) { ChurchMapSheetFilterBar(…) }
struct FindChurchResultSheet<FilterContent: View>: View {
    @Binding var state: ChurchDiscoverySheetState
    var loadState: FindChurchLoadState
    var onSelectChurch: (Church) -> Void
    var onRetry: () -> Void
    @ViewBuilder var filterContent: () -> FilterContent

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var nearestDistance: String {
        if case .results(let churches) = loadState {
            return churches.min(by: { $0.distanceValue < $1.distanceValue })?.distance ?? ""
        }
        return ""
    }

    var body: some View {
        ChurchDiscoveryBottomSheet(state: $state) { _ in
            VStack(spacing: 0) {
                ChurchDiscoverySheetHandle()
                switch state {
                case .collapsed:
                    collapsedPill
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                        .onTapGesture {
                            withAnimation(
                                Motion.adaptive(.interactiveSpring(response: 0.32, dampingFraction: 0.82))
                            ) { state = .medium }
                        }
                case .medium:
                    filterContent().padding(.bottom, 10)
                    Divider()
                    FindChurchSheetContent(
                        state: loadState,
                        onSelectChurch: onSelectChurch,
                        onRetry: onRetry,
                        resultLimit: 5
                    )
                case .expanded, .searchFocused:
                    filterContent().padding(.bottom, 10)
                    Divider()
                    FindChurchSheetContent(
                        state: loadState,
                        onSelectChurch: onSelectChurch,
                        onRetry: onRetry,
                        resultLimit: nil
                    )
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Church search results")
    }

    @ViewBuilder
    private var collapsedPill: some View {
        HStack(spacing: 10) {
            Image(systemName: "building.columns.fill")
                .font(.systemScaled(14, weight: .semibold))
                .foregroundStyle(Color.amenGold)
            Group {
                switch loadState {
                case .loading:
                    Text("Searching...")
                        .font(.systemScaled(14, weight: .semibold))
                        .foregroundStyle(.primary)
                case .results(let churches):
                    HStack(spacing: 4) {
                        Text("\(churches.count) church\(churches.count == 1 ? "" : "es") nearby")
                            .font(.systemScaled(14, weight: .semibold))
                            .foregroundStyle(.primary)
                        if !nearestDistance.isEmpty {
                            Text("· nearest \(nearestDistance)")
                                .font(.systemScaled(13, weight: .regular))
                                .foregroundStyle(.secondary)
                        }
                    }
                case .empty:
                    Text("No churches found")
                        .font(.systemScaled(14, weight: .semibold))
                        .foregroundStyle(.secondary)
                case .error:
                    Text("Couldn't load results")
                        .font(.systemScaled(14, weight: .semibold))
                        .foregroundStyle(.secondary)
                case .offline:
                    Text("Offline")
                        .font(.systemScaled(14, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.up")
                .font(.systemScaled(12, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .amenGlass(.thin, cornerRadius: 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(collapsedPillA11yLabel)
        .accessibilityHint("Double-tap to expand church list")
        .accessibilityAddTraits(.isButton)
    }

    private var collapsedPillA11yLabel: String {
        switch loadState {
        case .loading: return "Searching for churches"
        case .results(let churches):
            let suffix = nearestDistance.isEmpty ? "" : ", nearest \(nearestDistance)"
            return "\(churches.count) church\(churches.count == 1 ? "" : "es") nearby\(suffix)"
        case .empty: return "No churches found"
        case .error: return "Could not load results"
        case .offline: return "Offline, no results available"
        }
    }
}

// MARK: - ChurchAppleMapResultCard augmentation (A5): rating + Maps hand-off
// The existing ChurchAppleMapResultCard defined above already handles the Directions
// tap via onDirections closure. The augmented card below adds an optional rating
// parameter and a built-in Maps hand-off so callers can use either variant.

extension ChurchAppleMapResultCard {

    /// Returns the canonical VoiceOver label combining all visible metadata.
    internal static func a11yLabel(for church: Church, isLive: Bool, rating: Double?) -> String {
        var parts: [String] = [church.name, church.distance, church.address]
        parts.append(isLive ? "Service live now" : church.serviceTime)
        if let r = rating, r > 0 {
            parts.append(String(format: "%.1f stars", r))
        }
        return parts.joined(separator: ", ")
    }

    /// Opens Apple Maps with driving directions to the church coordinate.
    internal static func openMapsDirections(latitude: Double, longitude: Double) {
        let mapsURL = URL(string: "maps://?daddr=\(latitude),\(longitude)&dirflg=d")!
        if UIApplication.shared.canOpenURL(mapsURL) {
            UIApplication.shared.open(mapsURL)
        } else {
            let fallback = URL(string: "https://maps.apple.com/?daddr=\(latitude),\(longitude)&dirflg=d")!
            UIApplication.shared.open(fallback)
        }
    }
}
