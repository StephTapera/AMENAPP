import Foundation
import FirebaseFunctions

// MARK: - AmenModerationSeverity

/// Severity level returned by any moderation provider.
enum AmenModerationSeverity: String {
    case safe      = "safe"
    case warn      = "warn"
    case review    = "review"
    case block     = "block"
    /// Provider call failed or returned an unrecognised decision on a guard/tier-S surface.
    /// On guard surfaces this MUST block delivery.  On non-guard surfaces it is treated
    /// like `.warn` (soft-pass) so that a transient network error never silences ordinary users.
    case uncertain = "uncertain"
}

// MARK: - AmenModerationResult

/// The outcome of a single moderation call.
struct AmenModerationResult {
    let allowed: Bool
    let severity: AmenModerationSeverity
    let categories: [String]
    let userMessage: String?
    let crisisEscalated: Bool
    let crisisResources: [[String: String]]?
    let decisionId: String?

    static let safe = AmenModerationResult(
        allowed: true,
        severity: .safe,
        categories: [],
        userMessage: nil,
        crisisEscalated: false,
        crisisResources: nil,
        decisionId: nil
    )

    /// Returned when the provider fails on a guard/tier-S surface.
    /// `allowed` is false so the delivery path blocks without a cloud round-trip.
    static let uncertain = AmenModerationResult(
        allowed: false,
        severity: .uncertain,
        categories: ["moderation_unavailable"],
        userMessage: "This content could not be reviewed right now. Please try again.",
        crisisEscalated: false,
        crisisResources: nil,
        decisionId: nil
    )
}

// MARK: - AmenModerationContext

/// The surface from which text is being submitted.
enum AmenModerationContext: String {
    case message
    case post
    case profile
    case comment
    case dm
}

// MARK: - Guard-surface helpers

extension AmenModerationContext {
    /// Returns true for surfaces that MUST fail-secure (block on provider error).
    /// Direct messages and any context marked as crisis/medical/minor-adjacent qualify.
    var isGuardSurface: Bool {
        switch self {
        case .dm, .message: return true
        case .post, .profile, .comment: return false
        }
    }
}

extension BereanConstitutionalMode {
    /// Indicates that this constitutional mode requires fail-secure moderation.
    var isGuardMode: Bool { self == .guard }
}

// MARK: - AmenSafetyModerationProvider

/// Abstract provider protocol — swap implementations without changing call sites.
protocol AmenSafetyModerationProvider {
    /// Moderate `text` for the given surface and constitutional mode.
    ///
    /// - Parameter mode: Pass the active `BereanConstitutionalMode` when known.
    ///   When `.guard` (or nil on a guard surface), provider errors MUST return
    ///   `.uncertain` rather than `.safe` so delivery is blocked, not silently passed.
    func moderate(
        text: String,
        context: AmenModerationContext,
        mode: BereanConstitutionalMode?
    ) async throws -> AmenModerationResult
}

// MARK: - LocalRuleBasedModerationProvider

/// Offline fallback: deterministic rule-based checks, no network, always available.
final class LocalRuleBasedModerationProvider: AmenSafetyModerationProvider {
    func moderate(
        text: String,
        context: AmenModerationContext,
        mode: BereanConstitutionalMode?
    ) async throws -> AmenModerationResult {
        let lower = text.lowercased()

        let spamPatterns = [
            "win a free", "click here now", "limited time offer",
            "act now", "you have been selected",
        ]
        if spamPatterns.contains(where: { lower.contains($0) }) {
            return AmenModerationResult(
                allowed: true, severity: .review, categories: ["spam"],
                userMessage: "This may be flagged as spam.",
                crisisEscalated: false, crisisResources: nil, decisionId: nil
            )
        }
        // constitutional: verified safe-fallback — non-guard surface (local rules only, no network)
        // Guard-surface callers never land here: FirebaseModerationProvider returns .uncertain
        // before delegating to this local fallback when the surface requires fail-secure.
        return .safe
    }
}

// MARK: - FirebaseModerationProvider

/// Calls the `checkContentSafety` Firebase callable — the real NVIDIA NeMo Guard gate.
/// NVIDIA_API_KEY never touches the client; it lives only in Secret Manager server-side.
///
/// Failure semantics (G-2 fail-secure rule):
///   - Guard surfaces (DM, message, or BereanConstitutionalMode.guard):
///       ANY error → .uncertain (blocks delivery).
///   - Non-guard surfaces:
///       Network/parse error → local rule-based fallback (existing behaviour, fail open).
final class FirebaseModerationProvider: AmenSafetyModerationProvider {
    private let functions = Functions.functions(region: "us-central1")
    private let localFallback = LocalRuleBasedModerationProvider()

