// BereanModeContextSheet.swift
// AMEN App — Mode explanation + switcher sheet opened from ComposerPlusButton or SmartContextRow.

import SwiftUI

/// A bottom sheet that explains the active Berean aura mode and lets the user switch.
struct BereanModeContextSheet: View {
    let auraMode: BereanAuraMode
    let onModeSelect: (BereanAuraMode) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selected: BereanAuraMode

    init(auraMode: BereanAuraMode, onModeSelect: @escaping (BereanAuraMode) -> Void) {
        self.auraMode = auraMode
        self.onModeSelect = onModeSelect
        _selected = State(initialValue: auraMode)
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    // Drag handle
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(.separator).opacity(0.45))
                        .frame(width: 36, height: 4)
                        .padding(.top, 12)

                    // Header
                    VStack(spacing: 6) {
                        Text("Choose Your Mode")
                            .font(.systemScaled(22, weight: .bold))
                            .foregroundColor(.black)
                        Text("Each mode shapes how Berean listens and responds.")
                            .font(.systemScaled(14))
                            .foregroundColor(.black.opacity(0.50))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 28)

                    // Mode cards
                    VStack(spacing: 12) {
                        ForEach(BereanAuraMode.allCases, id: \.self) { mode in
                            modeCard(mode)
                        }
                    }
                    .padding(.horizontal, 18)

                    // Apply button
                    Button {
                        onModeSelect(selected)
                        dismiss()
                    } label: {
                        Text("Apply")
                            .font(.systemScaled(16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .fill(.black)
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 32)
                }
            }
            .background(Color(red: 0.971, green: 0.971, blue: 0.969).ignoresSafeArea())
            .navigationBarHidden(true)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
    }

    private func modeCard(_ mode: BereanAuraMode) -> some View {
        let isSelected = selected == mode
        return Button {
            withAnimation(.easeInOut(duration: 0.22)) { selected = mode }
        } label: {
            HStack(spacing: 14) {
                // Icon badge
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(mode.auraColor1)
                        .frame(width: 48, height: 48)
                    Image(systemName: modeIcon(mode))
                        .font(.systemScaled(20, weight: .medium))
                        .foregroundColor(.black.opacity(0.70))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(mode.rawValue)
                        .font(.systemScaled(16, weight: .semibold))
                        .foregroundColor(.black)
                    Text(mode.contextHelper)
                        .font(.systemScaled(13))
                        .foregroundColor(.black.opacity(0.52))
                        .lineSpacing(1.5)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                // Selection ring
                ZStack {
                    Circle()
                        .strokeBorder(Color.black.opacity(isSelected ? 1 : 0.20), lineWidth: 1.5)
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Circle()
                            .fill(Color.black)
                            .frame(width: 12, height: 12)
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Color.white.opacity(isSelected ? 0.72 : 0.44))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(
                                isSelected ? Color.black.opacity(0.14) : Color.white.opacity(0.65),
                                lineWidth: isSelected ? 1 : 0.5
                            )
                    )
                    .shadow(color: .black.opacity(isSelected ? 0.07 : 0.03), radius: 12, y: 4)
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.22), value: isSelected)
    }

    private func modeIcon(_ mode: BereanAuraMode) -> String {
        switch mode {
        case .scripture: return "book.pages"
        case .prayer:    return "hands.sparkles"
        case .study:     return "graduationcap"
        }
    }
}
