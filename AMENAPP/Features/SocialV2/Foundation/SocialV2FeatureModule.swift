import SwiftUI

enum SocialV2FeatureFlag: String, CaseIterable, Identifiable {
    case socialV2Foundation
    case socialV2Spaces
    case socialV2Feeds
    case socialV2Search
    case socialV2Messaging
    case socialV2Identity
    case socialV2PrivacySafety
    case socialV2VaultNotes
    case socialV2Settings

    var id: String { rawValue }

    var defaultValue: Bool { false }
}

struct SocialV2Route: Hashable, Identifiable {
    let id: String
    let title: String
    let systemImage: String
}

struct SocialV2SettingsEntry: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let route: SocialV2Route
}

struct SocialV2TabEntry: Identifiable, Hashable {
    let id: String
    let title: String
    let systemImage: String
    let selectedSystemImage: String
    let route: SocialV2Route
}

protocol SocialV2FeatureModule {
    static var id: String { get }
    static var flag: SocialV2FeatureFlag { get }
    static var routes: [SocialV2Route] { get }
    static var settingsEntries: [SocialV2SettingsEntry] { get }
    static var tabEntry: SocialV2TabEntry? { get }

    @MainActor
    static func makeRoot() -> AnyView
}

@MainActor
final class SocialV2FeatureRegistry: ObservableObject {
    static let shared = SocialV2FeatureRegistry()

    @Published private(set) var modules: [any SocialV2FeatureModule.Type] = []
    private var moduleIDs: Set<String> = []

    private init() {}

    func register(_ module: any SocialV2FeatureModule.Type) {
        guard moduleIDs.insert(module.id).inserted else { return }
        modules.append(module)
    }

    var routes: [SocialV2Route] {
        modules.flatMap { module in module.routes }
    }

    var settingsEntries: [SocialV2SettingsEntry] {
        modules.flatMap { module in module.settingsEntries }
    }

    var tabEntries: [SocialV2TabEntry] {
        modules.compactMap { module in module.tabEntry }
    }

    func module(id: String) -> (any SocialV2FeatureModule.Type)? {
        modules.first { $0.id == id }
    }
}

enum SocialV2FoundationModule: SocialV2FeatureModule {
    static let id = "social-v2-foundation"
    static let flag: SocialV2FeatureFlag = .socialV2Foundation
    static let routes: [SocialV2Route] = []
    static let settingsEntries: [SocialV2SettingsEntry] = []
    static let tabEntry: SocialV2TabEntry? = nil

    @MainActor
    static func makeRoot() -> AnyView {
        AnyView(EmptyView())
    }
}
