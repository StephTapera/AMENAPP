import Foundation

@MainActor
enum BereanPostContextAvailability {
    case available(BereanPostContext)
    case unavailable(message: String)
}

@MainActor
final class BereanPostContextAvailabilityService {
    static let shared = BereanPostContextAvailabilityService()

    private init() {}

    func validate(_ postContext: BereanPostContext) async -> BereanPostContextAvailability {
        do {
            guard let post = try await FirebasePostService.shared.fetchPostById(postId: postContext.postId) else {
                return .unavailable(message: "This post is no longer available. Berean will continue without post context.")
            }

            return .available(postContext.refreshed(from: post))
        } catch {
            return .unavailable(message: "This post is no longer available. Berean will continue without post context.")
        }
    }
}
