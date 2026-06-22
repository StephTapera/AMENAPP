import Foundation

protocol SearchQueryRouting {
    func makePlan(
        for query: String,
        entities: Set<SocialV2SearchEntity>,
        privacy: SocialV2AIPrivacyToggles
    ) -> SearchQueryPlan?
}

struct SearchQueryPlan: Equatable, Hashable {
    let query: String
    let entities: Set<SocialV2SearchEntity>
    let privacy: SocialV2AIPrivacyToggles

    var isEnabled: Bool {
        privacy.searchEnabled && !query.isEmpty && !entities.isEmpty
    }
}

struct SearchQueryRouter: SearchQueryRouting {
    func makePlan(
        for query: String,
        entities: Set<SocialV2SearchEntity>,
        privacy: SocialV2AIPrivacyToggles
    ) -> SearchQueryPlan? {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let plan = SearchQueryPlan(
            query: trimmedQuery,
            entities: entities,
            privacy: privacy
        )

        return plan.isEnabled ? plan : nil
    }
}

struct SearchSampleResult: Identifiable, Equatable, Hashable {
    let id: SocialV2Identifier
    let entity: SocialV2SearchEntity
    let title: String
    let summary: String
}

struct SearchHomeState: Equatable, Hashable {
    var privacy: SocialV2AIPrivacyToggles
    var suggestedQuery: String
    var selectedEntities: Set<SocialV2SearchEntity>
    var sampleResults: [SearchSampleResult]

    func visibleResults(for plan: SearchQueryPlan?) -> [SearchSampleResult] {
        guard let plan else { return [] }

        return sampleResults.filter { result in
            plan.entities.contains(result.entity)
        }
    }
}

extension SearchHomeState {
    static let sampleEnabled = SearchHomeState(
        privacy: SocialV2AIPrivacyToggles(
            recommendationsEnabled: true,
            personalizationEnabled: true,
            assistantsEnabled: true,
            searchEnabled: true
        ),
        suggestedQuery: "youth worship night",
        selectedEntities: Set(SocialV2SearchEntity.allCases),
        sampleResults: [
            SearchSampleResult(
                id: "search-sample-post-1",
                entity: .posts,
                title: "Post: youth worship night recap",
                summary: "Community updates, photos, and prayer requests from recent gatherings."
            ),
            SearchSampleResult(
                id: "search-sample-video-1",
                entity: .videos,
                title: "Video: acoustic worship set",
                summary: "Short-form clips and longer teaching moments connected to the query."
            ),
            SearchSampleResult(
                id: "search-sample-space-1",
                entity: .spaces,
                title: "Space: local youth leaders",
                summary: "Groups and communities where related conversations are happening."
            )
        ]
    )

    static let sampleDisabled = SearchHomeState(
        privacy: .allOff,
        suggestedQuery: "",
        selectedEntities: Set(SocialV2SearchEntity.allCases),
        sampleResults: []
    )
}
