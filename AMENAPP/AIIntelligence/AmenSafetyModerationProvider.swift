import Foundation
import FirebaseFunctions

// MARK: - AmenModerationSeverity

/// Severity level returned by any moderation provider.
enum AmenModerationSeverity: String {
    case safe   = "safe"
    case warn   = "warn"
    case review = "review"
    case block  = "block"
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

// MARK: - AmenSafetyModerationProvider

/// Abstract provider protocol — swap implementations without changing call sites.
protocol AmenSafetyModerationProvider {
    func moderate(text: String, context: AmenModerationContext) async throws -> AmenModerationResult
}

// MARK: - LocalRuleBasedModerationProvider

/// Offline fallback: deterministic rule-based checks, no network, always available.
final class LocalRuleBasedModerationProvider: AmenSafetyModerationProvider {
    func moderate(text: String, context: AmenModerationContext) async throws -> AmenModerationResult {
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
        return .safe
    }
}

// MARK: - FirebaseModerationProvider

/// Calls the `checkContentSafety` Firebase callable — the real NVIDIA NeMo Guard gate.
/// NVIDIA_API_KEY never touches the client; it lives only in Secret Manager server-side.
/// Falls back to the local provider if the network call fails so users are never blocked
/// by an AI outage.
final class FirebaseModerationProvider: AmenSafetyModerationProvider {
    private let functions = Functions.functions(region: "us-central1")
    private let localFallback = LocalRuleBasedModerationProvider()

    func moderate(text: String, context: AmenModerationContext) async throws -> AmenModerationResult {
        let payload: [String: Any] = [
            "content": text,
            "contentType": context.rawValue,
        ]

        do {
            let result = try await functions.httpsCallable("checkContentSafety").call(payload)

            guard let data = result.data as? [String: Any] else {
                return try await localFallback.moderate(text: text, context: context)
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
                severity = .safe;  allowed = true
            case "warn":
                severity = .warn;  allowed = true
            case "review":
                severity = .review; allowed = false
            case "block":
                severity = .block;  allowed = false
            default:
                severity = .safe;   allowed = true
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
            // Network/Firebase failure → fail open with local rules.
            // Moderation errors must never block legitimate users.
            return try await localFallback.moderate(text: text, context: context)
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

    /// Moderate `text` for the given surface.
    ///
    /// - Returns `.safe` immediately when `textModerationEnabled` is false.
    /// - Returns `.safe` on any provider error — moderation errors must never block the user.
    func moderate(text: String, context: AmenModerationContext) async -> AmenModerationResult {
        guard (UserDefaults.standard.object(forKey: "textModerationEnabled") as? Bool) ?? true else {
            return .safe
        }
        do {
            return try await provider.moderate(text: text, context: context)
        } catch {
            return .safe
        }
    }
}
