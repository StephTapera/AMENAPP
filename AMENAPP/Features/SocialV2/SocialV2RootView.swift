import SwiftUI

struct SocialV2RootView: View {
    @State private var selectedSection: SocialV2RootSection = .spaces

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                sectionPicker
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                Divider()

                selectedSectionView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color.white)
            .navigationTitle(selectedSection.title)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(SocialV2RootSection.allCases) { section in
                            Button {
                                selectedSection = section
                            } label: {
                                Label(section.title, systemImage: section.systemImage)
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Social V2 sections")
                }
            }
        }
    }

    private var sectionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SocialV2RootSection.allCases) { section in
                    Button {
                        selectedSection = section
                    } label: {
                        SocialV2GlassPill(
                            tintContext: section.tintContext,
                            isSelected: selectedSection == section
                        ) {
                            Label(section.title, systemImage: section.systemImage)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedSection == section ? .isSelected : [])
                }
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private var selectedSectionView: some View {
        switch selectedSection {
        case .spaces:
            SpacesHomeView()
        case .feeds:
            FeedsHomeView()
        case .search:
            SearchHomeView()
        case .messaging:
            MessagingHomeView()
        case .identity:
            IdentityHubView()
        case .privacySafety:
            PrivacySafetyCenterView()
        case .vaultNotes:
            VaultNotesHomeView()
        case .settings:
            SocialV2SettingsCenterView(entries: socialV2SettingsEntries)
        }
    }

    private var socialV2SettingsEntries: [SocialV2SettingsEntry] {
        [
            SpacesFeatureModule.settingsEntries,
            FeedsFeatureModule.settingsEntries,
            SearchFeatureModule.settingsEntries,
            MessagingFeatureModule.settingsEntries,
            IdentityFeatureModule.settingsEntries,
            PrivacySafetyFeatureModule.settingsEntries,
            VaultNotesFeatureModule.settingsEntries,
            SocialV2SettingsFeatureModule.settingsEntries
        ].flatMap { $0 }
    }
}

private enum SocialV2RootSection: String, CaseIterable, Identifiable {
    case spaces
    case feeds
    case search
    case messaging
    case identity
    case privacySafety
    case vaultNotes
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .spaces: return "Spaces"
        case .feeds: return "Feeds"
        case .search: return "Search"
        case .messaging: return "Messages"
        case .identity: return "Identity"
        case .privacySafety: return "Safety"
        case .vaultNotes: return "Vault"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .spaces: return "person.3"
        case .feeds: return "list.bullet.rectangle"
        case .search: return "magnifyingglass"
        case .messaging: return "bubble.left.and.bubble.right"
        case .identity: return "person.crop.circle"
        case .privacySafety: return "shield.lefthalf.filled"
        case .vaultNotes: return "archivebox"
        case .settings: return "gearshape"
        }
    }

    var tintContext: SocialV2GlassTintContext {
        switch self {
        case .privacySafety, .vaultNotes:
            return .state
        default:
            return .interactive
        }
    }
}

#if DEBUG
#Preview("Social V2 Root") {
    SocialV2RootView()
}
#endif
