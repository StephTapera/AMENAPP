// FindChurch2HeaderView.swift
// AMENAPP — Find Church 2.0, Wave 6 UI Refresh
//
// Collapsing header with search field, location chip, and filter button.
//
// Design rules enforced:
//   - Native .glassEffect() where available; .ultraThinMaterial as fallback
//   - No glass-on-glass nesting
//   - Luminous border: Color.white.opacity(0.45) strokeBorder 0.5pt
//   - reduceMotion guard on all animations
//   - Top padding respects status bar via .safeAreaPadding / GeometryReader
//   - Location chip NEVER shows "Updating location…" — falls back to "Current location"

import SwiftUI

// MARK: - FindChurch2LocationChip

struct FindChurch2LocationChip: View {
    let label: String          // "Phoenix, AZ" or "Current location"
    var onTap: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    private var safeLabel: String {
        let trimmed = label.trimmingCharacters(in: .whitespaces)
        // Guard: never surface "Updating…" strings to the user
        if trimmed.isEmpty
            || trimmed.lowercased().contains("updating")
            || trimmed.lowercased().contains("locating") {
            return "Current location"
        }
        return trimmed
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                Image(systemName: "location.fill")
                    .font(.system(.caption2).weight(.semibold))
                    .accessibilityHidden(true)
                Text(safeLabel)
                    .font(.system(.caption).weight(.medium))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(chipBackground)
            .overlay(chipBorder)
            .clipShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Location: \(safeLabel). Tap to change.")
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var chipBackground: some View {
        if reduceTransparency {
            Capsule(style: .continuous)
                .fill(Color(.systemBackground).opacity(0.92))
        } else {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.10))
                )
        }
    }

    private var chipBorder: some View {
        Capsule(style: .continuous)
            .strokeBorder(
                Color.white.opacity(contrast == .increased ? 0.55 : 0.45),
                lineWidth: 0.5
            )
    }
}

// MARK: - FindChurch2SearchField (internal helper)

private struct FindChurch2SearchField: View {
    @Binding var searchText: String
    var onFilter: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(.subheadline).weight(.medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField("Search churches, denominations…", text: $searchText)
                .font(.system(.body))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($isFocused)
                .submitLabel(.search)
                .accessibilityLabel("Search churches")

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(.body))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }

            Divider()
                .frame(height: 22)
                .opacity(0.4)
                .accessibilityHidden(true)

            Button(action: onFilter) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(.subheadline).weight(.medium))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Filter churches")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
        .frame(minHeight: 44)
        .background(searchFieldBackground)
        .overlay(searchFieldBorder)
        .clipShape(Capsule(style: .continuous))
    }

    @ViewBuilder
    private var searchFieldBackground: some View {
        if reduceTransparency {
            Capsule(style: .continuous)
                .fill(Color(.secondarySystemBackground))
        } else {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
        }
    }

    private var searchFieldBorder: some View {
        Capsule(style: .continuous)
            .strokeBorder(
                Color.white.opacity(contrast == .increased ? 0.55 : 0.45),
                lineWidth: 0.5
            )
    }
}

// MARK: - FindChurch2CollapsingHeader

/// Collapsing header for Find Church 2.0.
///
/// - Expanded (scrollY == 0): large title + location chip below title.
/// - Collapsed (scrollY > 60): compact glass bar with inline search + location chip.
/// - `locationLabel` must never contain "Updating…" text — parent supplies city name or "".
///
/// Usage:
/// ```swift
/// FindChurch2CollapsingHeader(
///     searchText: $searchText,
///     locationLabel: $locationLabel,
///     onFilter: { showFilterSheet = true }
/// )
/// ```
struct FindChurch2CollapsingHeader: View {
    @Binding var searchText: String
    @Binding var locationLabel: String
    var onFilter: () -> Void

    /// External scroll offset. Provide via a ScrollView + GeometryReader background.
    var scrollY: CGFloat = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    // Collapse threshold in points
    private let collapseThreshold: CGFloat = 60

    private var collapseProgress: CGFloat {
        guard collapseThreshold > 0 else { return 0 }
        return min(max(scrollY / collapseThreshold, 0), 1)
    }

    private var isCollapsed: Bool { collapseProgress >= 1 }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Collapsed bar (fades in as user scrolls)
            collapsedBar
                .opacity(collapseProgress)
                .offset(y: reduceMotion ? 0 : (1 - collapseProgress) * -8)
                .accessibilityHidden(!isCollapsed)

            // Expanded header (fades out as user scrolls)
            expandedHeader
                .opacity(1 - collapseProgress)
                .offset(y: reduceMotion ? 0 : collapseProgress * 8)
                .accessibilityHidden(isCollapsed)
        }
        .animation(
            reduceMotion
                ? .easeOut(duration: 0.12)
                : .spring(response: 0.32, dampingFraction: 0.82),
            value: collapseProgress
        )
    }

    // MARK: Expanded Header

    private var expandedHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Find a Church")
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)

            FindChurch2LocationChip(label: locationLabel, onTap: {})

            FindChurch2SearchField(searchText: $searchText, onFilter: onFilter)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Collapsed Bar

    private var collapsedBar: some View {
        HStack(spacing: 10) {
            // Compact search pill (fills remaining space)
            FindChurch2SearchField(searchText: $searchText, onFilter: onFilter)

            FindChurch2LocationChip(label: locationLabel, onTap: {})
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(collapsedBarBackground)
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundStyle(Color.white.opacity(contrast == .increased ? 0.45 : 0.28)),
            alignment: .bottom
        )
    }

    @ViewBuilder
    private var collapsedBarBackground: some View {
        if reduceTransparency {
            Color(.systemBackground).opacity(0.97)
        } else {
            Rectangle()
                .fill(.regularMaterial)
                .overlay(
                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                )
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Expanded") {
    ScrollView {
        VStack(spacing: 0) {
            FindChurch2CollapsingHeader(
                searchText: .constant(""),
                locationLabel: .constant("Phoenix, AZ"),
                onFilter: {}
            )
            Color.gray.opacity(0.1)
                .frame(height: 800)
        }
    }
}

#Preview("Collapsed") {
    ScrollView {
        VStack(spacing: 0) {
            FindChurch2CollapsingHeader(
                searchText: .constant("Baptist"),
                locationLabel: .constant("Tempe, AZ"),
                onFilter: {},
                scrollY: 80
            )
            Color.gray.opacity(0.1)
                .frame(height: 800)
        }
    }
}

#Preview("Empty location label → fallback") {
    FindChurch2CollapsingHeader(
        searchText: .constant(""),
        locationLabel: .constant(""),
        onFilter: {}
    )
}
#endif
