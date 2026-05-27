import Foundation

// MARK: - ProRoleSurface Protocol

public protocol ProRoleSurface {
    var role: ProRole { get }
    var priority: Int { get }
    func currentInsight(for userId: String) async -> ProInsight?
}

// MARK: - ProInsight

public struct ProInsight: Hashable {
    public let line: String
    public let deepLinkPath: String

    public init(line: String, deepLinkPath: String) {
        self.line = line
        self.deepLinkPath = deepLinkPath
    }
}