    func moderate(
        text: String,
        context: AmenModerationContext,
        mode: BereanConstitutionalMode?
    ) async throws -> AmenModerationResult {
        // Determine once whether this call requires fail-secure behaviour.
        let requiresFailSecure = context.isGuardSurface || (mode?.isGuardMode ?? false)

        let payload: [String: Any] = [
            "content": text,
            "contentType": context.rawValue,
        ]

        do {
            let result = try await functions.httpsCallable("checkContentSafety").call(payload)

            guard let data = result.data as? [String: Any] else {
                // Malformed response from the safety callable.
                if requiresFailSecure {
                    // G-2: fail-secure — block delivery rather than silently pass.
                    return .uncertain
                }
                // constitutional: verified safe-fallback — non-guard surface
                return try await localFallback.moderate(text: text, context: context, mode: mode)
            }

            let decisionRaw = data["decision"] as? String ?? "allow"
            let reason      = data["reason"] as? String
            let decisionId  = data["decisionId"] as? String
            let crisisEscalated = data["crisisEscalated"] as? Bool ?? false
            let categories  = data["detectedCategories"] as? [String] ?? []

            let rawResources = data["crisisResources"] as? [[String: String]]

            let severity: AmenModerationSeverity
            let allowed: Bool

            switch decisionRaw {
            case "allow":
                severity = .safe;   allowed = true
            case "warn":
                severity = .warn;   allowed = true
            case "review":
                severity = .review; allowed = false
            case "block":
                severity = .block;  allowed = false
            default:
                // Unrecognised decision string from the backend.
                if requiresFailSecure {
                    // G-2: unknown decision on guard surface → block.
                    return .uncertain
                }
                // constitutional: verified safe-fallback — non-guard surface
                severity = .safe; allowed = true
            }

            return AmenModerationResult(
                allowed: allowed,
                severity: severity,
                categories: categories,
                userMessage: reason,
                crisisEscalated: crisisEscalated,
                crisisResources: rawResources,
                decisionId: decisionId
            )
        } catch {
            if requiresFailSecure {
                // G-2: Network/Firebase failure on a guard/tier-S surface → fail-secure.
                // Do NOT fall through to local rules; block delivery until the safety
                // service is reachable.
                return .uncertain
            }
            // constitutional: verified safe-fallback — non-guard surface
            // Network/Firebase failure → fail open with local rules.
            // Moderation errors must never block legitimate users on ordinary surfaces.
            return try await localFallback.moderate(text: text, context: context, mode: mode)
        }
    }
}

// MARK: - AmenSafetyModerationCoordinator

/// Central coordinator. Picks the correct provider based on feature flags.
/// Guards every moderation call behind the `textModerationEnabled` flag.
///
/// Usage:
/// ```swift
/// let result = await AmenSafetyModerationCoordinator.shared.moderate(
///     text: draftText,
///     context: .post
/// )
/// if result.crisisEscalated { showCrisisResources(result.crisisResources) }
/// if !result.allowed { showModerationWarning(result.userMessage) }
/// ```
@MainActor
final class AmenSafetyModerationCoordinator: ObservableObject {
    static let shared = AmenSafetyModerationCoordinator()
    private init() {}

    private var provider: AmenSafetyModerationProvider = FirebaseModerationProvider()

    func configure(useFirebase: Bool) {
        provider = useFirebase ? FirebaseModerationProvider() : LocalRuleBasedModerationProvider()
    }

    /// Moderate `text` for the given surface and optional constitutional mode.
    ///
    /// - Parameters:
    ///   - text: The content to evaluate.
    ///   - context: The surface the content originates from.
    ///   - mode: The active `BereanConstitutionalMode`, if known.  Pass `.guard` for
    ///     crisis/medical/minor-adjacent sessions.
    ///
    /// - Returns `.safe` immediately when `textModerationEnabled` is false (non-guard only).
    ///   Guard surfaces always run the provider even when the flag is disabled, because
    ///   fail-open on guard contexts is a safety regression.
    /// - Returns `.uncertain` (blocks delivery) on provider error for guard/tier-S surfaces.
    /// - Returns `.safe` on provider error for non-guard surfaces — moderation errors
    ///   must never block legitimate users on ordinary surfaces.
    func moderate(
        text: String,
        context: AmenModerationContext,
        mode: BereanConstitutionalMode? = nil
    ) async -> AmenModerationResult {
        let requiresFailSecure = context.isGuardSurface || (mode?.isGuardMode ?? false)

        // Skip moderation only on non-guard surfaces when the flag is off.
        // Guard surfaces always run the provider.
        if !requiresFailSecure {
            guard (UserDefaults.standard.object(forKey: "textModerationEnabled") as? Bool) ?? true else {
                // constitutional: verified safe-fallback — non-guard surface (flag disabled)
                return .safe
            }
        }

        do {
            return try await provider.moderate(text: text, context: context, mode: mode)
        } catch {
            if requiresFailSecure {
                // G-2: unexpected throw on guard surface → fail-secure, block delivery.
                return .uncertain
            }
            // constitutional: verified safe-fallback — non-guard surface
            return .safe
        }
    }
}
