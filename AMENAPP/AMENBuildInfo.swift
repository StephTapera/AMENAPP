import Foundation

struct AMENBuildInfo {
    static let gitSHA = Bundle.main.object(forInfoDictionaryKey: "AMENBuildGitSHA") as? String ?? "unknown"
    static let gitBranch = Bundle.main.object(forInfoDictionaryKey: "AMENBuildGitBranch") as? String ?? "unknown"
    static let gitDirtyState = Bundle.main.object(forInfoDictionaryKey: "AMENBuildGitDirty") as? String ?? "unknown"

    static var shortSHA: String {
        guard gitSHA.count > 12 else { return gitSHA }
        return String(gitSHA.prefix(12))
    }

    static var displaySummary: String {
        "\(gitBranch) @ \(shortSHA) [\(gitDirtyState)]"
    }

    static func logLaunchStamp() {
        dlog("[BuildInfo] \(displaySummary)")
    }
}
