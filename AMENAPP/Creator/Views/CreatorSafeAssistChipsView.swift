import SwiftUI

struct CreatorSafeAssistChipsView: View {
    let suggestions: [CreatorSuggestion]
    var onSelect: ((CreatorSuggestion) -> Void)? = nil

    @State private var selectedIDs: Set<String> = []

    var body: some View {
        AMENFlowLayout(spacing: 8) {
            ForEach(suggestions) { suggestion in
                CreatorToggleChip(
                    title: suggestion.title,
                    isSelected: selectedIDs.contains(suggestion.id),
                    action: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        if selectedIDs.contains(suggestion.id) {
                            selectedIDs.remove(suggestion.id)
                        } else {
                            selectedIDs.insert(suggestion.id)
                            onSelect?(suggestion)
                        }
                    }
                )
            }
        }
    }
}
