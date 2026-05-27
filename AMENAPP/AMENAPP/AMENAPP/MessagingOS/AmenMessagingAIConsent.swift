// AmenMessagingAIConsent.swift
// AMENAPP
//
// Per-chat AI consent control.
// Three states: On / Ask Every Time / Off
//
// Rules:
//   - Defaults to .askEveryTime for all new conversations
//   - State is stored per-conversation locally + synced to Firestore
//   - AI features NEVER activate for a chat when consent = .off
//   - AI features ALWAYS prompt when consent = .askEveryTime before any AI action
//   - No AI reads, compresses, or summarizes chat history without this check
//   - Gated by aiPerChatConsentEnabled feature flag

import SwiftUI

// MARK: - Consent Level (shared with AmenMessagingPrivacyPill)
// AIConsentLevel is defined in AmenMessagingPrivacyPill.swift as ChatPrivacyState.AIConsentLevel.
// This file provides the UI surfaces and permission check logic.

// MARK: - Per-Chat AI Permission Check

/// Call this before any AI operation on a conversation.
/// Returns true only when the user has granted permission for this operation.
@MainActor
final class AmenMessagingAIPermissionGuard {

    static func canProceed(
        conversationId: String,
        feature: AIMessagingFeature,
        flags: AMENFeatureFlags
    ) async -> AIPermissionDecision {
        guard flags.aiPerChatConsentEnabled else { return .denied(reason: "Feature not enabled") }
        guard flags.amenMessagingOSEnabled else { return .denied(reason: "Messaging OS not enabled") }

        // Feature-specific flag check
        switch feature {
        case .summarize:
            guard flags.aiMessagingSummariesEnabled else { return .denied(reason: "Summaries not enabled") }
        case .translate:
            guard flags.messageTranslationEnabled else { return .denied(reason: "Translation not enabled") }
        case .extractActions:
            guard flags.messagingActionExtractionEnabled else { return .denied(reason: "Action extraction not enabled") }
        case .transcribeVoice:
            guard flags.voiceNoteTranscriptionEnabled else { return .denied(reason: "Voice transcription not enabled") }
        case .smartReply:
            guard flags.smartRepliesEnabled else { return .denied(reason: "Smart replies not enabled") }
        case .safeWording:
            // safeWording is sender-side, no consent needed — just flag check
            guard flags.safeWordingSuggestionsEnabled else { return .denied(reason: "Safe wording not enabled") }
            return .allowed
        case .riskDetection:
            guard flags.messagingRiskDetectionEnabled else { return .denied(reason: "Risk detection not enabled") }
            return .allowed  // pre-send, no consent needed
        }

        // Check per-chat consent
        let store = ChatPrivacyStateStore(conversationId: conversationId)
        switch store.state.aiConsent {
        case .on:           return .allowed
        case .off:          return .denied(reason: "AI is off for this conversation")
        case .askEveryTime: return .needsConsent
        }
    }

    enum AIPermissionDecision: Equatable {
        case allowed
        case needsConsent
        case denied(reason: String)

        var isAllowed: Bool { self == .allowed }
    }
}

enum AIMessagingFeature: String, CaseIterable {
    case summarize      = "summarize"
    case translate      = "translate"
    case extractActions = "extract_actions"
    case transcribeVoice = "transcribe_voice"
    case smartReply     = "smart_reply"
    case safeWording    = "safe_wording"
    case riskDetection  = "risk_detection"

    var displayName: String {
        switch self {
        case .summarize:      return "Summarize Conversation"
        case .translate:      return "Translate Messages"
        case .extractActions: return "Extract Action Items"
        case .transcribeVoice: return "Transcribe Voice Note"
        case .smartReply:     return "Smart Reply Suggestions"
        case .safeWording:    return "Suggest Calmer Wording"
        case .riskDetection:  return "Safety Check"
        }
    }

    var icon: String {
        switch self {
        case .summarize:      return "sparkles.rectangle.stack"
        case .translate:      return "globe"
        case .extractActions: return "checkmark.circle"
        case .transcribeVoice: return "waveform"
        case .smartReply:     return "bubble.left.and.bubble.right"
        case .safeWording:    return "heart.text.clipboard"
        case .riskDetection:  return "shield.fill"
        }
    }

    var describeWhatAIDoes: String {
        switch self {
        case .summarize:
            return "AI will read recent messages in this conversation to generate a summary. Only you can see the summary."
        case .translate:
            return "AI will read this message to translate it. The translation is only shown to you."
        case .extractActions:
            return "AI will scan recent messages for tasks, decisions, and follow-ups. Results are only visible to members."
        case .transcribeVoice:
            return "AI will transcribe this voice note. The transcript is shown alongside the audio."
        case .smartReply:
            return "AI will read recent messages to suggest replies. Suggestions are only shown to you."
        case .safeWording:
            return "AI will check your message before sending and suggest calmer alternatives if needed."
        case .riskDetection:
            return "AI will check your message for scam, harassment, or manipulation patterns before sending."
        }
    }
}

