import Foundation

// Call this after your Firebase Remote Config fetch completes.
// Pass in the fetched values as a [String: Bool] dictionary.
//
// Usage in AMENAPPApp.setupRemoteConfig():
//
//   remoteConfig.activate { _, _ in
//       let values = CommunicationOSRemoteConfigBridge.allFlagKeys.reduce(into: [String: Bool]()) { dict, key in
//           dict[key] = remoteConfig.configValue(forKey: key).boolValue
//       }
//       CommunicationOSRemoteConfigBridge.applyRemoteConfig(values)
//   }

struct CommunicationOSRemoteConfigBridge {
    static func applyRemoteConfig(_ values: [String: Bool]) {
        Task { @MainActor in
            CommunicationOSFeatureFlags.shared.configure(from: values)
            PostingOSFeatureFlags.shared.configure(from: values)
        }
    }

    // Keys to fetch from Remote Config.
    // All flags default OFF in code; set to true in Firebase Console to enable.
    static let allFlagKeys: [String] = [
        "smartMessageContextEnabled",
        "conversationMemoryEnabled",
        "privateContactNotesEnabled",
        "smartReminderDetectionEnabled",
        "smartMusicDetectionEnabled",
        "smartLinkDetectionEnabled",
        "smartAttachmentMenuEnabled",
        "liquidGlassMessagingEnabled",
        "smartPostContextEnabled",
        "textModerationEnabled",
        "imageModerationEnabled",
        "smartThreadMiniSummaryEnabled",
        "nvidiaSafetyProviderEnabled",
    ]
}
