import Foundation

// MARK: - AmenModerationSeverity

/// Severity level returned by any moderation provider.
enum AmenModerationSeverity: String {
    case safe   = "safe"
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

    /// Convenience singleton for a clean, unmoderated pass.
    static let safe = AmenModerationResult(
        allowed: true,
        severity: .safe,
        categories: [],
        userMessage: nil
    )
}

// MARK: - AmenModerationContext

/// The surface from which text is being submitted.
enum AmenModerationContext: String {
    case message
    case post
    case profile
    case comment
}

// MARK: - AmenSafetyModerationProvider

/// Abstract provider protocol — swap implementations without changing call sites.
protocol AmenSafetyModerationProvider {
    func moderate(text: String, context: AmenModerationContext) async throws -> AmenModerationResult
}

// MARK: - LocalRuleBasedModerationProvider

/// V1 default: deterministic rule-based checks, no network, always available offline.
/// Conservative: default to safe unless a clear signal is present.
final class LocalRuleBasedModerationProvider: AmenSafetyModerationProvider {
    func moderate(text: String, context: AmenModerationContext) async throws -> AmenModerationResult {
        let lower = text.lowercased()

        let spamPatterns = [
            "win a free",
            "click here now",
            "limited time offer",
            "act now",
            "you have been selected",
        ]

        if spamPatterns.contains(where: { lower.contains($0) }) {
            return AmenModerationResult(
                allowed: true,
                severity: .review,
                categories: ["spam"],
                userMessage: "This may be flagged as spam."
            )
        }

        return .safe
    }
}

// MARK: - NvidiaModerationProvider

/// Future NVIDIA NeMo Guardrails integration.
/// V1 stub: falls back to LocalRuleBasedModerationProvider when API key is absent
/// or NVIDIA integration is not yet wired. No API key is ever hardcoded.
final class NvidiaModerationProvider: AmenSafetyModerationProvider {
    private let localFallback = LocalRuleBasedModerationProvider()

    /// Loaded from the process environment — never hardcoded in source.
    private let apiKey: String?

    init() {
        apiKey = ProcessInfo.processInfo.environment["NVIDIA_MODERATION_API_KEY"]
    }

    func moderate(text: String, context: AmenModerationContext) async throws -> AmenModerationResult {
        guard apiKey != nil else {
            // No API key configured — fall back to local rule-based provider.
            return try await localFallback.moderate(text: text, context: context)
        }
        // V1: API key present but NVIDIA API integration not yet wired.
        // When NVIDIA NeMo Guardrails is integrated, replace this with the actual
        // URLSession-based API call and decode its response into AmenModerationResult.
        return try await localFallback.moderate(text: text, context: context)
    }
}

// MARK: - AmenSafetyModerationCoordinator

/// Central coordinator. Picks the correct provider based on feature flags.
/// Guards every moderation call behind the `textModerationEnabled` UserDefaults flag.
///
/// Usage:
/// ```swift
/// let result = await AmenSafetyModerationCoordinator.shared.moderate(
///     text: draftText,
///     context: .post
/// )
/// if result.severity == .review { /* show soft warning */ }
/// ```
@MainActor
final class AmenSafetyModerationCoordinator: ObservableObject {
    static let shared = AmenSafetyModerationCoordinator()
    private init() {}

    private var provider: AmenSafetyModerationProvider = LocalRuleBasedModerationProvider()

    /// Call during app startup or when the relevant feature flag changes.
    func configure(useNvidia: Bool) {
        provider = useNvidia ? NvidiaModerationProvider() : LocalRuleBasedModerationProvider()
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
            // Fail open: a moderation provider failure is never surfaced to the user
            // as a blocking error. Log internally if a logging service is available.
            return .safe
        }
    }
}
