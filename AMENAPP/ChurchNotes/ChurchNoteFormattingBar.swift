//
//  ChurchNoteFormattingBar.swift
//  AMENAPP
//
//  Above-keyboard formatting bar for Church Notes.
//  Builds on AmenFormatPanel (B/I/U) and adds church-notes-specific
//  highlight pills and block conversion actions as trailing content.
//
//  To use B/I/U alone on any other surface, adopt AmenFormatPanel directly.
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

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        AmenFormatPanel(
            activeState: AmenFormatActiveState(
                isBold: activeFormats.isBold,
                isItalic: activeFormats.isItalic,
                isUnderline: activeFormats.isUnderline
            ),
            onBold: onBold,
            onItalic: onItalic,
            onUnderline: onUnderline
        ) {
            churchExtensions
        }
    }

    // MARK: - Church-notes-specific toolbar sections

    @ViewBuilder
    private var churchExtensions: some View {
        if reduceTransparency {
            solidHighlightsAndBlocks
        } else {
            glassHighlightsAndBlocks
        }
    }

    private var glassHighlightsAndBlocks: some View {
        HStack(spacing: 6) {
            // Highlight pills
            GlassEffectContainer(spacing: 4) {
                HStack(spacing: 4) {
                    ForEach(ChurchNoteHighlightType.allCases, id: \.self) { type in
                        let isSelected = activeHighlight == type
                        Button { onHighlight(type) } label: {
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
                                isSelected
                                    ? Capsule().fill(type.selectedButtonFill)
                                    : nil
                            )
                            .overlay(
                                Capsule().strokeBorder(
                                    isSelected ? type.selectedButtonBorder : Color.clear,
                                    lineWidth: 0.5
                                )
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(type.shortLabel)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                        .amenGlassEffect(in: Capsule())
                        .animation(reduceMotion ? nil : .snappy, value: isSelected)
                    }
                }
            }

            Divider()
                .frame(height: 20)
                .padding(.horizontal, 2)

            // Block conversion
            GlassEffectContainer(spacing: 4) {
                HStack(spacing: 4) {
                    ForEach(ChurchNoteBlockType.allCases.filter(\.isConvertible), id: \.self) { type in
                        Button { onBlockConvert(type) } label: {
                            HStack(spacing: 3) {
                                Image(systemName: type.icon)
                                    .font(.systemScaled(10))
                                Text(type.displayName)
                                    .font(.systemScaled(11, weight: .medium))
                            }
                            .foregroundStyle(hasSelection ? Color.secondary : Color.secondary.opacity(0.3))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                        }
                        .buttonStyle(.plain)
                        .disabled(!hasSelection)
                        .accessibilityLabel("Convert to \(type.displayName)")
                        .accessibilityHint(hasSelection ? "" : "Requires a text selection")
                        .amenGlassEffect(in: Capsule())
                        .animation(reduceMotion ? nil : .snappy, value: hasSelection)
                    }
                }
            }
        }
    }

    private var solidHighlightsAndBlocks: some View {
        HStack(spacing: 2) {
            ForEach(ChurchNoteHighlightType.allCases, id: \.self) { type in
                ChurchNoteHighlightButton(
                    type: type,
                    isSelected: activeHighlight == type
                ) { onHighlight(type) }
            }

            Divider()
                .frame(height: 20)
                .padding(.horizontal, 2)

            ForEach(ChurchNoteBlockType.allCases.filter(\.isConvertible), id: \.self) { type in
                Button { onBlockConvert(type) } label: {
                    HStack(spacing: 3) {
                        Image(systemName: type.icon)
                            .font(.systemScaled(10))
                        Text(type.displayName)
                            .font(.systemScaled(11, weight: .medium))
                    }
                    .foregroundStyle(hasSelection ? Color.secondary : Color.secondary.opacity(0.3))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color(.secondarySystemFill)))
                }
                .buttonStyle(.plain)
                .disabled(!hasSelection)
                .accessibilityLabel("Convert to \(type.displayName)")
                .accessibilityHint(hasSelection ? "" : "Requires a text selection")
            }
        }
    }
}
