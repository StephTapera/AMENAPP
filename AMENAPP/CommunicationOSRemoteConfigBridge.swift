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

// All flags default ON. Set a key to false in Firebase Remote Config to disable remotely.
private func commOSFlag(_ key: String) -> Bool {
    (UserDefaults.standard.object(forKey: key) as? Bool) ?? true
}

@MainActor
final class CommunicationOSFeatureFlags: ObservableObject {
    static let shared = CommunicationOSFeatureFlags()
    private init() {}

    @Published var smartMessageContextEnabled: Bool = commOSFlag("smartMessageContextEnabled")
    @Published var conversationMemoryEnabled: Bool = commOSFlag("conversationMemoryEnabled")
    @Published var privateContactNotesEnabled: Bool = commOSFlag("privateContactNotesEnabled")
    @Published var smartReminderDetectionEnabled: Bool = commOSFlag("smartReminderDetectionEnabled")
    @Published var smartMusicDetectionEnabled: Bool = commOSFlag("smartMusicDetectionEnabled")
    @Published var smartLinkDetectionEnabled: Bool = commOSFlag("smartLinkDetectionEnabled")
    @Published var smartAttachmentMenuEnabled: Bool = commOSFlag("smartAttachmentMenuEnabled")
    @Published var liquidGlassMessagingEnabled: Bool = commOSFlag("liquidGlassMessagingEnabled")
    @Published var ragSearchEnabled: Bool = commOSFlag("ragSearchEnabled")

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
        ragSearchEnabled = remoteConfig["ragSearchEnabled"] ?? ragSearchEnabled
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
    // All flags default ON in code; set to false in Firebase Console to disable remotely.
    // GAP A5-P1 removed dead RC keys: smartThreadMiniSummaryEnabled, nvidiaSafetyProviderEnabled
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
        "ragSearchEnabled",
    ]
}
