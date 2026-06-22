import SwiftUI

enum SocialV2SettingsFeatureModule: SocialV2FeatureModule {
    static let id = "social-v2-settings"
    static let flag: SocialV2FeatureFlag = .socialV2Settings

    static let routes = [
        SocialV2Route(id: "social-v2-settings-root", title: "Social Settings", systemImage: "gearshape")
    ]

    static let settingsEntries = [
        SocialV2SettingsEntry(
            id: "social-v2-settings-entry",
            title: "Social V2",
            subtitle: "Account, privacy, communities, messages, AI features, and safety",
            systemImage: "gearshape",
            route: routes[0]
        )
    ]

    static let tabEntry: SocialV2TabEntry? = nil

    @MainActor
    static func makeRoot() -> AnyView {
        AnyView(SocialV2SettingsCenterView())
    }
}
