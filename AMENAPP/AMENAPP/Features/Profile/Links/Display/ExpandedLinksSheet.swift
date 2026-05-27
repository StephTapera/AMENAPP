import SwiftUI

// MARK: - ExpandedLinksSheet

/// Full-sheet list of all a user's typed link slots.
/// Each row opens the URL in-app via the `openURL` environment action.
struct ExpandedLinksSheet: View {

    let slots: [LinkSlot]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            List {
                ForEach(slots) { slot in
                    LinkRow(slot: slot) {
                        openURL(slot.url)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Links")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            // Glassmorphic drag handle capsule
            .safeAreaInset(edge: .top) {
                DragHandle()
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden) // we draw our own
        .presentationBackground(.ultraThinMaterial)
    }
}

// MARK: - LinkRow

private struct LinkRow: View {
    let slot: LinkSlot
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Image(systemName: slot.type.systemImage)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(slot.label)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)

                    Text(slot.url.absoluteString)
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(slot.label), \(slot.url.absoluteString)")
        .accessibilityHint("Opens link in browser")
    }
}

// MARK: - DragHandle

private struct DragHandle: View {
    var body: some View {
        Capsule()
            .fill(Color(uiColor: .tertiaryLabel))
            .frame(width: 36, height: 4)
            .padding(.top, 8)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    let slots: [LinkSlot] = [
        LinkSlot(id: "1", type: .church,   url: URL(string: "https://mychurch.org")!,    label: "My Church",      order: 0),
        LinkSlot(id: "2", type: .giving,   url: URL(string: "https://give.example.com")!, label: "Give",           order: 1),
        LinkSlot(id: "3", type: .podcast,  url: URL(string: "https://podcasts.apple.com")!, label: "Podcast",      order: 2),
        LinkSlot(id: "4", type: .book,     url: URL(string: "https://amazon.com/book")!,  label: "Read the Book",  order: 3),
    ]
    ExpandedLinksSheet(slots: slots)
}
#endif
