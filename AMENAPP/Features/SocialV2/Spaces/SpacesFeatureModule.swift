import SwiftUI

enum SpacesFeatureModule: SocialV2FeatureModule {
    static let id = "social-v2-spaces"
    static let flag: SocialV2FeatureFlag = .socialV2Spaces

    static let routes: [SocialV2Route] = [
        SocialV2Route(
            id: "social-v2-spaces-home",
            title: "Spaces",
            systemImage: "person.3"
        )
    ]

    static let settingsEntries: [SocialV2SettingsEntry] = [
        SocialV2SettingsEntry(
            id: "social-v2-spaces-settings",
            title: "Spaces",
            subtitle: "Manage local scope, moderation visibility, and space discovery.",
            systemImage: "person.3",
            route: routes[0]
        )
    ]

    static let tabEntry: SocialV2TabEntry? = SocialV2TabEntry(
        id: "social-v2-spaces-tab",
        title: "Spaces",
        systemImage: "person.3",
        selectedSystemImage: "person.3.fill",
        route: routes[0]
    )

    @MainActor
    static func makeRoot() -> AnyView {
        AnyView(SpacesHomeView())
    }
}
