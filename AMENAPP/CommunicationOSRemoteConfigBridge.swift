import Foundation
import Combine

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

@MainActor
final class CommunicationOSFeatureFlags: ObservableObject {
    static let shared = CommunicationOSFeatureFlags()
    private init() {}

    @Published var smartMessageContextEnabled: Bool = UserDefaults.standard.bool(forKey: "smartMessageContextEnabled")
    @Published var conversationMemoryEnabled: Bool = UserDefaults.standard.bool(forKey: "conversationMemoryEnabled")
    @Published var privateContactNotesEnabled: Bool = UserDefaults.standard.bool(forKey: "privateContactNotesEnabled")
    @Published var smartReminderDetectionEnabled: Bool = UserDefaults.standard.bool(forKey: "smartReminderDetectionEnabled")
    @Published var smartMusicDetectionEnabled: Bool = UserDefaults.standard.bool(forKey: "smartMusicDetectionEnabled")
    @Published var smartLinkDetectionEnabled: Bool = UserDefaults.standard.bool(forKey: "smartLinkDetectionEnabled")
    @Published var smartAttachmentMenuEnabled: Bool = UserDefaults.standard.bool(forKey: "smartAttachmentMenuEnabled")
    @Published var liquidGlassMessagingEnabled: Bool = UserDefaults.standard.bool(forKey: "liquidGlassMessagingEnabled")

    func configure(from remoteConfig: [String: Bool]) {
        for (key, value) in remoteConfig {
            UserDefaults.standard.set(value, forKey: key)
        }
        smartMessageContextEnabled = remoteConfig["smartMessageContextEnabled"] ?? smartMessageContextEnabled
        conversationMemoryEnabled = remoteConfig["conversationMemoryEnabled"] ?? conversationMemoryEnabled
        privateContactNotesEnabled = remoteConfig["privateContactNotesEnabled"] ?? privateContactNotesEnabled
        smartReminderDetectionEnabled = remoteConfig["smartReminderDetectionEnabled"] ?? smartReminderDetectionEnabled
        smartMusicDetectionEnabled = remoteConfig["smartMusicDetectionEnabled"] ?? smartMusicDetectionEnabled
        smartLinkDetectionEnabled = remoteConfig["smartLinkDetectionEnabled"] ?? smartLinkDetectionEnabled
        smartAttachmentMenuEnabled = remoteConfig["smartAttachmentMenuEnabled"] ?? smartAttachmentMenuEnabled
        liquidGlassMessagingEnabled = remoteConfig["liquidGlassMessagingEnabled"] ?? liquidGlassMessagingEnabled
    }
}

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
