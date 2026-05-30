//
//  BereanModeDrawer.swift
//  AMENAPP
//
//  Bottom sheet drawer for Berean personality mode selection.
//  2-column glass pill grid replacing full-width card list.
//

import SwiftUI

struct BereanModeDrawer: View {
    @Binding var selectedMode: BereanPersonalityMode
    @Environment(\.dismiss) private var dismiss

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(BereanPersonalityMode.allCases) { mode in
                        ModePill(mode: mode, isSelected: selectedMode == mode) {
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                                selectedMode = mode
                            }
                            HapticManager.impact(style: .light)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Color(.systemBackground))
            .navigationTitle("Response Style")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(AMENFont.semiBold(16))
                        .foregroundStyle(.primary)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - ModePill

private struct ModePill: View {
    let mode: BereanPersonalityMode
    let isSelected: Bool
    let action: () -> Void

    @GestureState private var isPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let gold = AmenTheme.Colors.amenGold

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: mode.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isSelected ? gold : Color.secondary)

                Text(mode.rawValue)
                    .font(AMENFont.semiBold(14))
                    .foregroundStyle(Color.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .padding(.horizontal, 8)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? gold.opacity(0.15) : Color.primary.opacity(0.06))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                isSelected ? gold.opacity(0.5) : Color.primary.opacity(0.12),
                                lineWidth: isSelected ? 1 : 0.5
                            )
                    }
            }
            .amenGlassEffect(isSelected ? gold.opacity(0.15) : .clear, cornerRadius: 14)
            .scaleEffect(isPressed ? 0.96 : 1.0)
            .opacity(isPressed ? 0.88 : 1.0)
            .animation(
                reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.22, dampingFraction: 0.82),
                value: isPressed
            )
            .animation(
                reduceMotion ? .easeOut(duration: 0.16) : .spring(response: 0.22, dampingFraction: 0.82),
                value: isSelected
            )
        }
        .buttonStyle(.plain)
        .gesture(DragGesture(minimumDistance: 0).updating($isPressed) { _, s, _ in s = true })
        .accessibilityLabel(mode.rawValue)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
