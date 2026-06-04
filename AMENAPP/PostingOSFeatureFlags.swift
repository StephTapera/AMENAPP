import Foundation

@MainActor
final class PostingOSFeatureFlags: ObservableObject {
    static let shared = PostingOSFeatureFlags()
    private init() {}

    @Published var smartPostContextEnabled: Bool = (UserDefaults.standard.object(forKey: "smartPostContextEnabled") as? Bool) ?? true
    @Published var textModerationEnabled: Bool = (UserDefaults.standard.object(forKey: "textModerationEnabled") as? Bool) ?? true
    @Published var imageModerationEnabled: Bool = (UserDefaults.standard.object(forKey: "imageModerationEnabled") as? Bool) ?? true

    func configure(from remoteConfig: [String: Bool]) {
        smartPostContextEnabled = remoteConfig["smartPostContextEnabled"] ?? smartPostContextEnabled
        textModerationEnabled = remoteConfig["textModerationEnabled"] ?? textModerationEnabled
        imageModerationEnabled = remoteConfig["imageModerationEnabled"] ?? imageModerationEnabled
    }
}
