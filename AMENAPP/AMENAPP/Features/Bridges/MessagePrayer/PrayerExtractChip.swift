import SwiftUI

/// Inline chip for converting a prayer-request message into a prayer list entry.
/// Shown as a dismissible banner below the message bubble.
struct PrayerExtractChip: View {
    let suggestion: PrayerSuggestion
    let onAccept: () -> Void
    let onDismiss: () -> Void

    @State private var isVisible = true

    var body: some View {
        if isVisible {
            HStack(spacing: 10) {
                Image(systemName: "hands.clap")
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Add to your prayer list?")
                        .font(.subheadline.weight(.medium))
                    Text(suggestion.excerpt)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button(action: {
                    withAnimation { isVisible = false }
                    onAccept()
                }) {
                    Text("Add")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.tint)
                }

                Button(action: {
                    withAnimation { isVisible = false }
                    onDismiss()
                }) {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 12)
            .transition(.asymmetric(
                insertion: .move(edge: .bottom).combined(with: .opacity),
                removal: .opacity
            ))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Prayer suggestion: \(suggestion.suggestedTitle). Double tap to add.")
            .accessibilityAddTraits(.isButton)
        }
    }
}
