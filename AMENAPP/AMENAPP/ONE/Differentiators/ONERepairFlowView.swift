// ONERepairFlowView.swift
// ONE — Structured opt-in reconciliation flow. Both parties must accept.
// P4-F | Calls one_activateRepairFlow + one_acceptRepairFlow CF stubs.
//
// Design rules:
//   • Exit is instant, always available, no guilt language.
//   • Block/sever is always available from user profile — independent of this flow.
//   • Tone check NEVER blocks send — always the user's choice.
//   • "Resolved" requires both parties to mark it. (P4-F: simulated for now.)

import SwiftUI

struct ONERepairFlowView: View {
    let otherUID: String
    let otherDisplayName: String
    var onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var phase: ONERepairPhase = .invited
    @State private var flowID: String? = nil
    @State private var messageText = ""
    @State private var toneWarning: String? = nil
    @State private var showTonePreview = false
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var messages: [(text: String, isOutgoing: Bool)] = [
        (text: "Hey — I've been thinking about what happened and I'd like to work through it together.", isOutgoing: true)
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                phaseStepperBar
                    .padding(.top, ONE.Spacing.sm)
                Divider().opacity(0.3)
                phaseContent
                exitStrip
            }
            .navigationTitle("Repair Flow")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { onDismiss(); dismiss() }
                }
            }
            .alert("Error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Phase stepper

    private var phaseStepperBar: some View {
        HStack(spacing: 0) {
            ForEach(Array(ONERepairPhase.stepCases.enumerated()), id: \.offset) { idx, step in
                HStack(spacing: 0) {
                    VStack(spacing: 4) {
                        Circle()
                            .fill(stepColor(step))
                            .frame(width: 10, height: 10)
                        Text(step.stepLabel)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(step == phase ? AmenTheme.Colors.amenGold : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                    if idx < ONERepairPhase.stepCases.count - 1 {
                        Rectangle()
                            .fill(Color.primary.opacity(0.15))
                            .frame(height: 1)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(.horizontal, ONE.Spacing.lg)
        .padding(.bottom, ONE.Spacing.sm)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Repair flow: \(phase.stepLabel) phase")
    }

    private func stepColor(_ step: ONERepairPhase) -> Color {
        let stepIdx = ONERepairPhase.stepCases.firstIndex(of: step) ?? 0
        let curIdx  = ONERepairPhase.stepCases.firstIndex(of: phase) ?? 0
        if step == phase       { return AmenTheme.Colors.amenGold }
        if stepIdx < curIdx    { return AmenTheme.Colors.amenGold.opacity(0.4) }
        return Color.primary.opacity(0.2)
    }

    // MARK: - Phase content

    @ViewBuilder
    private var phaseContent: some View {
        ScrollView {
            VStack(spacing: ONE.Spacing.lg) {
                switch phase {
                case .invited:    invitedPanel
                case .active:     activePanel
                case .toneCheck:  toneCheckPanel
                case .resolved:   resolvedPanel
                case .exited:     exitedPanel
                }
            }
            .padding(ONE.Spacing.lg)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Invited panel

    private var invitedPanel: some View {
        VStack(alignment: .leading, spacing: ONE.Spacing.lg) {
            infoRow(
                icon: "clock.fill",
                color: ONE.Colors.witnessGold,
                text: "Waiting for \(otherDisplayName) to accept. They'll see your name and this note."
            )
            Text("Request sent just now")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Simulate: Other Party Accepted") {
                withAnimation(ONE.Motion.adaptive(reduceMotion: reduceMotion)) {
                    phase = .active
                }
            }
            .font(.system(size: 13))
            .foregroundStyle(ONE.Colors.repairGreen)
            .accessibilityLabel("Simulate other party accepting the repair flow")
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Active panel

    private var activePanel: some View {
        VStack(spacing: ONE.Spacing.sm) {
            messageThread
            composerRow(
                placeholder: "Say something thoughtful…",
                onSend: {
                    let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return }
                    messages.append((text: text, isOutgoing: true))
                    messageText = ""
                },
                extraButton: AnyView(
                    Button("Enable Tone Check") {
                        withAnimation(ONE.Motion.adaptive(reduceMotion: reduceMotion)) {
                            phase = .toneCheck
                        }
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(AmenTheme.Colors.amenGold)
                    .accessibilityLabel("Enable AI tone checking for messages")
                )
            )
        }
    }

    // MARK: - Tone check panel

    private var toneCheckPanel: some View {
        VStack(spacing: ONE.Spacing.sm) {
            infoRow(
                icon: "waveform.badge.magnifyingglass",
                color: AmenTheme.Colors.amenGold,
                text: "Tone check is on. Each message is previewed before sending. Sending is always your choice."
            )
            messageThread
            composerRow(
                placeholder: "Type your message…",
                onSend: {
                    let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return }
                    toneWarning = text.lowercased().contains("you always") || text.lowercased().contains("never")
                        ? "This may read as absolute language. Consider softening."
                        : nil
                    showTonePreview = true
                },
                extraButton: nil
            )
            if showTonePreview { tonePreviewCard }
        }
    }

    private var tonePreviewCard: some View {
        VStack(alignment: .leading, spacing: ONE.Spacing.sm) {
            if let warning = toneWarning {
                HStack(spacing: ONE.Spacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(ONE.Colors.decayAmber)
                    Text(warning)
                        .font(.system(size: 13))
                        .foregroundStyle(.primary)
                }
            } else {
                HStack(spacing: ONE.Spacing.sm) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(ONE.Colors.repairGreen)
                    Text("Tone looks good.")
                        .font(.system(size: 13))
                        .foregroundStyle(.primary)
                }
            }
            Text("Sending is always your choice.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            HStack(spacing: ONE.Spacing.sm) {
                Button("Edit message") {
                    withAnimation(ONE.Motion.adaptive(reduceMotion: reduceMotion)) {
                        showTonePreview = false
                    }
                }
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                Spacer()
                Button("Send anyway") {
                    let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty {
                        messages.append((text: text, isOutgoing: true))
                        messageText = ""
                    }
                    showTonePreview = false
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AmenTheme.Colors.amenGold)
            }
        }
        .padding(ONE.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: ONE.Radius.card, style: .continuous)
                .fill(ONE.Colors.decayAmber.opacity(0.08))
        )
        .accessibilityElement(children: .contain)
        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .bottom)))
    }

    // MARK: - Resolved panel

    private var resolvedPanel: some View {
        VStack(spacing: ONE.Spacing.md) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(ONE.Colors.repairGreen)
            Text("Both parties resolved")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.primary)
            Text("This flow is archived. No further messages can be sent.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Close") { onDismiss(); dismiss() }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, ONE.Spacing.xl)
                .padding(.vertical, ONE.Spacing.sm)
                .background(Capsule().fill(ONE.Colors.repairGreen))
                .accessibilityLabel("Close repair flow")
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Exited panel

    private var exitedPanel: some View {
        VStack(spacing: ONE.Spacing.md) {
            Spacer()
            Image(systemName: "arrow.left.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("You left this flow")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)
            Text("That's okay. You can start a new request if you'd like to try again.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Start new request") {
                withAnimation(ONE.Motion.adaptive(reduceMotion: reduceMotion)) {
                    phase = .invited
                    messages = []
                }
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(AmenTheme.Colors.amenGold)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Exit strip (always visible)

    private var exitStrip: some View {
        VStack(spacing: 4) {
            Divider().opacity(0.3)
            HStack {
                if phase != .resolved && phase != .exited {
                    Button("Exit repair flow") {
                        withAnimation(ONE.Motion.adaptive(reduceMotion: reduceMotion)) {
                            phase = .exited
                        }
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(ONE.Colors.ephemeralRed.opacity(0.8))
                    .accessibilityLabel("Exit repair flow. You can leave at any time.")
                }
                Spacer()
                Text("Block or sever is always available from your profile.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            .padding(.horizontal, ONE.Spacing.md)
            .padding(.vertical, ONE.Spacing.sm)
        }
    }

    // MARK: - Shared subviews

    private var messageThread: some View {
        VStack(spacing: ONE.Spacing.xs) {
            ForEach(messages.indices, id: \.self) { idx in
                let msg = messages[idx]
                HStack {
                    if msg.isOutgoing { Spacer() }
                    Text(msg.text)
                        .font(.system(size: 14))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, ONE.Spacing.md)
                        .padding(.vertical, ONE.Spacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(msg.isOutgoing
                                      ? ONE.Colors.privateIndigo.opacity(0.18)
                                      : Color.primary.opacity(0.06))
                        )
                        .frame(maxWidth: 280, alignment: msg.isOutgoing ? .trailing : .leading)
                    if !msg.isOutgoing { Spacer() }
                }
                .accessibilityLabel("\(msg.isOutgoing ? "You" : otherDisplayName): \(msg.text)")
            }
        }
    }

    private func composerRow(
        placeholder: String,
        onSend: @escaping () -> Void,
        extraButton: AnyView?
    ) -> some View {
        VStack(spacing: ONE.Spacing.xs) {
            if let extra = extraButton { extra }
            HStack(spacing: ONE.Spacing.sm) {
                TextField(placeholder, text: $messageText)
                    .font(.system(size: 14))
                    .padding(.horizontal, ONE.Spacing.md)
                    .padding(.vertical, ONE.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    )
                    .accessibilityLabel(placeholder)
                Button {
                    onSend()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                         ? Color.secondary.opacity(0.4)
                                         : AmenTheme.Colors.amenGold)
                }
                .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Send message")
            }
        }
    }

    private func infoRow(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: ONE.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(color)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(ONE.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: ONE.Radius.card, style: .continuous)
                .fill(color.opacity(0.06))
        )
        .accessibilityElement(children: .combine)
    }
}

// MARK: - ONERepairPhase step helpers

extension ONERepairPhase: Equatable {}

extension ONERepairPhase {
    static var stepCases: [ONERepairPhase] { [.invited, .active, .toneCheck, .resolved] }

    var stepLabel: String {
        switch self {
        case .invited:   return "Invite"
        case .active:    return "Active"
        case .toneCheck: return "Tone"
        case .resolved:  return "Resolved"
        case .exited:    return "Exited"
        }
    }
}
