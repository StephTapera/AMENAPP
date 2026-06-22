//
//  BereanModeDrawer.swift
//  AMENAPP
//
//  Bottom sheet drawer for Berean personality mode selection.
//  Replaces inline mode chips with a full-featured selection experience.
//

import SwiftUI

struct BereanModeDrawer: View {
    @Binding var selectedMode: BereanPersonalityMode
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(BereanPersonalityMode.allCases) { mode in
                        modeCard(mode)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Color(uiColor: .systemBackground))
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

    private func modeCard(_ mode: BereanPersonalityMode) -> some View {
        let isSelected = selectedMode == mode

        return Button {
            withAnimation(Motion.adaptive(.spring(response: 0.28, dampingFraction: 0.78))) {
                selectedMode = mode
            }
            HapticManager.impact(style: .light)
        } label: {
            HStack(spacing: 14) {
                // Icon circle
                Circle()
                    .fill(isSelected ? Color.black : Color.black.opacity(0.06))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: mode.icon)
                            .font(.systemScaled(16, weight: .semibold))
                            .foregroundStyle(isSelected ? .white : .black.opacity(0.5))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.rawValue)
                        .font(AMENFont.semiBold(16))
                        .foregroundStyle(.primary)

                    Text(mode.description)
                        .font(AMENFont.regular(13))
                        .foregroundStyle(.black.opacity(0.5))
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.systemScaled(20))
                        .foregroundStyle(.primary)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? Color.black.opacity(0.04) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isSelected ? Color.black.opacity(0.12) : Color.black.opacity(0.06), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}
