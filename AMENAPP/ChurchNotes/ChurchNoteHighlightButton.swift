//
//  ChurchNoteHighlightButton.swift
//  AMENAPP
//
//  Soft-tinted highlight pill for each ChurchNoteHighlightType.
//  Base state: translucent white glass + subtle neutral border.
//  Selected state: faint tint fill + slightly darker border + dark text.
//  Never uses bright saturation or white text.
//

import SwiftUI

struct ChurchNoteHighlightButton: View {
    let type: ChurchNoteHighlightType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: type.icon)
                    .font(.systemScaled(12, weight: .medium))
                Text(type.shortLabel)
                    .font(.systemScaled(12, weight: .medium))
            }
            .foregroundStyle(isSelected ? type.selectedButtonTextColor : .primary.opacity(0.65))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isSelected ? type.selectedButtonFill : .clear)
                    .background(
                        isSelected ? nil : Capsule().fill(.ultraThinMaterial)
                    )
                    .background(
                        isSelected ? nil : Capsule().fill(Color(.systemBackground).opacity(0.55))
                    )
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        isSelected ? type.selectedButtonBorder : Color.primary.opacity(0.1),
                        lineWidth: 0.5
                    )
            )
            .shadow(color: isSelected ? .clear : .black.opacity(0.04), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(CNToken.Anim.quickTap, value: isSelected)
    }
}

// MARK: - Highlight Button Row

/// Horizontal row of all 5 highlight types.
struct ChurchNoteHighlightRow: View {
    let activeHighlight: ChurchNoteHighlightType?
    let onSelect: (ChurchNoteHighlightType) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ChurchNoteHighlightType.allCases, id: \.self) { type in
                    ChurchNoteHighlightButton(
                        type: type,
                        isSelected: activeHighlight == type
                    ) {
                        if activeHighlight == type {
                            onSelect(type) // toggle off handled by parent
                        } else {
                            onSelect(type)
                        }
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }
}
