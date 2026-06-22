//
//  MessagingInboxFilterTray.swift
//  AMENAPP
//
//  Apple Mail-style floating Liquid Glass tray for the inbox.
//  Layout:
//      [ ⌥ Filtered by Unread ▼ ]          [ 🔍 ]  [ 📝 ]
//
//  Design constraints:
//    - Regular Liquid Glass white-on-black palette.
//    - Safe-area aware (sits above home indicator).
//    - No glass-on-glass stacking — only the tray itself is glass.
//    - Message rows behind it remain content layer (no glass).
//    - Dynamic Type, VoiceOver, Reduce Motion / Reduce Transparency /
//      Increased Contrast all fall back gracefully.
//

import SwiftUI

// MARK: - Tray Public API

@available(iOS 17.0, *)
public struct MessagingInboxFilterTray: View {

    // Inputs
    let activeFilter: MessagingInboxFilter
    let availableFilters: [MessagingInboxFilter]
    let chips: [MessagingInboxFilter]
    let onFilterChange: (MessagingInboxFilter) -> Void
    let onClearFilter: () -> Void
    let onSearch: () -> Void
    let onCompose: () -> Void

    // Accessibility / motion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var dynamicType

    @State private var showFilterPicker = false

    public init(
        activeFilter: MessagingInboxFilter,
        availableFilters: [MessagingInboxFilter],
        chips: [MessagingInboxFilter] = [],
        onFilterChange: @escaping (MessagingInboxFilter) -> Void,
        onClearFilter: @escaping () -> Void,
        onSearch: @escaping () -> Void,
        onCompose: @escaping () -> Void
    ) {
        self.activeFilter = activeFilter
        self.availableFilters = availableFilters
        self.chips = chips
        self.onFilterChange = onFilterChange
        self.onClearFilter = onClearFilter
        self.onSearch = onSearch
        self.onCompose = onCompose
    }

    public var body: some View {
        VStack(spacing: 10) {
            if !chips.isEmpty {
                chipRow
            }
            controlRow
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }

    // MARK: - Chip Row

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chips) { chip in
                    chipButton(chip)
                }
            }
            .padding(.horizontal, 4)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Quick filters")
    }

    @ViewBuilder
    private func chipButton(_ filter: MessagingInboxFilter) -> some View {
        let isActive = activeFilter == filter
        Button {
            if isActive {
                onClearFilter()
            } else {
                onFilterChange(filter)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: filter.symbol)
                    .font(.systemScaled(12, weight: .semibold))
                Text(filter.title)
                    .font(.systemScaled(14, weight: isActive ? .semibold : .medium))
            }
            .foregroundStyle(isActive ? Color.white : Color.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(isActive
                          ? AnyShapeStyle(Color.accentColor)
                          : AnyShapeStyle(.thinMaterial))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(
                        Color.primary.opacity(contrast == .increased ? 0.30 : 0.06),
                        lineWidth: contrast == .increased ? 1.0 : 0.5
                    )
            )
            .frame(minHeight: 44 - 8 * 2) // ensure 44pt tap target via padding
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isActive ? "\(filter.title), selected" : filter.title)
        .accessibilityHint(isActive ? "Double tap to clear filter" : filter.voiceOverHint)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    // MARK: - Control Row (filter pill + search + compose)

    private var controlRow: some View {
        HStack(spacing: 10) {
            filterPill
            Spacer(minLength: 8)
            iconButton(systemName: "magnifyingglass",
                       label: "Search messages",
                       action: onSearch)
            iconButton(systemName: "square.and.pencil",
                       label: "Compose new message",
                       action: onCompose)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(trayBackground)
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(
                    Color.primary.opacity(contrast == .increased ? 0.30 : 0.08),
                    lineWidth: contrast == .increased ? 1.2 : 0.6
                )
        )
        .clipShape(Capsule(style: .continuous))
        .shadow(color: .black.opacity(reduceTransparency ? 0 : 0.12),
                radius: 14, x: 0, y: 6)
        .accessibilityElement(children: .contain)
    }

    private var trayBackground: AnyShapeStyle {
        // Reduce Transparency fallback: solid background.
        if reduceTransparency {
            return AnyShapeStyle(Color(.systemBackground))
        }
        return AnyShapeStyle(.regularMaterial)
    }

    // MARK: - Filter Pill

    private var filterPill: some View {
        Button {
            showFilterPicker = true
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 32, height: 32)
                    Image(systemName: activeFilter.symbol)
                        .font(.systemScaled(14, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("Filtered by")
                        .font(.systemScaled(11, weight: .medium))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 3) {
                        Text(activeFilter.title)
                            .font(.systemScaled(13, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                        Image(systemName: "chevron.down")
                            .font(.systemScaled(9, weight: .bold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .padding(.trailing, 4)
            }
            .padding(.leading, 4)
            .padding(.trailing, 12)
            .padding(.vertical, 4)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Filtered by \(activeFilter.title)")
        .accessibilityHint(activeFilter.voiceOverHint)
        .confirmationDialog(
            "Filter messages",
            isPresented: $showFilterPicker,
            titleVisibility: .visible
        ) {
            ForEach(availableFilters) { filter in
                Button(filter.title) {
                    onFilterChange(filter)
                }
            }
            if activeFilter != .all {
                Button("Clear filter", role: .destructive) {
                    onClearFilter()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Icon button (search / compose)

    @ViewBuilder
    private func iconButton(
        systemName: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.systemScaled(17, weight: .semibold))
                .foregroundStyle(Color.primary)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(Color(.systemBackground).opacity(reduceTransparency ? 1.0 : 0.5))
                )
                .overlay(
                    Circle()
                        .strokeBorder(
                            Color.primary.opacity(contrast == .increased ? 0.30 : 0.08),
                            lineWidth: contrast == .increased ? 1.0 : 0.4
                        )
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
