import Foundation

@MainActor
final class PostingOSFeatureFlags: ObservableObject {
    static let shared = PostingOSFeatureFlags()
    private init() {}

    @Published var smartPostContextEnabled: Bool = UserDefaults.standard.bool(forKey: "smartPostContextEnabled")
    @Published var textModerationEnabled: Bool = UserDefaults.standard.bool(forKey: "textModerationEnabled")
    @Published var imageModerationEnabled: Bool = UserDefaults.standard.bool(forKey: "imageModerationEnabled")

    func configure(from remoteConfig: [String: Bool]) {
        smartPostContextEnabled = remoteConfig["smartPostContextEnabled"] ?? smartPostContextEnabled
        textModerationEnabled = remoteConfig["textModerationEnabled"] ?? textModerationEnabled
        imageModerationEnabled = remoteConfig["imageModerationEnabled"] ?? imageModerationEnabled
    }
}
