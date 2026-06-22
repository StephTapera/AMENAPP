import Foundation
import Combine

// Phase-3: Canonical Threads-style feed scope.
//
// Selecting a row in the Unified Feeds switcher either:
//   1. updates the system feed mode (For You / Following / Quiet), OR
//   2. routes to a community/hub/topic detail view (the existing "Open
//      Community" path — unchanged), OR
//   3. sets an `ActiveFeedScope` so the home timeline shows a scoped
//      slice of the global feed (the "View in Feed" path).
//
// The scope itself is a typed enum so unsafe stringly-typed routing cannot
// silently widen access. The home-timeline query MUST consult this scope
// before issuing Firestore reads, applying:
//   - membership/entitlement enforcement for private/paid scopes
//   - moderation exclusion (removed/flagged/deleted)
//   - blocked-author exclusion
//   - pagination cursor scoped to the same scope key
//
// Until that query layer lands, the "View in Feed" UI affordance is gated
// behind `AMENFeatureFlags.viewInFeedEnabled` (default false). With the
// flag off, the switcher only routes via Open Community — never via View
// in Feed — so no scoped read happens.

public enum ActiveFeedScope: Equatable, Hashable {
    case forYou
    case following
    case quiet
    case covenant(id: String)
    case hub(id: String)
    case topic(slug: String)

    /// Stable scope key for caching, pagination cursors, and analytics
    /// (paired with `CommunitiesAnalytics` to keep payloads safe — the
    /// identifier component is NOT logged raw, only the scope type).
    public var scopeKey: String {
        switch self {
        case .forYou:            return "for_you"
        case .following:         return "following"
        case .quiet:             return "quiet"
        case .covenant(let id):  return "covenant:\(id)"
        case .hub(let id):       return "hub:\(id)"
        case .topic(let slug):   return "topic:\(slug)"
        }
    }

    /// Scope category for analytics (no raw id leakage).
    public var scopeType: String {
        switch self {
        case .forYou:    return "for_you"
        case .following: return "following"
        case .quiet:     return "quiet"
        case .covenant:  return "covenant"
        case .hub:       return "hub"
        case .topic:     return "topic"
        }
    }

    /// True when this scope reads from the global system feed (For You /
    /// Following / Quiet). Scoped reads (covenant/hub/topic) require
    /// additional membership/visibility validation server-side.
    public var isSystemFeed: Bool {
        switch self {
        case .forYou, .following, .quiet: return true
        case .covenant, .hub, .topic:     return false
        }
    }
}

@MainActor
public final class ActiveFeedScopeStore: ObservableObject {
    public static let shared = ActiveFeedScopeStore()

    /// Current scope. `forYou` is the default (matches existing global
    /// timeline behavior). Setting a community/hub/topic scope is the
    /// "View in Feed" entry point.
    @Published public private(set) var scope: ActiveFeedScope = .forYou

    private init() {}

    /// Sets the scope to a community/hub/topic. Called only when the
    /// `viewInFeedEnabled` feature flag is ON.
    public func enter(scope: ActiveFeedScope) {
        self.scope = scope
    }

    /// Resets scope back to the default system feed.
    public func reset() {
        self.scope = .forYou
    }
}
