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
                formatButton(icon: "bold", isActive: activeFormats.isBold, action: onBold)
                formatButton(icon: "italic", isActive: activeFormats.isItalic, action: onItalic)
                formatButton(icon: "underline", isActive: activeFormats.isUnderline, action: onUnderline)

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
                                .font(.system(size: 10))
                            Text(type.displayName)
                                .font(.system(size: 11, weight: .medium))
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

    private func formatButton(icon: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(isActive ? Color.primary : Color.secondary)
                .frame(width: 40, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isActive ? Color.primary.opacity(0.1) : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }

    private var sectionDivider: some View {
        Divider()
            .frame(height: 20)
            .padding(.horizontal, 4)
    }
}
