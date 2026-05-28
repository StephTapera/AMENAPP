// ChurchNoteAnchorPickerSheet.swift
// AMENAPP
//
// Glass pill sheet for choosing an anchor type to apply to a block.
// Appears as a half-height sheet when user long-presses a block
// or taps "Mark Anchor" from the block context menu.
//
// Design: liquid glass background, soft color swatches, no heavy gradients.
// Interaction: tap anchor type to apply; tap again to clear; dismiss with Done.

import SwiftUI

struct ChurchNoteAnchorPickerSheet: View {

    /// The current semantic type of the block being marked.
    let currentSemanticType: ChurchNoteSemanticType
    /// Called when user selects (or clears) an anchor.
    let onSelect: (CNAnchorType?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selected: CNAnchorType?
    @State private var showHint = false

    private var resolvedCurrent: CNAnchorType? {
        let anchorables: [ChurchNoteSemanticType] = [
            .conviction, .keyTruth, .prayerPoint, .actionStep,
            .question, .verseInsight, .pastorQuote, .testimony,
        ]
        guard anchorables.contains(currentSemanticType) else { return nil }
        return CNAnchorType(from: currentSemanticType)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                headerSection
                    .padding(.top, 8)

                anchorGrid
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                if let anchor = selected, showHint {
                    hintBanner(anchor: anchor)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                Spacer()

                applyButton
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.secondary)
                }
            }
            .onAppear {
                selected = resolvedCurrent
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 4) {
            Text("Mark Anchor")
                .font(.headline)
                .foregroundStyle(.primary)
            Text("What does this moment mean to you?")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    // MARK: - Anchor Grid

    private var anchorGrid: some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(CNAnchorType.allCases) { anchor in
                anchorCell(anchor)
            }
        }
    }

    private func anchorCell(_ anchor: CNAnchorType) -> some View {
        let isSelected = selected == anchor

        return Button {
            withAnimation(ChurchNotesAnimationTokens.chipInsert) {
                if selected == anchor {
                    // Tap selected again to clear
                    selected = nil
                    showHint = false
                } else {
                    selected = anchor
                    showHint = true
                }
            }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(isSelected ? anchor.fillColor : Color(.tertiarySystemFill))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    isSelected ? anchor.borderColor.opacity(0.6) : Color.clear,
                                    lineWidth: 1.5
                                )
                        )
                    Image(systemName: anchor.icon)
                        .font(.systemScaled(18))
                        .foregroundStyle(isSelected ? anchor.accentColor : Color.secondary)
                        .accessibilityHidden(true)
                }

                Text(anchor.shortLabel)
                    .font(.caption2.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? anchor.accentColor : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? anchor.fillColor.opacity(0.5) : Color.clear)
            )
            .animation(ChurchNotesAnimationTokens.chipInsert, value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(anchor.displayName)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Hint Banner

    private func hintBanner(anchor: CNAnchorType) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle")
                .font(.caption)
                .foregroundStyle(anchor.accentColor)
                .accessibilityHidden(true)
            Text(anchor.downstreamHint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(anchor.fillColor.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(anchor.borderColor.opacity(0.3), lineWidth: 1)
                )
        )
    }

    // MARK: - Apply Button

    private var applyButton: some View {
        HStack(spacing: 12) {
            if resolvedCurrent != nil {
                Button {
                    onSelect(nil)
                    dismiss()
                } label: {
                    Text("Clear")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear anchor marking")
            }

            Button {
                onSelect(selected)
                dismiss()
            } label: {
                HStack(spacing: 6) {
                    if let anchor = selected {
                        Image(systemName: anchor.icon)
                            .font(.systemScaled(14))
                            .accessibilityHidden(true)
                        Text("Mark as \(anchor.shortLabel)")
                    } else {
                        Text("No anchor")
                    }
                }
                .font(.body.weight(.semibold))
                .foregroundStyle(selected != nil ? Color(.systemBackground) : .secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    selected != nil
                        ? AnyShapeStyle(Color.primary)
                        : AnyShapeStyle(Color(.tertiarySystemFill)),
                    in: RoundedRectangle(cornerRadius: 12)
                )
            }
            .buttonStyle(.plain)
            .disabled(selected == nil && resolvedCurrent == nil)
            .accessibilityLabel(selected.map { "Apply anchor type \($0.displayName)" } ?? "No anchor selected")
        }
    }
}

// MARK: - Anchor Chip (inline indicator)

/// Compact chip shown on a block cell that has an anchor marking.
struct ChurchNoteAnchorChip: View {
    let anchor: CNAnchorType

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: anchor.icon)
                .font(.systemScaled(10))
                .accessibilityHidden(true)
            Text(anchor.shortLabel)
                .font(.systemScaled(10, weight: .medium))
        }
        .foregroundStyle(anchor.accentColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(anchor.fillColor)
                .overlay(Capsule().strokeBorder(anchor.borderColor.opacity(0.4), lineWidth: 0.5))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(anchor.displayName) anchor")
    }
}

// MARK: - Preview

#if DEBUG
struct ChurchNoteAnchorPickerSheet_Previews: PreviewProvider {
    static var previews: some View {
        ChurchNoteAnchorPickerSheet(
            currentSemanticType: .general,
            onSelect: { _ in }
        )
        .previewDisplayName("Fresh block")

        ChurchNoteAnchorPickerSheet(
            currentSemanticType: .conviction,
            onSelect: { _ in }
        )
        .previewDisplayName("Already marked Conviction")
    }
}
#endif
