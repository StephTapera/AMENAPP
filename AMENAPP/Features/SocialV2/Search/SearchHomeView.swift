import SwiftUI

struct SearchHomeView: View {
    private let state: SearchHomeState
    private let router: any SearchQueryRouting

    init(
        state: SearchHomeState = .sampleEnabled,
        router: any SearchQueryRouting = SearchQueryRouter()
    ) {
        self.state = state
        self.router = router
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerCard
                filterCard
                resultsCard
            }
            .padding(20)
        }
        .background(Color.white)
    }

    private var activePlan: SearchQueryPlan? {
        router.makePlan(
            for: query,
            entities: state.selectedEntities,
            privacy: state.privacy
        )
    }

    private var visibleResults: [SearchSampleResult] {
        state.visibleResults(for: activePlan)
    }

    private var query: String {
        if state.privacy.searchEnabled {
            return state.suggestedQuery
        }

        return ""
    }

    private var headerCard: some View {
        SocialV2GlassCard(tintContext: state.privacy.searchEnabled ? .interactive : .neutral, isActive: state.privacy.searchEnabled) {
            VStack(alignment: .leading, spacing: 12) {
                Label("AI Search", systemImage: "magnifyingglass")
                    .font(.title2.weight(.bold))

                TextField("Search AMEN", text: .constant(query))
                    .autocorrectionDisabled()
                    .disabled(!state.privacy.searchEnabled)
                    .textFieldStyle(.roundedBorder)

                Text(statusText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var filterCard: some View {
        SocialV2GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Filters")
                    .font(.headline)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(SocialV2SearchEntity.allCases) { entity in
                        Button {
                            route(entity)
                        } label: {
                            SocialV2GlassPill(isSelected: state.selectedEntities.contains(entity)) {
                                Text(entity.searchDisplayName)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(!state.privacy.searchEnabled)
                        .accessibilityLabel(entity.searchDisplayName)
                    }
                }
            }
        }
    }

    private var resultsCard: some View {
        SocialV2GlassCard(tintContext: visibleResults.isEmpty ? .neutral : .state, isActive: !visibleResults.isEmpty) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Results")
                    .font(.headline)

                if visibleResults.isEmpty {
                    Text(emptyResultsText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(visibleResults) { result in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(result.title)
                                .font(.subheadline.weight(.semibold))

                            Text(result.summary)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
        }
    }

    private var statusText: String {
        if state.privacy.searchEnabled {
            return "Search routes only selected content types."
        }

        return "AI search is off in privacy settings."
    }

    private var emptyResultsText: String {
        if !state.privacy.searchEnabled {
            return "Enable AI search to search across AMEN."
        }

        if activePlan == nil {
            return "Enter a query and choose at least one filter."
        }

        return "No sample results match the selected filters."
    }

    private func route(_ entity: SocialV2SearchEntity) {
        _ = router.makePlan(
            for: query,
            entities: [entity],
            privacy: state.privacy
        )
    }
}

private extension SocialV2SearchEntity {
    var searchDisplayName: String {
        switch self {
        case .posts:
            return "Posts"
        case .videos:
            return "Videos"
        case .spaces:
            return "Spaces"
        case .events:
            return "Events"
        case .resources:
            return "Resources"
        case .churches:
            return "Churches"
        case .podcasts:
            return "Podcasts"
        case .people:
            return "People"
        case .messages:
            return "Messages"
        case .prayers:
            return "Prayers"
        case .notes:
            return "Notes"
        }
    }
}
