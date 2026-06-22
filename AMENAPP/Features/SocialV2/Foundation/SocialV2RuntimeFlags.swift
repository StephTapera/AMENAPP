import Foundation

@MainActor
final class SocialV2RuntimeFlags: ObservableObject {
    static let shared = SocialV2RuntimeFlags()

    private static let socialV2EnabledKey = "social_v2_enabled"
    private static let smokeLaunchArgument = "-SocialV2Enabled"

    @Published private(set) var isSocialV2Enabled: Bool

    private init(defaults: UserDefaults = .standard, arguments: [String] = ProcessInfo.processInfo.arguments) {
        if let argumentIndex = arguments.firstIndex(of: Self.smokeLaunchArgument),
           arguments.indices.contains(argumentIndex + 1) {
            let value = arguments[argumentIndex + 1].lowercased()
            isSocialV2Enabled = ["1", "true", "yes", "on"].contains(value)
        } else {
            isSocialV2Enabled = defaults.bool(forKey: Self.socialV2EnabledKey)
        }
    }

    func setSocialV2Enabled(_ enabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: Self.socialV2EnabledKey)
        isSocialV2Enabled = enabled
    }
}
