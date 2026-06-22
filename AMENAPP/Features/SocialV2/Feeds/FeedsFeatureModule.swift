import SwiftUI

enum FeedsFeatureModule: SocialV2FeatureModule {
    static let id = "social-v2-feeds"
    static let flag: SocialV2FeatureFlag = .socialV2Feeds

    static let routes: [SocialV2Route] = [
        SocialV2Route(
            id: "social-v2-feeds-home",
            title: "Feeds",
            systemImage: "rectangle.stack"
        )
    ]

    static let settingsEntries: [SocialV2SettingsEntry] = [
        SocialV2SettingsEntry(
            id: "social-v2-feeds-calm-mode",
            title: "Calm Mode",
            subtitle: "Prefer helpful and educational posts over outrage-driven threads.",
            systemImage: "leaf",
            route: routes[0]
        )
    ]

    static let tabEntry: SocialV2TabEntry? = SocialV2TabEntry(
        id: "social-v2-feeds",
        title: "Feeds",
        systemImage: "rectangle.stack",
        selectedSystemImage: "rectangle.stack.fill",
        route: routes[0]
    )

    @MainActor
    static func makeRoot() -> AnyView {
        AnyView(FeedsHomeView())
    }
}
