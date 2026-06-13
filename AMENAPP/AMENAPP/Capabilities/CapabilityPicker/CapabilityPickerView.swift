// CapabilityPickerView.swift
// AMEN Capabilities v1 — @ capability picker (Wave 1: Lane C)
//
// Floating glass panel anchored above the keyboard. Appears when the user
// types "@" at a word boundary in a wired composer surface.
//
// Accessibility: VoiceOver labels, Dynamic Type, reduced motion, reduced transparency.
// Contract: Docs/Capabilities/CONTRACTS.md §8

import SwiftUI

// MARK: - CapabilityPickerView

struct CapabilityPickerView: View {

    @ObservedObject var coordinator: CapabilityComposerCoordinator
    @ObservedObject private var store: CapabilityRegistryStore = .shared

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    // Track which row has keyboard focus for hardware-keyboard navigation.
    @State private var focusedIndex: Int? = 0

    // MARK: - Computed

    private var surfaceCapabilities: [Capability] {
        store.capabilities(for: coordinator.surface)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            if coordinator.isPickerVisible {
                pickerPanel
                    .transition(
                        reduceMotion
                            ? .opacity.animation(.easeInOut(duration: 0.2))
                            : .asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .move(edge: .bottom).combined(with: .opacity)
                              ).animation(.spring(response: 0.32, dampingFraction: 0.80))
                    )
            }
        }
        .animation(
            reduceMotion
                ? .easeInOut(duration: 0.2)
                : .spring(response: 0.32, dampingFraction: 0.80),
            value: coordinator.isPickerVisible
        )
        .task(id: coordinator.surface) {
            // Load capabilities whenever the surface changes (or on first appear).
            await store.loadCapabilities(for: coordinator.surface)
        }
        // Reset focused index whenever the picker opens.
        .onChange(of: coordinator.isPickerVisible) { visible in
            if visible { focusedIndex = surfaceCapabilities.isEmpty ? nil : 0 }
        }
    }

    // MARK: - Panel

    @ViewBuilder
    private var pickerPanel: some View {
        VStack(spacing: 0) {
            headerRow
            Divider()
                .opacity(0.4)
            if store.isLoading {
                loadingRow
            } else if surfaceCapabilities.isEmpty {
                emptyStateRow
            } else {
                capabilityList
            }
        }
        .glassSurface(cornerRadius: 16)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .shadow(color: .black.opacity(0.15), radius: 20, y: 4)
        // Dismiss on external tap (handled by the hosting view via coordinator).
        .onTapGesture {} // swallows taps inside the panel; external taps reach the hosting view
        // Hardware keyboard: Escape dismisses.
        .onKeyPress(.escape) {
            coordinator.dismissPicker()
            return .handled
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack {
            Image(systemName: "at")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("Capabilities")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                coordinator.dismissPicker()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.body)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss capability picker")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Rows

    private var capabilityList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(Array(surfaceCapabilities.enumerated()), id: \.element.id) { index, cap in
                    capabilityRow(cap, index: index)
                    if index < surfaceCapabilities.count - 1 {
                        Divider()
                            .padding(.leading, 52)
                            .opacity(0.35)
                    }
                }
            }
        }
        .frame(maxHeight: 260)
    }

    @ViewBuilder
    private func capabilityRow(_ cap: Capability, index: Int) -> some View {
        let isFocused = focusedIndex == index

        Button {
            coordinator.selectCapability(cap)
        } label: {
            HStack(spacing: 12) {
                // Icon
                Image(systemName: cap.iconSymbol)
                    .font(.title3)
                    .foregroundStyle(isFocused ? Color.accentColor : .primary)
                    .frame(width: 30)

                // Text stack
                VStack(alignment: .leading, spacing: 2) {
                    Text(cap.displayName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(cap.tagline)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // Tier badge
                if cap.tier == .plus {
                    Text("Plus")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                }

                // Focus indicator
                if isFocused {
                    Image(systemName: "return")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .background(
                isFocused
                    ? Color.primary.opacity(0.06)
                    : Color.clear
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(cap.displayName) — \(cap.tagline)")
        .accessibilityAddTraits(.isButton)
        .onHover { hovering in
            if hovering { focusedIndex = index }
        }
        // Hardware keyboard: Tab/arrow moves focus; Return/Space selects.
        .onKeyPress(.upArrow) {
            moveFocus(by: -1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            moveFocus(by: 1)
            return .handled
        }
        .onKeyPress(.return) {
            coordinator.selectCapability(cap)
            return .handled
        }
        .onKeyPress(.space) {
            coordinator.selectCapability(cap)
            return .handled
        }
    }

    // MARK: - Loading

    private var loadingRow: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Loading capabilities…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .accessibilityLabel("Loading capabilities")
    }

    // MARK: - Empty state

    private var emptyStateRow: some View {
        VStack(spacing: 6) {
            Image(systemName: "puzzlepiece.extension")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No capabilities available")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
            Text("Capabilities are rolled out gradually. Check back soon.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No capabilities available. Capabilities are rolled out gradually. Check back soon.")
    }

    // MARK: - Keyboard helpers

    private func moveFocus(by delta: Int) {
        let count = surfaceCapabilities.count
        guard count > 0 else { return }
        let current = focusedIndex ?? 0
        focusedIndex = (current + delta + count) % count
    }
}
