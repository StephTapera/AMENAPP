import SwiftUI

struct CreatorSceneSuggestionsView: View {
    let suggestions: [CreatorSuggestion]

    var body: some View {
        VStack(spacing: 10) {
            ForEach(suggestions) { suggestion in
                CreatorGlassCard {
                    Text(suggestion.title)
                        .font(AMENFont.medium(13))
                        .foregroundStyle(Color.black.opacity(0.7))
                }
            }
        }
    }
}
