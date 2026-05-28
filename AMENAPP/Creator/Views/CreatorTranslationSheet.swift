import SwiftUI

struct CreatorTranslationSheet: View {
    let availableLanguages: [String]

    var body: some View {
        VStack(spacing: 12) {
            CreatorTopBar(title: "Translate", subtitle: "Choose a language")

            ForEach(availableLanguages, id: \.self) { language in
                CreatorGlassCard {
                    Text(language)
                        .font(AMENFont.semiBold(14))
                }
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
    }
}
