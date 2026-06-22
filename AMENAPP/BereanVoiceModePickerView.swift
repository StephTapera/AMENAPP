// BereanVoiceModePickerView.swift
// AMENAPP
//
// Berean Live Voice — Reusable mode-selection chip component
//
// BereanVoiceModeChip: a Capsule pill with mode icon + label.
//   Selected  → black fill, white text
//   Unselected → .ultraThinMaterial fill, black text
//
// No existing files are modified.

import SwiftUI

// MARK: - BereanVoiceModeChip

struct BereanVoiceModeChip: View {

    // -------------------------------------------------------------------------
    // MARK: Inputs
    // -------------------------------------------------------------------------

    let mode:       BereanVoiceMode
    let isSelected: Bool
    let onSelect:   () -> Void

    // -------------------------------------------------------------------------
    // MARK: Environment
    // -------------------------------------------------------------------------

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // -------------------------------------------------------------------------
    // MARK: Body
    // -------------------------------------------------------------------------

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 5) {
                Image(systemName: mode.systemIconName)
                    .font(.systemScaled(11, weight: .medium))

                Text(mode.displayName)
                    .font(.custom("OpenSans-SemiBold", size: 12))
            }
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(chipBackground)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(mode.displayName) mode")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .animation(
            reduceMotion ? nil : Motion.adaptive(.spring(response: 0.28, dampingFraction: 0.72)),
            value: isSelected
        )
    }

    // -------------------------------------------------------------------------
    // MARK: Background
    // -------------------------------------------------------------------------

    @ViewBuilder
    private var chipBackground: some View {
        if isSelected {
            Capsule()
                .fill(Color.black)
        } else {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                )
        }
    }
}

// MARK: - BereanVoiceModePicker (Full Row)

/// A horizontally scrolling row of BereanVoiceModeChip pills.
/// Drop this into any view that needs mode selection outside of BereanLiveVoiceView.
struct BereanVoiceModePicker: View {

    @Binding var selectedMode: BereanVoiceMode

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(BereanVoiceMode.allCases, id: \.rawValue) { mode in
                    BereanVoiceModeChip(
                        mode: mode,
                        isSelected: selectedMode == mode
                    ) {
                        selectedMode = mode
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Mode Chips") {
    VStack(spacing: 20) {
        // All unselected
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(BereanVoiceMode.allCases, id: \.rawValue) { mode in
                    BereanVoiceModeChip(mode: mode, isSelected: false) {}
                }
            }
            .padding(.horizontal, 16)
        }

        // First selected
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(BereanVoiceMode.allCases, id: \.rawValue) { mode in
                    BereanVoiceModeChip(
                        mode: mode,
                        isSelected: mode == .prayer
                    ) {}
                }
            }
            .padding(.horizontal, 16)
        }
    }
    .padding(.vertical, 24)
    .background(Color(.systemBackground))
}
#endif
