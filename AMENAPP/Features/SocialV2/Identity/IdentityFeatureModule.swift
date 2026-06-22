import SwiftUI

enum IdentityFeatureModule: SocialV2FeatureModule {
    static let id = "social-v2-identity"
    static let flag: SocialV2FeatureFlag = .socialV2Identity

    static let routes = [
        SocialV2Route(id: "social-v2-identity-root", title: "Identity Hub", systemImage: "person.crop.circle")
    ]

    static let settingsEntries = [
        SocialV2SettingsEntry(
            id: "social-v2-identity-settings",
            title: "Identity Hub",
            subtitle: "Profile sections, interests, ministries, and trust signals",
            systemImage: "person.crop.circle",
            route: routes[0]
        )
    ]

    static let tabEntry: SocialV2TabEntry? = SocialV2TabEntry(
        id: "social-v2-identity-tab",
        title: "Profile",
        systemImage: "person.crop.circle",
        selectedSystemImage: "person.crop.circle.fill",
        route: routes[0]
    )

    @MainActor
    static func makeRoot() -> AnyView {
        AnyView(IdentityHubView())
    }
}
