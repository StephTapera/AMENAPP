import SwiftUI

struct SocialV2SettingsCenterView: View {
    let entries: [SocialV2SettingsEntry]

    init(entries: [SocialV2SettingsEntry] = SocialV2SettingsSampleData.entries) {
        self.entries = entries
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    settingsRow(title: "Account", subtitle: "Profile, identity, and organizations", systemImage: "person.crop.circle")
                    settingsRow(title: "Security", subtitle: "Sessions, devices, and login protection", systemImage: "lock.shield")
                }

                Section("Experience") {
                    settingsRow(title: "Appearance", subtitle: "White canvas and Liquid Glass preferences", systemImage: "sparkles")
                    settingsRow(title: "Accessibility", subtitle: "Motion, transparency, captions, and touch targets", systemImage: "accessibility")
                    settingsRow(title: "Notifications", subtitle: "Communities, messages, and reminders", systemImage: "bell")
                }

                Section("Social V2 Modules") {
                    ForEach(entries) { entry in
                        settingsRow(title: entry.title, subtitle: entry.subtitle, systemImage: entry.systemImage)
                    }
                }

                Section("Data & Safety") {
                    settingsRow(title: "AI Features", subtitle: "Recommendations, personalization, assistants, and search", systemImage: "brain")
                    settingsRow(title: "Data & Storage", subtitle: "Downloads, saved items, and cache", systemImage: "externaldrive")
                    settingsRow(title: "Safety Center", subtitle: "Account status, appeals, and review history", systemImage: "shield.lefthalf.filled")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.white)
            .navigationTitle("Settings")
        }
    }

    private func settingsRow(title: String, subtitle: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(.blue)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .listRowBackground(Color.white.opacity(0.72))
    }
}

private enum SocialV2SettingsSampleData {
    static let entries = [
        SocialV2SettingsEntry(
            id: "settings-spaces",
            title: "Communities",
            subtitle: "Spaces, membership, local privacy, and moderation",
            systemImage: "person.3",
            route: SocialV2Route(id: "settings-spaces-route", title: "Communities", systemImage: "person.3")
        ),
        SocialV2SettingsEntry(
            id: "settings-messages",
            title: "Messages",
            subtitle: "Safety scanning, summaries, and group coordination",
            systemImage: "bubble.left.and.bubble.right",
            route: SocialV2Route(id: "settings-messages-route", title: "Messages", systemImage: "bubble.left.and.bubble.right")
        ),
        SocialV2SettingsEntry(
            id: "settings-privacy",
            title: "Privacy",
            subtitle: "Visibility, AI toggles, location scope, and reports",
            systemImage: "hand.raised",
            route: SocialV2Route(id: "settings-privacy-route", title: "Privacy", systemImage: "hand.raised")
        )
    ]
}
