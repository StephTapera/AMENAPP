//
//  RemoteKillSwitch.swift
//  AMENAPP
//
//  Feature 57: Remote Kill Switch via Firebase Remote Config.
//  Disable features remotely without an App Store update.
//

import Foundation
import FirebaseRemoteConfig

@MainActor
class RemoteKillSwitch: ObservableObject {
    static let shared = RemoteKillSwitch()

    @Published var feedEnabled = true
    @Published var bereanEnabled = true
    @Published var messagingEnabled = true
    @Published var createPostEnabled = true
    @Published var searchEnabled = true
    @Published var notificationsEnabled = true

    @Published var maintenanceMode = false
    @Published var maintenanceMessage = ""
    @Published var minimumAppVersion = "1.0"

    private init() {
        loadFlags()
    }

    func loadFlags() {
        let config = RemoteConfig.remoteConfig()

        feedEnabled = config.configValue(forKey: "kill_feed_enabled").boolValue
        bereanEnabled = config.configValue(forKey: "kill_berean_enabled").boolValue
        messagingEnabled = config.configValue(forKey: "kill_messaging_enabled").boolValue
        createPostEnabled = config.configValue(forKey: "kill_create_post_enabled").boolValue
        searchEnabled = config.configValue(forKey: "kill_search_enabled").boolValue
        notificationsEnabled = config.configValue(forKey: "kill_notifications_enabled").boolValue

        maintenanceMode = config.configValue(forKey: "maintenance_mode").boolValue
        maintenanceMessage = config.configValue(forKey: "maintenance_message").stringValue ?? ""
        minimumAppVersion = config.configValue(forKey: "minimum_app_version").stringValue ?? "1.0"

        // Default: all enabled if Remote Config hasn't been set
        if config.lastFetchStatus == .noFetchYet {
            feedEnabled = true
            bereanEnabled = true
            messagingEnabled = true
            createPostEnabled = true
            searchEnabled = true
            notificationsEnabled = true
        }
    }

    /// Check if current app version meets minimum requirement.
    var isAppVersionValid: Bool {
        let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return current.compare(minimumAppVersion, options: .numeric) != .orderedAscending
    }
}
