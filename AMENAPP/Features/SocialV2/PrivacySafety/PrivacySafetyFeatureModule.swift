import SwiftUI

enum PrivacySafetyFeatureModule: SocialV2FeatureModule {
    static let id = "social-v2-privacy-safety"
    static let flag: SocialV2FeatureFlag = .socialV2PrivacySafety

    static let routes = [
        SocialV2Route(id: "social-v2-privacy-safety-root", title: "Privacy & Safety", systemImage: "shield.lefthalf.filled")
    ]

    static let settingsEntries = [
        SocialV2SettingsEntry(
            id: "social-v2-privacy-safety-settings",
            title: "Privacy & Safety",
            subtitle: "AI controls, location privacy, account status, and appeals",
            systemImage: "shield.lefthalf.filled",
            route: routes[0]
        )
    ]

    static let tabEntry: SocialV2TabEntry? = nil

    @MainActor
    static func makeRoot() -> AnyView {
        AnyView(PrivacySafetyCenterView())
    }
}