// MARK: - Consent Prompt Sheet

struct AIConsentPromptSheet: View {
    let conversationId: String
    let feature: AIMessagingFeature
    let onAllow: () -> Void
    let onAllowAlways: () -> Void
    let onDeny: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(.separator))
                .frame(width: 36, height: 4)
                .padding(.top, 12)
                .padding(.bottom, 20)
                .accessibilityHidden(true)

            VStack(spacing: 12) {
                Image(systemName: feature.icon)
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(.blue)
                    .accessibilityHidden(true)

                Text(feature.displayName)
                    .font(.system(size: 20, weight: .bold))
                    .multilineTextAlignment(.center)

                Text(feature.describeWhatAIDoes)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 28)

            VStack(spacing: 10) {
                Button(action: {
                    let store = ChatPrivacyStateStore(conversationId: conversationId)
                    store.update { $0.aiConsent = .on }
                    dismiss()
                    onAllowAlways()
                }) {
                    Text("Allow for This Conversation")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(Color.black))
                }
                .accessibilityLabel("Allow AI access for this entire conversation")

                Button(action: {
                    dismiss()
                    onAllow()
                }) {
                    Text("Allow Once")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            Capsule()
                                .stroke(Color(.separator), lineWidth: 1)
                        )
                }
                .accessibilityLabel("Allow AI access just this one time")

                Button(action: {
                    let store = ChatPrivacyStateStore(conversationId: conversationId)
                    store.update { $0.aiConsent = .off }
                    dismiss()
                    onDeny()
                }) {
                    Text("Don't Allow")
                        .font(.system(size: 14))
                        .foregroundStyle(.red)
                }
                .accessibilityLabel("Deny AI access and turn off AI for this conversation")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .background(Color(.systemBackground))
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
    }
}

// MARK: - AI Consent Badge

/// Small inline badge showing current AI consent state for a conversation.
/// Used in chat header alongside AmenMessagingPrivacyPill or standalone.
struct AIConsentBadge: View {
    let conversationId: String
    let onTap: () -> Void

    @StateObject private var store: ChatPrivacyStateStore

    init(conversationId: String, onTap: @escaping () -> Void) {
        self.conversationId = conversationId
        self.onTap = onTap
        _store = StateObject(wrappedValue: ChatPrivacyStateStore(conversationId: conversationId))
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Image(systemName: store.state.aiConsent.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .accessibilityHidden(true)
                Text(store.state.aiConsent.displayName)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(store.state.aiConsent.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(store.state.aiConsent.color.opacity(0.10))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("AI access: \(store.state.aiConsent.displayName). Tap to change.")
    }
}

// MARK: - AI Feature Action Button

/// A button that checks AI consent before performing an AI action.
/// Shows AIConsentPromptSheet if consent is .askEveryTime.
struct AmenAIFeatureButton<Label: View>: View {
    let conversationId: String
    let feature: AIMessagingFeature
    let flags: AMENFeatureFlags
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    @State private var showConsentSheet = false
    @State private var pendingAction = false

    var body: some View {
        Button {
            Task {
                let decision = await AmenMessagingAIPermissionGuard.canProceed(
                    conversationId: conversationId,
                    feature: feature,
                    flags: flags
                )
                switch decision {
                case .allowed:
                    action()
                case .needsConsent:
                    showConsentSheet = true
                case .denied:
                    break
                }
            }
        } label: {
            label()
        }
        .sheet(isPresented: $showConsentSheet) {
            AIConsentPromptSheet(
                conversationId: conversationId,
                feature: feature,
                onAllow: action,
                onAllowAlways: action,
                onDeny: {}
            )
        }
    }
}

// MARK: - AI Consent Settings Row

/// List row for use in PrivacyControlsSettingsView or chat settings.
struct AIConsentSettingsRow: View {
    let conversationId: String
    @StateObject private var store: ChatPrivacyStateStore

    init(conversationId: String) {
        self.conversationId = conversationId
        _store = StateObject(wrappedValue: ChatPrivacyStateStore(conversationId: conversationId))
    }

    var body: some View {
        Picker("AI Access", selection: Binding(
            get: { store.state.aiConsent },
            set: { newValue in store.update { $0.aiConsent = newValue } }
        )) {
            ForEach(ChatPrivacyState.AIConsentLevel.allCases, id: \.self) { level in
                Label(level.displayName, systemImage: level.icon).tag(level)
            }
        }
        .accessibilityLabel("AI access for this conversation: \(store.state.aiConsent.displayName)")
    }
}
