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
