// ONEMessageComposerView.swift
// ONE — Composer bar: inherited thread contract + per-message permission overrides.
// Chrome surface: uses regularMaterial backdrop (Liquid Glass upgrade path at P1-I).

import SwiftUI

struct ONEMessageComposerView: View {
    let threadID: String
    let threadContract: ONEPrivacyContract
    let onSend: (String, ONEMomentPermissions) async throws -> Void

    @State private var text = ""
    @State private var overridesOpen = false
    @State private var overrides: ONEMomentPermissions
    @State private var isSending = false
    @State private var sendError: String?
    // AIL C10/C11 — DM path: isDirectMessage: true per iron rule.
    // Proposal-only; no-op unless AILPreSendInterceptor.shared.isEnabled (default OFF).
    @State private var dmSendGate = AILPreSendGate(
        messageKey: "one-dm-composer",
        isCrisisContext: false,
        isDirectMessage: true
    )
    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(threadID: String,
         threadContract: ONEPrivacyContract,
         onSend: @escaping (String, ONEMomentPermissions) async throws -> Void) {
        self.threadID = threadID
        self.threadContract = threadContract
        self.onSend = onSend
        _overrides = State(initialValue: threadContract.permissions)
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    private var contractSummary: String {
        "\(threadContract.audience.displayLabel) · \(threadContract.lifetime.displayLabel)"
    }

    var body: some View {
        VStack(spacing: 0) {
            contractBar
            if overridesOpen {
                overridePanel
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            if let err = sendError {
                Text(err)
                    .font(.systemScaled(11))
                    .foregroundStyle(.red)
                    .padding(.horizontal, ONE.Spacing.md)
                    .padding(.top, ONE.Spacing.xs)
            }
            inputRow
        }
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Divider().opacity(0.4)
        }
        .animation(ONE.Motion.adaptive(reduceMotion: reduceMotion), value: overridesOpen)
        .ailPreSendGate(dmSendGate)
    }

    // MARK: - Contract bar

    private var contractBar: some View {
        HStack(spacing: ONE.Spacing.sm) {
            Image(systemName: "lock.fill")
                .font(.systemScaled(10))
                .foregroundStyle(ONE.Colors.privateIndigo)

            Text(contractSummary)
                .font(.systemScaled(11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            Button {
                withAnimation(ONE.Motion.adaptive(reduceMotion: reduceMotion)) {
                    overridesOpen.toggle()
                }
            } label: {
                Text(overridesOpen ? "Done" : "Override ›")
                    .font(.systemScaled(11, weight: .medium))
                    .foregroundStyle(ONE.Colors.privateIndigo)
                    .padding(.horizontal, ONE.Spacing.sm)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(ONE.Colors.privateIndigo.opacity(0.10)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(overridesOpen ? "Close permission overrides" : "Override permissions for this message")
        }
        .padding(.horizontal, ONE.Spacing.md)
        .padding(.vertical, ONE.Spacing.sm)
    }

    // MARK: - Override panel

    private var overridePanel: some View {
        VStack(alignment: .leading, spacing: ONE.Spacing.sm) {
            Text("Override for this message")
                .font(.systemScaled(11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, ONE.Spacing.md)

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: ONE.Spacing.sm
            ) {
                permToggle("Forward",   isOn: $overrides.forwardAllowed)
                permToggle("Save",      isOn: $overrides.saveAllowed)
                permToggle("Quote",     isOn: $overrides.quoteAllowed)
                permToggle("Summarize", isOn: $overrides.summarizeAllowed)
            }
            .padding(.horizontal, ONE.Spacing.md)

            if overrides.forwardAllowed || overrides.saveAllowed {
                privacyWarning
                    .padding(.horizontal, ONE.Spacing.md)
            }
        }
        .padding(.vertical, ONE.Spacing.sm)
    }

    private func permToggle(_ label: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(label)
                .font(.systemScaled(13))
                .foregroundStyle(.primary)
            Spacer()
            Toggle(label, isOn: isOn)
                .labelsHidden()
                .tint(ONE.Colors.repairGreen)
        }
        .padding(.horizontal, ONE.Spacing.sm)
        .padding(.vertical, ONE.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .accessibilityLabel("\(label): \(isOn.wrappedValue ? "allowed" : "not allowed")")
    }

    private var privacyWarning: some View {
        HStack(spacing: ONE.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.systemScaled(12))
                .foregroundStyle(.orange)
            Text("Enabling forward or save reduces the recipient's privacy. They will see this change.")
                .font(.systemScaled(11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(ONE.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.orange.opacity(0.08))
                .stroke(Color.orange.opacity(0.22), lineWidth: 0.5)
        )
    }

    // MARK: - Input row

    private var inputRow: some View {
        HStack(alignment: .bottom, spacing: ONE.Spacing.sm) {
            lockButton

            TextField("Message", text: $text, axis: .vertical)
                .font(.systemScaled(15))
                .lineLimit(1...5)
                .focused($isFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.primary.opacity(0.07))
                        .stroke(Color.primary.opacity(0.09), lineWidth: 0.5)
                )

            sendButton
        }
        .padding(.horizontal, ONE.Spacing.md)
        .padding(.vertical, ONE.Spacing.sm)
        .padding(.bottom, ONE.Spacing.sm)
    }

    private var lockButton: some View {
        Button {
            withAnimation(ONE.Motion.adaptive(reduceMotion: reduceMotion)) {
                overridesOpen.toggle()
            }
        } label: {
            Image(systemName: "lock.fill")
                .font(.systemScaled(16))
                .foregroundStyle(overridesOpen ? ONE.Colors.privateIndigo : Color.secondary)
                .frame(width: 36, height: 36)
                .background(
                    Circle().fill(
                        overridesOpen
                            ? ONE.Colors.privateIndigo.opacity(0.14)
                            : Color.primary.opacity(0.06)
                    )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Privacy permissions")
        .accessibilityHint("Toggle per-message permission overrides")
    }

    private var sendButton: some View {
        Button {
            // Route through AIL pre-send gate (C10/C11, isDirectMessage: true).
            // When interceptor is disabled (default), forwards straight to trySend.
            let draft = text
            dmSendGate.submit(draft: draft) { _ in
                Task { await trySend() }
            }
        } label: {
            Image(systemName: "arrow.up")
                .font(.systemScaled(16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(
                    Circle().fill(
                        canSend
                            ? ONE.Colors.privateIndigo
                            : Color.secondary.opacity(0.35)
                    )
                )
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
        .accessibilityLabel("Send message")
    }

    // MARK: - Send

    private func trySend() async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSending = true
        sendError = nil
        defer { isSending = false }
        do {
            try await onSend(trimmed, overrides)
            text = ""
            overridesOpen = false
            overrides = threadContract.permissions
        } catch {
            sendError = error.localizedDescription
        }
    }
}
