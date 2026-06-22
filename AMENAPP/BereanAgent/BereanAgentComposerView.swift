// BereanAgentComposerView.swift
// AMEN — Berean Agent Surface (BAS) Wave 1, Lane B
//
// Floating glass composer that sits above the keyboard.
// Design §2: Liquid Glass (.glassEffect), warm paper bg, tan surface,
// wine-red accent (one element per screen), 24pt corners, soft shadow.
// All animations gated by @Environment(\.accessibilityReduceMotion).
// NO glass-on-glass. SF system font for UI. Fully accessible.
//
// Lane rule: ONLY writes to BereanAgent/. No outside-lane references.
// Type prefix: BAS* for all new types in this file.

import SwiftUI

// MARK: - BereanAgentComposerView

/// Floating Liquid Glass composer panel that lives above the keyboard.
/// Stateless by design — the caller owns send/plugin/voice actions.
struct BereanAgentComposerView: View {

    // MARK: Init

    let onSend: (String, BASComposerMode) -> Void
    let onPluginDrawerRequested: () -> Void
    let onVoiceRequested: () -> Void

    init(
        onSend: @escaping (String, BASComposerMode) -> Void,
        onPluginDrawerRequested: @escaping () -> Void,
        onVoiceRequested: @escaping () -> Void
    ) {
        self.onSend = onSend
        self.onPluginDrawerRequested = onPluginDrawerRequested
        self.onVoiceRequested = onVoiceRequested
    }

    // MARK: State

    @State private var activeMode: BASComposerMode = .ask
    @State private var text: String = ""

    // MARK: Environment

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Observed directly so private-mode pill stays in sync.
    @State private var broker = BASPermissionBroker.shared

    // MARK: Body

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            VStack(spacing: 0) {
                modeSelectorRow
                    .padding(.horizontal, 12)
                    .padding(.top, 12)

                textEntryArea
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                toolbarRow
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }
            .amenGlassEffect(in: .rect(cornerRadius: 24))
            .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 4)
        }
        .padding(.horizontal, 16)
    }

    // MARK: Mode Selector Row

    private var modeSelectorRow: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(BASComposerMode.allCases) { mode in
                        BASSModeSelectorChip(
                            mode: mode,
                            isActive: activeMode == mode,
                            reduceMotion: reduceMotion,
                            onTap: {
                                switchMode(to: mode)
                            },
                            onDismiss: activeMode == mode ? {
                                switchMode(to: .ask)
                            } : nil
                        )
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 4)
            }

            // §7 Private pill — shown when broker.isPrivateModeActive
            if broker.isPrivateModeActive {
                BASSPrivatePill()
                    .padding(.leading, 8)
                    .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
            }
        }
    }

    // MARK: Text Entry

    private var textEntryArea: some View {
        ZStack(alignment: .topLeading) {
            // Placeholder text
            if text.isEmpty {
                Text(activeMode.placeholder)
                    .font(.body)
                    .foregroundStyle(Color.basInk.opacity(0.4))
                    .padding(.top, 8)
                    .padding(.leading, 4)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $text)
                .font(.body)
                .foregroundStyle(Color.basInk)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .frame(minHeight: 48, maxHeight: 120)
                .accessibilityLabel(activeMode.placeholder)
                .accessibilityHint("Type your message here")
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.basTan.opacity(0.45))
        )
    }

    // MARK: Toolbar

    private var toolbarRow: some View {
        HStack(spacing: 16) {
            // @ — Plugin drawer
            Button {
                onPluginDrawerRequested()
            } label: {
                Image(systemName: "at")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.basInk.opacity(0.7))
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("Insert plugin")
            .accessibilityHint("Opens the plugin selection drawer")

            // Mic — Voice input
            Button {
                onVoiceRequested()
            } label: {
                Image(systemName: "mic.fill")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.basInk.opacity(0.7))
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("Voice input")
            .accessibilityHint("Speak your message")

            Spacer()

            // Send button — wine-red, one accent per screen
            Button {
                handleSend()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up")
                        .font(.footnote.weight(.semibold))
                    Text("Send")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(Color.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(
                    Capsule()
                        .fill(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              ? Color.basWineRed.opacity(0.4)
                              : Color.basWineRed)
                )
            }
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Send message")
            .accessibilityHint("Sends your message in \(activeMode.displayName) mode")
        }
    }

    // MARK: Actions

    private func switchMode(to mode: BASComposerMode) {
        let animation: Animation? = reduceMotion
            ? nil
            : Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.8))
        withAnimation(animation) {
            activeMode = mode
        }
    }

    private func handleSend() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSend(trimmed, activeMode)
        text = ""
    }
}

// MARK: - BASSModeSelectorChip

/// Individual mode chip inside the horizontal mode selector scroll view.
/// Active chips are wine-red; inactive chips are tan.
private struct BASSModeSelectorChip: View {

    let mode: BASComposerMode
    let isActive: Bool
    let reduceMotion: Bool
    let onTap: () -> Void
    let onDismiss: (() -> Void)?

    var body: some View {
        HStack(spacing: 4) {
            Text(mode.displayName)
                .font(.footnote.weight(isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? Color.white : Color.basInk)

            if isActive, onDismiss != nil {
                Button {
                    onDismiss?()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(.caption2, design: .default).weight(.bold))
                        .foregroundStyle(Color.white.opacity(0.85))
                }
                .accessibilityLabel("Remove \(mode.displayName) mode")
                .accessibilityHint("Deselects \(mode.displayName) mode and returns to Ask")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(isActive ? Color.basWineRed : Color.basTan.opacity(0.7))
        )
        .contentShape(Capsule())
        .onTapGesture {
            onTap()
        }
        .accessibilityLabel("\(mode.displayName) mode\(isActive ? ", selected" : "")")
        .accessibilityHint(isActive ? "" : "Switches the composer to \(mode.displayName) mode")
        .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : .isButton)
        .animation(
            reduceMotion ? nil : Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.8)),
            value: isActive
        )
    }
}

// MARK: - BASSPrivatePill

/// Subtle trailing pill shown when BASPermissionBroker.shared.isPrivateModeActive.
private struct BASSPrivatePill: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "lock.fill")
                .font(.system(.caption2, design: .default).weight(.medium))
            Text("Private")
                .font(.caption2.weight(.medium))
        }
        .foregroundStyle(Color.basInk.opacity(0.65))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color.basTan.opacity(0.6))
        )
        .accessibilityLabel("Private mode active")
        .accessibilityAddTraits(.isStaticText)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Composer — Ask mode") {
    VStack {
        Spacer()
        BereanAgentComposerView(
            onSend: { text, mode in
                print("Send: \(text) in \(mode.displayName)")
            },
            onPluginDrawerRequested: {
                print("Plugin drawer requested")
            },
            onVoiceRequested: {
                print("Voice requested")
            }
        )
        .padding(.bottom, 16)
    }
    .background(Color.basWarmPaper)
}
#endif
