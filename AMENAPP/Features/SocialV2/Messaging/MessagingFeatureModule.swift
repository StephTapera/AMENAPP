import SwiftUI

enum MessagingFeatureModule: SocialV2FeatureModule {
    static let id = "social-v2-messaging"
    static let flag: SocialV2FeatureFlag = .socialV2Messaging

    static let routes = [
        SocialV2Route(id: "social-v2-messaging-root", title: "Messages", systemImage: "bubble.left.and.bubble.right")
    ]

    static let settingsEntries = [
        SocialV2SettingsEntry(
            id: "social-v2-messaging-settings",
            title: "Messages",
            subtitle: "Safety scanning, summaries, and group coordination",
            systemImage: "bubble.left.and.bubble.right",
            route: routes[0]
        )
    ]

    static let tabEntry: SocialV2TabEntry? = SocialV2TabEntry(
        id: "social-v2-messaging-tab",
        title: "Messages",
        systemImage: "bubble.left.and.bubble.right",
        selectedSystemImage: "bubble.left.and.bubble.right.fill",
        route: routes[0]
    )

    @MainActor
    static func makeRoot() -> AnyView {
        AnyView(MessagingHomeView())
    }
}
