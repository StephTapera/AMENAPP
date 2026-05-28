import SwiftUI

struct SmartCommunitySearchBar: View {
    @Binding var text: String
    let isLoading: Bool
    let onSubmit: () -> Void
    let onClear: () -> Void

    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceTransparency) var reduceTransparency

    private let placeholderPrompts = [
        "Young adult church near me with worship...",
        "Small groups focused on Bible study...",
        "Diverse community with childcare...",
        "Church with recovery ministry...",
        "Quiet, contemplative congregation...",
    ]

    @State private var placeholderIndex = 0

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField(placeholderPrompts[placeholderIndex], text: $text, axis: .vertical)
                .font(.body)
                .lineLimit(1...3)
                .focused($isFocused)
                .submitLabel(.search)
                .onSubmit { onSubmit() }
                .accessibilityLabel("Smart community search")
                .accessibilityHint("Describe what kind of church, group, or community you're looking for")

            if isLoading {
                AMENLoader.inline
                    .accessibilityLabel("Searching")
            } else if !text.isEmpty {
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(reduceTransparency ? AnyShapeStyle(Color(.systemBackground)) : AnyShapeStyle(.ultraThinMaterial))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isFocused ? Color.accentColor.opacity(0.5) : Color(.separator).opacity(0.3), lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.2), value: isFocused)
        .task {
            // Cycle placeholder prompts every 4 seconds when idle
            while true {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                guard text.isEmpty && !isFocused else { continue }
                placeholderIndex = (placeholderIndex + 1) % placeholderPrompts.count
            }
        }
    }
}
