import SwiftUI

struct CreatorSafeAssistChipsView: View {
    let suggestions: [CreatorSuggestion]

    var body: some View {
        AMENFlowLayout(spacing: 8) {
            ForEach(suggestions) { suggestion in
                CreatorToggleChip(title: suggestion.title, isSelected: false, action: {})
            }
        }
    }
}
