//
//  ChurchNoteFormattingBar.swift
//  AMENAPP
//
//  Above-keyboard formatting bar with bold/italic/underline,
//  5 highlight type pills, and block conversion actions.
//

import SwiftUI

struct ChurchNoteFormattingBar: View {
    let activeFormats: ChurchNoteActiveFormats
    let activeHighlight: ChurchNoteHighlightType?
    let hasSelection: Bool

    let onBold: () -> Void
    let onItalic: () -> Void
    let onUnderline: () -> Void
    let onHighlight: (ChurchNoteHighlightType) -> Void
    let onBlockConvert: (ChurchNoteBlockType) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                // Section 1: Text formatting
                formatButton(icon: "bold", label: "Bold", isActive: activeFormats.isBold, action: onBold)
                formatButton(icon: "italic", label: "Italic", isActive: activeFormats.isItalic, action: onItalic)
                formatButton(icon: "underline", label: "Underline", isActive: activeFormats.isUnderline, action: onUnderline)

                sectionDivider

                // Section 2: Highlights
                ForEach(ChurchNoteHighlightType.allCases, id: \.self) { type in
                    ChurchNoteHighlightButton(
                        type: type,
                        isSelected: activeHighlight == type
                    ) {
                        onHighlight(type)
                    }
                }

                sectionDivider

                // Section 3: Block conversion (only enabled with selection)
                ForEach(ChurchNoteBlockType.allCases.filter(\.isConvertible), id: \.self) { type in
                    Button {
                        onBlockConvert(type)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: type.icon)
                                .font(.systemScaled(10, weight: .regular))
                            Text(type.displayName)
                                .font(.systemScaled(11, weight: .medium))
                        }
                        .foregroundStyle(hasSelection ? Color.secondary : Color.secondary.opacity(0.3))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(Color(.systemBackground).opacity(hasSelection ? 0.6 : 0.3))
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.primary.opacity(hasSelection ? 0.1 : 0.04), lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!hasSelection)
                }
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 44)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Rectangle().fill(Color(.systemBackground).opacity(0.85)))
        )
    }

    // MARK: - Helpers

    private func formatButton(icon: String, label: String = "", isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.systemScaled(16, weight: .medium))
                .foregroundStyle(isActive ? Color.amenPurple : Color.secondary)
                .frame(width: 40, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isActive ? Color.amenPurple.opacity(0.12) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label.isEmpty ? icon : label)
        .accessibilityValue(isActive ? "Active" : "Inactive")
    }

    private var sectionDivider: some View {
        Divider()
            .frame(height: 20)
            .padding(.horizontal, 4)
    }
}
