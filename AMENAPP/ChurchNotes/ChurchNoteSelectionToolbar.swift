//
//  ChurchNoteSelectionToolbar.swift
//  AMENAPP
//
//  Contextual liquid-glass toolbar appearing on text selection.
//  Shows bold/italic/underline, highlight submenu, and block conversion.
//

import SwiftUI

struct ChurchNoteSelectionToolbar: View {
    let activeFormats: ChurchNoteActiveFormats
    let hasSelection: Bool
    let onBold: () -> Void
    let onItalic: () -> Void
    let onUnderline: () -> Void
    let onHighlight: (ChurchNoteHighlightType) -> Void
    let onRemoveHighlight: () -> Void
    let onConvertBlock: (ChurchNoteBlockType) -> Void

    @State private var showHighlightPicker = false
    @State private var showBlockPicker = false

    var body: some View {
        if hasSelection {
            VStack(spacing: 6) {
                // Main toolbar row
                HStack(spacing: 2) {
                    // Text formatting
                    toolbarButton(icon: "bold", isActive: activeFormats.isBold, action: onBold)
                    toolbarButton(icon: "italic", isActive: activeFormats.isItalic, action: onItalic)
                    toolbarButton(icon: "underline", isActive: activeFormats.isUnderline, action: onUnderline)

                    thinDivider

                    // Highlight toggle
                    toolbarButton(
                        icon: "highlighter",
                        isActive: activeFormats.highlightType != nil
                    ) {
                        withAnimation(CNToken.Anim.quickTap) {
                            showHighlightPicker.toggle()
                            showBlockPicker = false
                        }
                    }

                    thinDivider

                    // Block convert
                    toolbarButton(icon: "square.text.square", isActive: false) {
                        withAnimation(CNToken.Anim.quickTap) {
                            showBlockPicker.toggle()
                            showHighlightPicker = false
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(toolbarBackground)

                // Highlight picker submenu
                if showHighlightPicker {
                    HStack(spacing: 4) {
                        ForEach(ChurchNoteHighlightType.allCases, id: \.self) { type in
                            ChurchNoteHighlightButton(
                                type: type,
                                isSelected: activeFormats.highlightType == type
                            ) {
                                if activeFormats.highlightType == type {
                                    onRemoveHighlight()
                                } else {
                                    onHighlight(type)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(toolbarBackground)
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
                }

                // Block picker submenu
                if showBlockPicker {
                    HStack(spacing: 4) {
                        ForEach(ChurchNoteBlockType.allCases.filter(\.isConvertible), id: \.self) { type in
                            Button {
                                onConvertBlock(type)
                                withAnimation(CNToken.Anim.quickTap) {
                                    showBlockPicker = false
                                }
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: type.icon)
                                        .font(.system(size: 10))
                                    Text(type.displayName)
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .foregroundStyle(.primary.opacity(0.65))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule()
                                        .fill(.ultraThinMaterial)
                                        .overlay(
                                            Capsule()
                                                .fill(Color(.systemBackground).opacity(0.55))
                                        )
                                )
                                .overlay(
                                    Capsule()
                                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
                                )
                                .shadow(color: .black.opacity(0.03), radius: 2, y: 1)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(toolbarBackground)
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
                }
            }
            .animation(CNToken.Anim.quickTap, value: hasSelection)
        }
    }

    // MARK: - Helpers

    private func toolbarButton(icon: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(isActive ? Color.primary : Color.secondary.opacity(0.7))
                .frame(width: 36, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(isActive ? Color.primary.opacity(0.1) : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }

    private var thinDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(width: 0.5, height: 18)
            .padding(.horizontal, 2)
    }

    private var toolbarBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.systemBackground).opacity(0.8))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
    }
}
