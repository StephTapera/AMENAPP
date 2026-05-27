import Foundation

// MARK: - ProSurfaceResolver

@MainActor
final class ProSurfaceResolver {

    // MARK: Resolve

    /// Returns the highest-priority active role and its current insight,
    /// or nil if the user holds no elevated role or the surface returns no insight.
    func resolve(userId: String, roleFlags: ProfileRoleFlags) async -> (role: ProRole, insight: ProInsight)? {
        // Collect all active (role, priority) pairs
        var candidates: [(surface: any ProRoleSurface, priority: Int)] = []

        if roleFlags.isMentor {
            let s = MentorSurface()
            candidates.append((s, s.priority))
        }
        if roleFlags.isCreator {
            let s = CreatorSurface()
            candidates.append((s, s.priority))
        }
        if roleFlags.isMinistryLeader {
            let s = MinistrySurface()
            candidates.append((s, s.priority))
        }
        if roleFlags.isChurchAccount {
            let s = ChurchSurface(roleFlags: roleFlags)
            candidates.append((s, s.priority))
        }

        guard !candidates.isEmpty else { return nil }

        // Pick the surface with the lowest priority number (highest precedence)
        let sorted = candidates.sorted { $0.priority < $1.priority }

        for candidate in sorted {
            if let insight = await candidate.surface.currentInsight(for: userId) {
                return (role: candidate.surface.role, insight: insight)
            }
        }

        return nil
    }
}
