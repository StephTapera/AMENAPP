import SwiftUI

enum SearchFeatureModule: SocialV2FeatureModule {
    static let id = "social-v2-search"
    static let flag: SocialV2FeatureFlag = .socialV2Search

    static let routes: [SocialV2Route] = [
        SocialV2Route(
            id: "social-v2-search-home",
            title: "AI Search",
            systemImage: "magnifyingglass"
        )
    ]

    static let settingsEntries: [SocialV2SettingsEntry] = [
        SocialV2SettingsEntry(
            id: "social-v2-search-settings",
            title: "AI Search",
            subtitle: "Search across social content when AI search is enabled.",
            systemImage: "magnifyingglass",
            route: routes[0]
        )
    ]

    static let tabEntry: SocialV2TabEntry? = SocialV2TabEntry(
        id: "social-v2-search-tab",
        title: "Search",
        systemImage: "magnifyingglass",
        selectedSystemImage: "magnifyingglass.circle.fill",
        route: routes[0]
    )

    @MainActor
    static func makeRoot() -> AnyView {
        AnyView(SearchHomeView(state: .sampleEnabled))
    }
}
