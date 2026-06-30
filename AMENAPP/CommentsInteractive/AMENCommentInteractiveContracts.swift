import Foundation

// MARK: - Moderation decision (fail-closed authoritative value)

/// The authoritative moderation outcome for an interactive-comment action.
/// Server-backed in production; any client-constructed value is advisory only.
/// Fail-closed: the default decision BLOCKS. Reuses the existing `ModerationCategory`
/// taxonomy (SmartCommentsContracts) — no duplicate type is introduced.
struct AMENModerationDecision: Sendable, Equatable {
    enum Outcome: String, Sendable, Equatable {
        case allow            // explicitly cleared
        case warn             // allowed, surface a safety warning
        case rewriteRequired  // must be rewritten before publish
        case block            // not publishable
        case review           // pending human review; not publishable
    }

    let outcome: Outcome
    let categories: [ModerationCategory]
    /// True only when a server gate produced this decision. Client-only => false.
    let serverEnforced: Bool
    let reason: String?

    init(outcome: Outcome,
         categories: [ModerationCategory] = [],
         serverEnforced: Bool = false,
         reason: String? = nil) {
        self.outcome = outcome
        self.categories = categories
        self.serverEnforced = serverEnforced
        self.reason = reason
    }

    /// Fail-closed default: blocks until a real decision is supplied.
    static let failClosed = AMENModerationDecision(
        outcome: .block, categories: [], serverEnforced: false, reason: "fail-closed default"
    )

    /// Only `.allow`/`.warn` permit publishing.
    var permitsPublish: Bool {
        switch outcome {
        case .allow, .warn: return true
        case .rewriteRequired, .block, .review: return false
        }
    }
}

// MARK: - Moderation gate facade (the ONE authoritative block)

/// Wraps an async, server-backed resolver. If no resolver is configured (or the
/// lane is OFF), the gate returns `.failClosed` — it blocks. This is the single
/// authoritative entry point the interactive-comments lane consults before publish.
struct AMENModerationGate: Sendable {
    typealias Resolver = @Sendable (_ text: String) async -> AMENModerationDecision

    private let resolver: Resolver?

    init(resolver: Resolver? = nil) {
        self.resolver = resolver
    }

    func evaluate(text: String) async -> AMENModerationDecision {
        guard AMENSafeInteractiveCommentsFlags.masterEnabled, let resolver else {
            return .failClosed
        }
        return await resolver(text)
    }
}

// MARK: - Registration contracts (anti-collision backbone)

/// A compose mode (plain, reply, edit, quote, attach…) registered by Group A.
protocol AMENCommentComposeMode: Sendable {
    var id: String { get }
    var displayName: String { get }
    var isEnabled: Bool { get }
}

/// A media attachment provider registered by Group B. Media is gated BEFORE
/// upload/render; providers must fail closed on scanner/provider failure.
protocol AMENCommentMediaProvider: Sendable {
    var id: String { get }
    var isEnabled: Bool { get }
    /// Preflight a candidate attachment. Default-deny on any failure.
    func preflight(itemDescriptor: String) async -> AMENModerationDecision
}

/// An interaction (reply, react, report, block, delete…) registered by Group C.
/// `isAlwaysAvailable` enforces that safety actions (report/block) can never be
/// hidden behind an overflow gate.
protocol AMENCommentInteraction: Sendable {
    var id: String { get }
    var isDestructive: Bool { get }
    var requiresConfirmation: Bool { get }
    var isAlwaysAvailable: Bool { get }
}

/// A thread-level observer (expansion, pile-on, escalation…) for Group D.
protocol AMENThreadDynamicsObserver: AnyObject {
    var id: String { get }
    func threadDidUpdate(replyCount: Int, isEscalating: Bool)
}

// MARK: - Registry (single serialized owner; fail-closed)

/// The single registry for the interactive-comments lane. Gated by flags; while
/// the master flag is OFF, registration is inert and all collections stay empty.
@MainActor
final class AMENCommentInteractiveRegistry {
    static let shared = AMENCommentInteractiveRegistry()

    private(set) var composeModes: [AMENCommentComposeMode] = []
    private(set) var mediaProviders: [AMENCommentMediaProvider] = []
    private(set) var interactions: [AMENCommentInteraction] = []
    private(set) var threadObservers: [AMENThreadDynamicsObserver] = []

    private init() {}

    func register(composeMode: AMENCommentComposeMode) {
        guard AMENSafeInteractiveCommentsFlags.composeModesEnabled else { return }
        composeModes.append(composeMode)
    }
    func register(mediaProvider: AMENCommentMediaProvider) {
        guard AMENSafeInteractiveCommentsFlags.mediaProvidersEnabled else { return }
        mediaProviders.append(mediaProvider)
    }
    func register(interaction: AMENCommentInteraction) {
        guard AMENSafeInteractiveCommentsFlags.interactionsEnabled else { return }
        interactions.append(interaction)
    }
    func register(threadObserver: AMENThreadDynamicsObserver) {
        guard AMENSafeInteractiveCommentsFlags.threadDynamicsEnabled else { return }
        threadObservers.append(threadObserver)
    }

    /// Kill-switch / test reset.
    func reset() {
        composeModes.removeAll()
        mediaProviders.removeAll()
        interactions.removeAll()
        threadObservers.removeAll()
    }
}

// MARK: - Activation entry point (wired into the comment surface)

enum AMENSafeInteractiveComments {
    /// Called from the comment surface `onAppear`. No-op while the lane is OFF, so
    /// the OFF state is a guaranteed zero behavioral diff. Feature groups register
    /// their modes/providers/interactions in later waves; activation is intentionally
    /// inert until a group opts in behind its own gate.
    @MainActor
    static func activateIfEnabled() {
        guard AMENSafeInteractiveCommentsFlags.masterEnabled else { return }
        _ = AMENCommentInteractiveRegistry.shared
    }
}
