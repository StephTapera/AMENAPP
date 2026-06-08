//
//  ChurchNoteBlockView.swift
//  AMENAPP
//
//  Renders a single semantic block with soft tint background,
//  type icon, editable text, and delete/revert button.
//

import SwiftUI

struct ChurchNoteBlockView: View {
    let block: ChurchNoteBlock
    let onDelete: () -> Void
    let onUpdate: (ChurchNoteBlock) -> Void

    @State private var editingText: String

    init(block: ChurchNoteBlock, onDelete: @escaping () -> Void, onUpdate: @escaping (ChurchNoteBlock) -> Void) {
        self.block = block
        self.onDelete = onDelete
        self.onUpdate = onUpdate
        _editingText = State(initialValue: block.text)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Left accent border
            RoundedRectangle(cornerRadius: 2)
                .fill(CNToken.BlockBorder.color(for: block.type))
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 6) {
                // Block type header
                HStack(spacing: 5) {
                    Image(systemName: block.type.icon)
                        .font(.systemScaled(11, weight: .medium))
                        .foregroundStyle(CNToken.BlockBorder.color(for: block.type))

                    Text(block.type.displayName)
                        .font(.systemScaled(11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.5)

                    Spacer()

                    Button(action: onDelete) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.systemScaled(14))
                            .foregroundStyle(.quaternary)
                    }
                    .buttonStyle(.plain)
                }

                // Editable text
                TextField("", text: $editingText, axis: .vertical)
                    .font(.systemScaled(15))
                    .foregroundStyle(.primary)
                    .lineLimit(1...10)
                    .onChange(of: editingText) { _, newValue in
                        var updated = block
                        updated.text = newValue
                        onUpdate(updated)
                    }

                // Highlight badge if present
                if let hl = block.highlight {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(hl.fillColor)
                            .frame(width: 8, height: 8)
                        Text(hl.displayTitle)
                            .font(.systemScaled(10, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: CGFloat(CNToken.Radius.block), style: .continuous)
                .fill(CNToken.BlockTint.tint(for: block.type))
        )
        .overlay(
            RoundedRectangle(cornerRadius: CGFloat(CNToken.Radius.block), style: .continuous)
                .strokeBorder(CNToken.BlockBorder.color(for: block.type).opacity(0.3), lineWidth: 0.5)
        )
    }
}
