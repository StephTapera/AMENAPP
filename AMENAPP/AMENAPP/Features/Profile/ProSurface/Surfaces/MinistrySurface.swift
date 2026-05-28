import Foundation

// MARK: - MinistrySurface

struct MinistrySurface: ProRoleSurface {
    let role: ProRole = .ministryLeader
    let priority: Int = 30

    func currentInsight(for userId: String) async -> ProInsight? {
        // TODO: Wire real analytics once the Berean conversation analytics collection is defined.
        return ProInsight(
            line: "Ministry engagement this week",
            deepLinkPath: "amen://ministry-hub"
        )
    }
}
