import Foundation

// MARK: - TrustCenterSendSafelyAction

enum TrustCenterSendSafelyAction: String, CaseIterable, Identifiable, Sendable {
    case rewrite
    case soften
    case clarify
    case keep

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .rewrite: return "Rewrite"
        case .soften: return "Soften"
        case .clarify: return "Clarify"
        case .keep: return "Keep"
        }
    }
}

// MARK: - TrustCenterSendSafelyRequest

struct TrustCenterSendSafelyRequest: Sendable {
    let draftText: String
    let verdict: TrustCenterVerdict
    let moderationReason: String?
    let moderationCategories: [String]
    let postContext: String?

    init(
        draftText: String,
        verdict: TrustCenterVerdict,
        moderationReason: String? = nil,
        moderationCategories: [String] = [],
        postContext: String? = nil
    ) {
        self.draftText = draftText
        self.verdict = verdict
        self.moderationReason = moderationReason
        self.moderationCategories = moderationCategories
        self.postContext = postContext
    }
}

// MARK: - TrustCenterSendSafelyOption

struct TrustCenterSendSafelyOption: Identifiable, Equatable, Sendable {
    let id: TrustCenterSendSafelyAction
    let action: TrustCenterSendSafelyAction
    let replacementText: String?
    let explanation: String

    init(
        action: TrustCenterSendSafelyAction,
        replacementText: String? = nil,
        explanation: String
    ) {
        self.id = action
        self.action = action
        self.replacementText = replacementText
        self.explanation = explanation
    }
}

// MARK: - TrustCenterSendSafelyResult

struct TrustCenterSendSafelyResult: Equatable, Sendable {
    let isEnabled: Bool
    let verdict: TrustCenterVerdict
    let options: [TrustCenterSendSafelyOption]
    let provider: String?

    static func disabled(for request: TrustCenterSendSafelyRequest) -> TrustCenterSendSafelyResult {
        TrustCenterSendSafelyResult(
            isEnabled: false,
            verdict: request.verdict,
            options: [
                TrustCenterSendSafelyOption(
                    action: .keep,
                    replacementText: request.draftText,
                    explanation: "Send Safely is off. No rewrite was requested."
                ),
            ],
            provider: nil
        )
    }
}

// MARK: - TrustCenterSendSafelyRewriteProviding

protocol TrustCenterSendSafelyRewriteProviding: Sendable {
    func rewriteSuggestion(for request: TrustCenterSendSafelyRequest) async throws -> TrustCenterSendSafelyRewriteSuggestion?
}

struct TrustCenterSendSafelyRewriteSuggestion: Equatable, Sendable {
    let text: String
    let provider: String?
}

// MARK: - Existing Berean proxy adapter

struct TrustCenterSmartCommentRewriteAdapter: TrustCenterSendSafelyRewriteProviding {
    func rewriteSuggestion(for request: TrustCenterSendSafelyRequest) async throws -> TrustCenterSendSafelyRewriteSuggestion? {
        let result = try await SmartCommentService.shared.reviewComment(
            commentText: request.draftText,
            postContext: request.postContext
        )

        guard let suggestion = result.rewriteSuggestion?.trimmingCharacters(in: .whitespacesAndNewlines),
              !suggestion.isEmpty else {
            return nil
        }

        return TrustCenterSendSafelyRewriteSuggestion(
            text: suggestion,
            provider: result.provider
        )
    }
}

// MARK: - TrustCenterSendSafelyService

struct TrustCenterSendSafelyService: Sendable {
    private let featureGate: TrustCenterFeatureGate
    private let rewriteProvider: any TrustCenterSendSafelyRewriteProviding

    init(
        featureGate: TrustCenterFeatureGate = .disabled,
        rewriteProvider: any TrustCenterSendSafelyRewriteProviding = TrustCenterSmartCommentRewriteAdapter()
    ) {
        self.featureGate = featureGate
        self.rewriteProvider = rewriteProvider
    }

    func options(for request: TrustCenterSendSafelyRequest) async -> TrustCenterSendSafelyResult {
        guard featureGate.isEnabled(.sendSafely) else {
            return .disabled(for: request)
        }

        let rewriteSuggestion = try? await rewriteProvider.rewriteSuggestion(for: request)
        let options = makeOptions(for: request, rewriteSuggestion: rewriteSuggestion?.text)

        return TrustCenterSendSafelyResult(
            isEnabled: true,
            verdict: request.verdict,
            options: options,
            provider: rewriteSuggestion?.provider
        )
    }

    private func makeOptions(
        for request: TrustCenterSendSafelyRequest,
        rewriteSuggestion: String?
    ) -> [TrustCenterSendSafelyOption] {
        var options: [TrustCenterSendSafelyOption] = []

        if let rewriteSuggestion {
            options.append(
                TrustCenterSendSafelyOption(
                    action: .rewrite,
                    replacementText: rewriteSuggestion,
                    explanation: "Use the existing compose coach suggestion."
                )
            )
        }

        switch request.verdict.level {
        case .safe:
            options.append(
                TrustCenterSendSafelyOption(
                    action: .clarify,
                    replacementText: nil,
                    explanation: "Optionally make the message clearer before sending."
                )
            )
        case .caution:
            options.append(
                TrustCenterSendSafelyOption(
                    action: .soften,
                    replacementText: nil,
                    explanation: request.verdict.humanReadable
                )
            )
            options.append(
                TrustCenterSendSafelyOption(
                    action: .clarify,
                    replacementText: nil,
                    explanation: "Clarify intent without changing the moderation verdict."
                )
            )
        case .blocked:
            options.append(
                TrustCenterSendSafelyOption(
                    action: .soften,
                    replacementText: nil,
                    explanation: request.verdict.humanReadable
                )
            )
        }

        options.append(
            TrustCenterSendSafelyOption(
                action: .keep,
                replacementText: request.draftText,
                explanation: "Keep the original text. Send eligibility remains controlled by the existing verdict."
            )
        )

        return options
    }
}
