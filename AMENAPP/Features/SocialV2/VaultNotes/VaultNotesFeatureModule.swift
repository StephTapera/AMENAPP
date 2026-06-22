import SwiftUI

enum VaultNotesFeatureModule: SocialV2FeatureModule {
    static let id = "social-v2-vault-notes"
    static let flag: SocialV2FeatureFlag = .socialV2VaultNotes

    static let routes = [
        SocialV2Route(id: "social-v2-vault-notes-root", title: "Knowledge Vault", systemImage: "archivebox")
    ]

    static let settingsEntries = [
        SocialV2SettingsEntry(
            id: "social-v2-vault-notes-settings",
            title: "Knowledge Vault",
            subtitle: "Saved knowledge, AI collections, and reviewed context notes",
            systemImage: "archivebox",
            route: routes[0]
        )
    ]

    static let tabEntry: SocialV2TabEntry? = SocialV2TabEntry(
        id: "social-v2-vault-notes-tab",
        title: "Vault",
        systemImage: "archivebox",
        selectedSystemImage: "archivebox.fill",
        route: routes[0]
    )

    @MainActor
    static func makeRoot() -> AnyView {
        AnyView(VaultNotesHomeView())
    }
}
