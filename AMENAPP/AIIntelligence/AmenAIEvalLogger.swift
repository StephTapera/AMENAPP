import Foundation
import FirebaseAnalytics

struct AmenAIEvalEvent {
    let routeId: String
    let taskType: AmenAITaskType
    let surface: String
    let provider: AmenAIProvider
    let model: String
    let executionPath: AmenAIExecutionPath
    let riskTier: AmenAIRiskTier
    let latencyMs: Int?
    let tokenEstimate: Int?
    let costBudgetMicroUSD: Int
    let fallbackReason: String?
    let blockedReason: String?
    let qualityScore: Double?

    var safeParameters: [String: Any] {
        var params: [String: Any] = [
            "route_id": routeId,
            "task_type": taskType.rawValue,
            "surface": surface,
            "provider": provider.rawValue,
            "model": model,
            "execution_path": executionPath.rawValue,
            "risk_tier": riskTier.rawValue,
            "cost_budget_micro_usd": costBudgetMicroUSD
        ]
        if let latencyMs { params["latency_ms"] = latencyMs }
        if let tokenEstimate { params["token_estimate"] = tokenEstimate }
        if let fallbackReason { params["fallback_reason"] = sanitizeReason(fallbackReason) }
        if let blockedReason { params["blocked_reason"] = sanitizeReason(blockedReason) }
        if let qualityScore { params["quality_score"] = qualityScore }
        return params
    }

    private func sanitizeReason(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9_,-]"#, with: "_", options: .regularExpression)
            .prefix(80)
            .description
    }
}

@MainActor
final class AmenAIEvalLogger {
    static let shared = AmenAIEvalLogger()

    private init() {}

    func logRoute(_ decision: AmenAIRouteDecision, surface: String, routeId: String = UUID().uuidString) {
        guard AMENFeatureFlags.shared.analyticsEnabled else { return }
        let event = AmenAIEvalEvent(
            routeId: routeId,
            taskType: decision.taskType,
            surface: surface,
            provider: decision.provider,
            model: decision.model,
            executionPath: decision.executionPath,
            riskTier: decision.riskTier,
            latencyMs: nil,
            tokenEstimate: nil,
            costBudgetMicroUSD: decision.costBudgetMicroUSD,
            fallbackReason: nil,
            blockedReason: decision.blockedReason,
            qualityScore: nil
        )
        Analytics.logEvent("amen_ai_route_decision", parameters: event.safeParameters)
    }

    func logCompletion(
        decision: AmenAIRouteDecision,
        surface: String,
        routeId: String,
        latencyMs: Int,
        tokenEstimate: Int? = nil,
        fallbackReason: String? = nil,
        qualityScore: Double? = nil
    ) {
        guard AMENFeatureFlags.shared.analyticsEnabled else { return }
        let event = AmenAIEvalEvent(
            routeId: routeId,
            taskType: decision.taskType,
            surface: surface,
            provider: decision.provider,
            model: decision.model,
            executionPath: decision.executionPath,
            riskTier: decision.riskTier,
            latencyMs: latencyMs,
            tokenEstimate: tokenEstimate,
            costBudgetMicroUSD: decision.costBudgetMicroUSD,
            fallbackReason: fallbackReason,
            blockedReason: decision.blockedReason,
            qualityScore: qualityScore
        )
        Analytics.logEvent("amen_ai_route_completed", parameters: event.safeParameters)
    }
}
