// DiscussionModeService.swift — AMEN App
import Foundation
import FirebaseRemoteConfig

@MainActor
final class DiscussionModeService {
    static let shared = DiscussionModeService()
    private init() {}

    private(set) var currentMode: DiscussionMode = .general

    private var isEnabled: Bool {
        RemoteConfig.remoteConfig().configValue(forKey: "discussion_modes_enabled").boolValue
    }

    func availableModes() -> [DiscussionMode] {
        guard isEnabled else { return [.general] }
        return DiscussionMode.allCases
    }

    func setMode(_ mode: DiscussionMode) {
        guard isEnabled else { return }
        currentMode = mode
    }
}
