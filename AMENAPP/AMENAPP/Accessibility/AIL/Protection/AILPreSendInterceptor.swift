// AILPreSendInterceptor.swift
// AMENAPP — Accessibility Intelligence Layer (AIL)
//
// Pre-send interception seam for C10 (Reply-with-Care) and C11 (Cooldown Assist).
//
// IRON RULES encoded here (do not relax):
//  • PROPOSAL-ONLY. This NEVER blocks a send and NEVER edits the user's message.
//    The user's original text is always sendable. A chosen rewrite is applied only
//    because the USER picked it.
//  • Protection suggests; moderation decides. This shares NO code path with NeMo
//    moderation (which fails closed). This is a gentle nudge only.
//  • At most ONE gentle interception per message draft. After one prompt, re-sending
//    the same draft proceeds silently — never nag.
//  • Crisis context ALWAYS routes to care (a gentle pause), NEVER to cooldown.
//  • Fails OPEN: disabled, empty, already-seen, or any unavailable transform → proceed.
//  • OFF by default. Gated by a local preference, not the contested feature-flag hotspot.

import Foundation

@MainActor
final class AILPreSendInterceptor {

    static let shared = AILPreSendInterceptor()

    /// Local enable preference. OFF by default. Kept off the contended
    /// `AMENFeatureFlags` hotspot; a future Remote Config flag can drive this key.
    static let enabledDefaultsKey = "amen.ail.preSendCheckEnabled"

    /// When false (the default), `evaluate` always returns `.proceed` — zero interference.
    var isEnabled: Bool

    /// Drafts already intercepted once (keyed by message + content) — never twice.
    private var intercepted: Set<String> = []

    init(isEnabled: Bool = UserDefaults.standard.bool(forKey: AILPreSendInterceptor.enabledDefaultsKey)) {
        self.isEnabled = isEnabled
    }

    /// The outcome of a pre-send check. `.proceed` means send the original as-is.
    enum Decision: Equatable {
        case proceed
        case care(suggestion: String)     // gentle pause prompt (crisis or care path)
        case cooldown(rewrite: String)    // calmer rewrite offered (non-crisis only)
    }

    /// Injectable transform runner so the decision logic is testable without the network.
    typealias TransformRunner = (
        _ task: A11yTask,
        _ input: String,
        _ originalRef: String,
        _ isDirectMessage: Bool,
        _ crisisContext: Bool
    ) async -> A11yTransformResult

    /// The production runner — routes through the single AIL transform seam (fails open).
    static let liveRunner: TransformRunner = { task, input, ref, dm, crisis in
        await AILTransformService.shared.transform(
            task: task, input: input, originalRef: ref,
            isDirectMessage: dm, crisisContext: crisis
        )
    }

    /// Decide whether to gently intercept a send. Always resolves; never throws.
    /// - Returns `.proceed` whenever disabled, empty, already-prompted-once, or the
    ///   transform is unavailable (fail-open). Otherwise `.care`/`.cooldown`.
    func evaluate(
        draft: String,
        isCrisisContext: Bool,
        isDirectMessage: Bool = false,
        messageKey: String,
        using runner: TransformRunner = AILPreSendInterceptor.liveRunner
    ) async -> Decision {

        guard isEnabled else { return .proceed }

        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .proceed }

        let key = interceptKey(draft: trimmed, messageKey: messageKey)
        guard !intercepted.contains(key) else { return .proceed }   // once per message draft

        // Crisis ALWAYS routes to care (reply_care_check), never cooldown.
        let task: A11yTask = isCrisisContext ? .replyCareCheck : .cooldownRewrite
        let result = await runner(task, trimmed, messageKey, isDirectMessage, isCrisisContext)

        // Fail open: no usable suggestion → proceed silently.
        guard !result.failOpen,
              let text = result.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return .proceed
        }

        intercepted.insert(key)   // mark — dismiss or proceed won't prompt again
        return isCrisisContext ? .care(suggestion: text) : .cooldown(rewrite: text)
    }

    /// Forget a message's prompt history (e.g. after a successful send or a cleared
    /// composer) so a genuinely new message can be evaluated fresh.
    func forget(messageKey: String) {
        intercepted = intercepted.filter { !$0.hasPrefix(messageKey + "|") }
    }

    private func interceptKey(draft: String, messageKey: String) -> String {
        "\(messageKey)|\(draft.hashValue)"
    }

    #if DEBUG
    /// Test seam — clears once-per-message memory.
    func _resetForTesting() { intercepted.removeAll() }
    #endif
}
