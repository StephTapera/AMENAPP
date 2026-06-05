// NoteBlockComposer.swift
// AMENAPP — ChurchNotesOS
// Horizontal block-type insertion row for the note editor.

import SwiftUI

// MARK: - Block Type

enum NoteBlockType: String, CaseIterable, Identifiable {
    case scripture, prayer, reflection, question, action, testimony, voice, photo

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .scripture:   return "Scripture"
        case .prayer:      return "Prayer"
        case .reflection:  return "Reflection"
        case .question:    return "Question"
        case .action:      return "Action"
        case .testimony:   return "Testimony"
        case .voice:       return "Voice"
        case .photo:       return "Photo"
        }
    }

    var icon: String {
        switch self {
        case .scripture:   return "book.fill"
        case .prayer:      return "hands.sparkles.fill"
        case .reflection:  return "bubble.left.and.text.bubble.right.fill"
        case .question:    return "questionmark.bubble.fill"
        case .action:      return "checkmark.circle.fill"
        case .testimony:   return "star.fill"
        case .voice:       return "waveform"
        case .photo:       return "camera.fill"
        }
    }

    var accent: Color {
        switch self {
        case .scripture:   return .amenGold
        case .prayer:      return Color.purple
        case .reflection:  return Color.blue
        case .question:    return Color.orange
        case .action:      return Color.green
        case .testimony:   return Color.yellow
        case .voice:       return Color.pink
        case .photo:       return Color.teal
        }
    }
}

// MARK: - Block Composer Row

struct NoteBlockComposer: View {
    let onInsert: (NoteBlockType) -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(NoteBlockType.allCases) { blockType in
                    BlockChip(type: blockType, onInsert: onInsert)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background {
            if reduceTransparency {
                Color(.secondarySystemBackground)
            } else {
                Rectangle().fill(.ultraThinMaterial)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Block Chip

private struct BlockChip: View {
    let type: NoteBlockType
    let onInsert: (NoteBlockType) -> Void

    var body: some View {
        Button {
            onInsert(type)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: type.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(type.accent)
                Text("+ \(type.displayName)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 34)
            .background(type.accent.opacity(0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(type.accent.opacity(0.3), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add \(type.displayName) block")
    }
}

// MARK: - Preview

#Preview {
    VStack {
        Spacer()
        NoteBlockComposer { blockType in
            print("Insert:", blockType.displayName)
        }
        .padding()
    }
}
