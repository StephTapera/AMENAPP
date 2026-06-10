// AILPreSendGate.swift
// AMENAPP — Accessibility Intelligence Layer (AIL)
//
// The SwiftUI seam that places C10/C11 in a composer's send path. A composer holds
// an AILPreSendGate, applies `.ailPreSendGate(gate)`, and routes its send through
// `gate.submit(draft:) { finalText in <actually send finalText> }`.
//
// PROPOSAL-ONLY: when enabled and the interceptor returns a suggestion, the gate
// presents a dismissible sheet. The user can always send the original; a rewrite is
// sent only if the USER taps "Use this". When disabled (the default), `submit`
// forwards straight to the send closure — zero interference.

import SwiftUI

@MainActor
@Observable
final class AILPreSendGate {

    /// Drives sheet presentation. `nil` ⇒ no prompt.
    enum Prompt: Identifiable, Equatable {
        case care(suggestion: String)
        case cooldown(rewrite: String)
        var id: String {
            switch self {
            case .care(let s):     return "care:\(s)"
            case .cooldown(let r): return "cooldown:\(r)"
            }
        }
    }

    let messageKey: String
    let isCrisisContext: Bool
    let isDirectMessage: Bool

    var prompt: Prompt?
    fileprivate var pendingDraft: String = ""
    fileprivate var proceed: ((String) -> Void)?

    init(messageKey: String, isCrisisContext: Bool = false, isDirectMessage: Bool = false) {
        self.messageKey = messageKey
        self.isCrisisContext = isCrisisContext
        self.isDirectMessage = isDirectMessage
    }

    /// Route a send through the gate. `send` performs the actual delivery with the
    /// final text. Never blocks: on `.proceed` it forwards immediately.
    func submit(draft: String, send: @escaping (String) -> Void) {
        pendingDraft = draft
        proceed = send
        let interceptor = AILPreSendInterceptor.shared
        Task { @MainActor in
            let decision = await interceptor.evaluate(
                draft: draft,
                isCrisisContext: isCrisisContext,
                isDirectMessage: isDirectMessage,
                messageKey: messageKey
            )
            switch decision {
            case .proceed:          send(draft)
            case .care(let s):      prompt = .care(suggestion: s)
            case .cooldown(let r):  prompt = .cooldown(rewrite: r)
            }
        }
    }

    // MARK: - Sheet outcomes (proposal-only — user choices)

    fileprivate func sendOriginal() {            // "Send anyway" / "Keep mine"
        let send = proceed; let draft = pendingDraft
        clear()
        send?(draft)
    }

    fileprivate func sendRewrite(_ text: String) {  // "Use this" — user adopted the rewrite
        let send = proceed
        clear()
        send?(text)
    }

    fileprivate func dismissOnly() {             // "Edit" — nothing sent; composer retains text
        clear()
    }

    private func clear() {
        prompt = nil
        proceed = nil
    }
}

// MARK: - Modifier

struct AILPreSendGateModifier: ViewModifier {
    @Bindable var gate: AILPreSendGate

    func body(content: Content) -> some View {
        content.sheet(item: $gate.prompt) { prompt in
            switch prompt {
            case .care(let suggestion):
                AILReplyWithCareSheet(
                    draft: gate.pendingDraft,
                    suggestion: suggestion,
                    onSend: { gate.sendOriginal() },
                    onEdit: { gate.dismissOnly() }
                )
            case .cooldown(let rewrite):
                AILCooldownAssistSheet(
                    original: gate.pendingDraft,
                    rewrite: rewrite,
                    onUseRewrite: { gate.sendRewrite($0) },
                    onKeepMine: { gate.sendOriginal() }
                )
            }
        }
    }
}

extension View {
    /// Place the AIL pre-send check (C10/C11) on a composer. Proposal-only; no-op
    /// unless `AILPreSendInterceptor.shared.isEnabled`.
    func ailPreSendGate(_ gate: AILPreSendGate) -> some View {
        modifier(AILPreSendGateModifier(gate: gate))
    }
}
