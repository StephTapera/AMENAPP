// SabbathSurfaceListView.swift
// AMENAPP — SabbathMode
//
// 8 tappable surface rows inside the SabbathWindowView white card.
// Each row: SF Symbol icon (monochrome, .secondary), label (.body.bold),
// description (.caption, secondary). No borders between rows.
// Tap → onSurfaceSelect(surface).
//
// BANNED tokens: gold, purple, dark gradients, serif fonts, streaks, counts.

import SwiftUI

// MARK: - Surface metadata

private struct SurfaceEntry {
    let surface: SabbathSurface
    let symbolName: String
    let label: String
    let description: String
}

private let SURFACE_ENTRIES: [SurfaceEntry] = [
    SurfaceEntry(
        surface: .scripture,
        symbolName: "book.closed",
        label: "Scripture",
        description: "Read and reflect on the Word"
    ),
    SurfaceEntry(
        surface: .prayer,
        symbolName: "hands.and.sparkles",
        label: "Prayer",
        description: "Pray, be still, listen"
    ),
    SurfaceEntry(
        surface: .bereanGuide,
        symbolName: "bubble.left.and.text.bubble.right",
        label: "Berean Guide",
        description: "Be led through prayer or study"
    ),
    SurfaceEntry(
        surface: .churchNotes,
        symbolName: "note.text",
        label: "Church Notes",
        description: "Capture and review sermon notes"
    ),
    SurfaceEntry(
        surface: .findChurch,
        symbolName: "mappin.and.ellipse",
        label: "Find a Church",
        description: "Find where to worship today"
    ),
    SurfaceEntry(
        surface: .spaces,
        symbolName: "person.3",
        label: "Spaces",
        description: "Connect with your community"
    ),
    SurfaceEntry(
        surface: .familyQuestions,
        symbolName: "house",
        label: "Family Questions",
        description: "Dinner table conversation starters"
    ),
    SurfaceEntry(
        surface: .reflection,
        symbolName: "text.alignleft",
        label: "Reflection",
        description: "Journal privately"
    ),
]

// MARK: - Surface row

private struct SurfaceRowView: View {
    let entry: SurfaceEntry
    let onSelect: (SabbathSurface) -> Void

    @State private var isPressed = false

    var body: some View {
        Button {
            onSelect(entry.surface)
        } label: {
            HStack(spacing: 12) {
                // Icon container — monochrome, .secondary
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(.systemFill))
                        .frame(width: 36, height: 36)

                    Image(systemName: entry.symbolName)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(.secondary)
                }

                // Text stack
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.label)
                        .font(.body.bold())
                        .foregroundStyle(.primary)
                    Text(entry.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isPressed ? Color.black.opacity(0.04) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(entry.label): \(entry.description)")
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded   { _ in isPressed = false }
        )
    }
}

// MARK: - SabbathSurfaceListView

struct SabbathSurfaceListView: View {
    var onSurfaceSelect: (SabbathSurface) -> Void

    var body: some View {
        VStack(spacing: 2) {
            ForEach(SURFACE_ENTRIES, id: \.surface.rawValue) { entry in
                SurfaceRowView(entry: entry, onSelect: onSurfaceSelect)
            }
        }
        .accessibilityLabel("Sabbath surfaces")
    }
}

#Preview {
    SabbathSurfaceListView { surface in
        print("Selected: \(surface.rawValue)")
    }
    .padding()
    .background(Color.white)
}
