//
//  ChurchNoteFormattingBar.swift
//  AMENAPP
//
//  Above-keyboard formatting bar with bold/italic/underline,
//  5 highlight type pills, and block conversion actions.
//
//  iOS 26+: each button segment uses native .amenGlassEffect() so the bar
//  matches the iOS 26 Notes app formatting toolbar pattern.
//  Reduce-transparency: falls back to a solid systemBackground strip.
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
        ScrollView(.horizontal, showsIndicators: false) {
            if reduceTransparency {
                solidToolbarContent
            } else {
                glassToolbarContent
            }
        }
        .frame(height: 44)
        .background(
            reduceTransparency
                ? Color(.systemBackground)
                : Color.clear
        )
    }

    // MARK: - Glass toolbar (iOS 26 GlassEffectContainer)

    @ViewBuilder
    private var glassToolbarContent: some View {
        HStack(spacing: 6) {
            // Section 1: Text formatting — grouped in a single container
            GlassEffectContainer(spacing: 0) {
                HStack(spacing: 0) {
                    formatButton(icon: "bold",
                                 label: "Bold",
                                 isActive: activeFormats.isBold,
                                 action: onBold)
                    formatButton(icon: "italic",
                                 label: "Italic",
                                 isActive: activeFormats.isItalic,
                                 action: onItalic)
                    formatButton(icon: "underline",
                                 label: "Underline",
                                 isActive: activeFormats.isUnderline,
                                 action: onUnderline)
                }
            }

            sectionDivider

            // Section 2: Highlight pills — one glass surface per pill.
            // The pill label+tint sits inside a glass capsule; the old ultraThinMaterial
            // background from ChurchNoteHighlightButton is bypassed here to avoid
            // glass-on-glass layering. ChurchNoteHighlightButton is used unchanged
            // in the solid fallback path below.
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
                            // Tint overlay only — no material background here.
                            // The system glass capsule (glassEffect below) is the surface.
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

            sectionDivider

            // Section 3: Block conversion — single container, dimmed when no selection
            GlassEffectContainer(spacing: 4) {
                HStack(spacing: 4) {
                    ForEach(ChurchNoteBlockType.allCases.filter(\.isConvertible), id: \.self) { type in
                        Button {
                            onBlockConvert(type)
                        } label: {
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
        .padding(.horizontal, 12)
    }

    // MARK: - Solid fallback (reduceTransparency)

    @ViewBuilder
    private var solidToolbarContent: some View {
        HStack(spacing: 2) {
            solidFormatButton(icon: "bold",  label: "Bold",      isActive: activeFormats.isBold,      action: onBold)
            solidFormatButton(icon: "italic", label: "Italic",   isActive: activeFormats.isItalic,    action: onItalic)
            solidFormatButton(icon: "underline", label: "Underline", isActive: activeFormats.isUnderline, action: onUnderline)

            sectionDivider

            ForEach(ChurchNoteHighlightType.allCases, id: \.self) { type in
                ChurchNoteHighlightButton(
                    type: type,
                    isSelected: activeHighlight == type
                ) { onHighlight(type) }
            }

            sectionDivider

            ForEach(ChurchNoteBlockType.allCases.filter(\.isConvertible), id: \.self) { type in
                Button {
                    onBlockConvert(type)
                } label: {
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
        .padding(.horizontal, 12)
    }

    // MARK: - Helpers

    /// Glass format button — `.amenGlassEffect()` is the last modifier on the button.
    private func formatButton(icon: String, label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.systemScaled(16, weight: .medium))
                .foregroundStyle(isActive ? Color.primary : Color.secondary)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .amenGlassEffect()
        .animation(reduceMotion ? nil : .snappy, value: isActive)
    }

    /// Solid fallback format button for reduceTransparency.
    private func solidFormatButton(icon: String, label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.systemScaled(16, weight: .medium))
                .foregroundStyle(isActive ? Color.primary : Color.secondary)
                .frame(width: 40, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isActive ? Color.primary.opacity(0.1) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var sectionDivider: some View {
        Divider()
            .frame(height: 20)
            .padding(.horizontal, 2)
    }
}
