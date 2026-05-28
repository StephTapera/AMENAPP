import SwiftUI

struct SmartCommunitySearchEmptyState: View {
    let query: String
    let suggestions: [String]
    let onSuggestionTapped: (String) -> Void

    private let examples = [
        "Young adult church near me with worship",
        "Small groups focused on Bible study",
        "Church with recovery ministry and community",
        "Family-friendly church with childcare",
        "Diverse congregation with Spanish service",
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Spacer(minLength: 20)

                // Icon + message
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass.circle")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)

                    Text("No results for \u{201C}\(query)\u{201D}")
                        .font(.headline)
                        .multilineTextAlignment(.center)

                    Text("Try refining your search or use one of the suggestions below.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal)

                // Refinement chips if available
                if !suggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Try refining")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 16)
                        SmartCommunityRefinementChips(chips: suggestions, onChipTapped: onSuggestionTapped)
                    }
                }

                // Example searches
                VStack(alignment: .leading, spacing: 10) {
                    Text("Search examples")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)

                    ForEach(examples, id: \.self) { example in
                        Button {
                            onSuggestionTapped(example)
                        } label: {
                            HStack {
                                Image(systemName: "arrow.up.left")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                                Text(example)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                        }
                        .accessibilityLabel("Try search: \(example)")
                    }
                }

                Spacer(minLength: 40)
            }
        }
    }
}
