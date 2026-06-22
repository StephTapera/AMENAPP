// BereanComposer.swift
// AMENAPP — Floating glass composer bar for the Berean assistant.
// Frozen contract:
//   BereanComposer(
//       state: Binding<ComposerState>,
//       onPlus: () -> Void,
//       onSend: (String) -> Void,
//       onMic: () -> Void,
//       onVoice: () -> Void
//   )

import SwiftUI

struct BereanComposer: View {

    @Binding var state: ComposerState
    let onPlus: () -> Void
    let onSend: (String) -> Void
    let onMic: () -> Void
    let onVoice: () -> Void

    @FocusState private var isFieldFocused: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Whether voice-mode is live. Owned here so BereanVoiceButton can read it.
    @State private var voiceActive: Bool = false

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            composerCapsule
                .padding(.horizontal, DesignTokens.spacingXL)
                .padding(.bottom, isFieldFocused ? DesignTokens.spacingS : 0)
        }
        .ignoresSafeArea(.keyboard)
    }

    // MARK: - Capsule Shell

    private var composerCapsule: some View {
        HStack(alignment: .bottom, spacing: DesignTokens.spacingS) {
            plusButton
            textField
            trailingControls
        }
        .padding(.horizontal, DesignTokens.spacingM)
        .padding(.vertical, 10)
        .background(capsuleBackground)
    }

    // MARK: - Background

    @ViewBuilder
    private var capsuleBackground: some View {
        if reduceTransparency {
            // Solid accessible fallback: opaque surface + hairline separator border
            Capsule(style: .continuous)
                .fill(Color(.systemBackground))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color(.separator), lineWidth: 0.5)
                )
                .shadow(color: DesignTokens.shadowElevated, radius: 16, x: 0, y: 6)
        } else {
            // Live glass capsule — reuses LiquidGlassCapsuleBackground
            LiquidGlassCapsuleBackground(
                cornerRadius: DesignTokens.radiusCapsule,
                glassOpacity: 0.06,
                shadowOpacity: 0.10,
                highlightOpacity: 0.26
            )
        }
    }

    // MARK: - Plus Button

    private var plusButton: some View {
        Button {
            HapticManager.impact(style: .light)
            withAnimation(reduceMotion ? .none : .amenSpringEntry) {
                state.isTrayOpen.toggle()
            }
            onPlus()
        } label: {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Circle()
                            .fill(DesignTokens.glassFill)
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        DesignTokens.glassStroke,
                                        DesignTokens.glassStroke.opacity(0.2)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.75
                            )
                    )
                    .frame(width: 40, height: 40)

                Image(systemName: "plus")
                    .font(.systemScaled(19, weight: .semibold))
                    .foregroundStyle(DesignTokens.textPrimary)
                    .rotationEffect(
                        state.isTrayOpen
                            ? .degrees(45)
                            : .degrees(0)
                    )
                    .animation(
                        reduceMotion ? .none : .amenSpringEntry,
                        value: state.isTrayOpen
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open actions tray")
    }

    // MARK: - Text Field

    private var textField: some View {
        TextField(
            "Ask Berean",
            text: $state.text,
            axis: .vertical
        )
        .lineLimit(1...5)
        .font(.body)
        .foregroundStyle(DesignTokens.textPrimary)
        .tint(DesignTokens.accentBlue)
        .focused($isFieldFocused)
        .submitLabel(.send)
        .onSubmit {
            guard !state.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            sendMessage()
        }
        .accessibilityLabel("Message Berean")
    }

    // MARK: - Trailing Controls

    private var trailingControls: some View {
        HStack(alignment: .bottom, spacing: DesignTokens.spacingS) {
            if state.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // Mic button — visible when field is empty
                micButton
                    .transition(
                        .asymmetric(
                            insertion: .scale.combined(with: .opacity),
                            removal: .scale.combined(with: .opacity)
                        )
                    )
            } else {
                // Send button — replaces mic when text is present
                sendButton
                    .transition(
                        .asymmetric(
                            insertion: .scale.combined(with: .opacity),
                            removal: .scale.combined(with: .opacity)
                        )
                    )
            }

            // Voice orb — always visible
            BereanVoiceButton(isActive: voiceActive) {
                voiceActive.toggle()
                onVoice()
            }
        }
        .animation(reduceMotion ? .none : .amenEaseQuick, value: state.text.isEmpty)
    }

    // MARK: - Mic Button

    private var micButton: some View {
        Button {
            onMic()
        } label: {
            Image(systemName: "mic.fill")
                .font(.systemScaled(18, weight: .medium))
                .foregroundStyle(DesignTokens.textSecondary)
                .frame(width: 38, height: 38)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Voice input")
    }

    // MARK: - Send Button

    private var sendButton: some View {
        Button {
            sendMessage()
        } label: {
            ZStack {
                Circle()
                    .fill(Color.black)
                    .frame(width: 38, height: 38)

                Image(systemName: "arrow.up")
                    .font(.systemScaled(15, weight: .semibold))
                    .foregroundStyle(Color.white)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Send message")
    }

    // MARK: - Send Action

    private func sendMessage() {
        let trimmed = state.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        HapticManager.impact(style: .medium)
        onSend(trimmed)
        withAnimation(reduceMotion ? .none : .amenEaseQuick) {
            state.text = ""
        }
        isFieldFocused = false
        HapticManager.notification(type: .success)
    }
}

// MARK: - Preview

#Preview {
    ZStack(alignment: .bottom) {
        Color(red: 0.971, green: 0.971, blue: 0.969)
            .ignoresSafeArea()

        BereanComposer(
            state: .constant(ComposerState()),
            onPlus: {},
            onSend: { _ in },
            onMic: {},
            onVoice: {}
        )
    }
}
