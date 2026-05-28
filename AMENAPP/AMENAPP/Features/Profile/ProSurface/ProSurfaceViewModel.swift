import Foundation
import Observation

// MARK: - ProSurfaceViewModel

@MainActor
@Observable
final class ProSurfaceViewModel {

    // MARK: State

    private(set) var insight: ProInsight? = nil
    private(set) var activeRole: ProRole? = nil
    private(set) var isResolving: Bool = false

    // MARK: Dependencies

    private let userId: String
    private let roleFlags: ProfileRoleFlags
    private let resolver: ProSurfaceResolver

    // MARK: Init

    init(userId: String, roleFlags: ProfileRoleFlags, resolver: ProSurfaceResolver? = nil) {
        self.userId = userId
        self.roleFlags = roleFlags
        self.resolver = resolver ?? ProSurfaceResolver()
    }

    // MARK: Lifecycle

    func start() async {
        guard !isResolving else { return }
        isResolving = true
        defer { isResolving = false }

        if let result = await resolver.resolve(userId: userId, roleFlags: roleFlags) {
            activeRole = result.role
            insight = result.insight
        } else {
            activeRole = nil
            insight = nil
        }
    }

    func stop() {
        // No persistent listener — no-op.
    }
}
