// AmenActionTray.swift
// AMENAPP — Berean assistant composer attachment tray.
//
// Surfaces as a floating Liquid Glass menu rising from the composer's + button.
// Contract: AmenActionTray(isPresented: Binding<Bool>, onSelect: (TrayAction) -> Void)
// Source of truth: BereanIntelligenceContracts.swift (TrayAction, DesignTokens, bereanLiquidGlass)

import SwiftUI
import FirebaseAuth

// MARK: - AmenActionTray

struct AmenActionTray: View {

    @Binding var isPresented: Bool
    let onSelect: (TrayAction) -> Void

    // MARK: - State

    @State private var appeared = false
    @State private var moderatingAction: TrayAction? = nil
    @State private var blockedAction: TrayAction? = nil

    // MARK: - Environment

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Dismiss backdrop — invisible, covers the rest of the screen.
            if isPresented {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture {
                        dismiss()
                    }
            }

            // Tray panel
            trayPanel
                .frame(maxWidth: 320)
                .padding(.leading, 16)
                .padding(.bottom, 8)
                .opacity(appeared ? 1 : 0)
                .scaleEffect(appeared ? 1 : 0.94, anchor: .bottom)
                .transition(
                    reduceMotion
                        ? .opacity
                        : .move(edge: .bottom).combined(with: .opacity)
                )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .onAppear {
            let animation: Animation = reduceMotion
                ? .easeOut(duration: 0.08)
                : .spring(response: 0.38, dampingFraction: 0.82)
            withAnimation(animation) {
                appeared = true
            }
        }
        .onDisappear {
            appeared = false
            moderatingAction = nil
            blockedAction = nil
        }
    }

    // MARK: - Tray Panel

    private var trayPanel: some View {
        VStack(spacing: 0) {
            ForEach(Array(TrayAction.allCases.enumerated()), id: \.element.id) { index, action in
                trayRow(action: action, index: index)

                if index < TrayAction.allCases.count - 1 {
                    Divider()
                        .background(Color.black.opacity(0.06))
                        .padding(.leading, 52)
                }
            }
        }
        .padding(.vertical, 6)
        .background(trayBackground)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(trayBorder)
        .shadow(color: reduceTransparency ? .clear : .black.opacity(0.12), radius: 18, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Berean actions tray")
    }

    // MARK: - Tray Background

    @ViewBuilder
    private var trayBackground: some View {
        if reduceTransparency {
            Color(.secondarySystemBackground)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white.opacity(0.70))
            }
        }
    }

    // MARK: - Tray Border

    @ViewBuilder
    private var trayBorder: some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color(.separator), lineWidth: 0.5)
        } else {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.60), lineWidth: 0.75)
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func trayRow(action: TrayAction, index: Int) -> some View {
        let isBeingModerated = moderatingAction == action
        let wasBlocked       = blockedAction == action

        Button {
            handleTap(action)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: action.systemImage)
                    .font(.systemScaled(20, weight: .regular))
                    .foregroundStyle(.primary)
                    .frame(width: 28)

                Text(action.title)
                    .font(.systemScaled(15, weight: .medium))
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)

                if wasBlocked {
                    Text("Safety check failed")
                        .font(.systemScaled(12, weight: .regular))
                        .foregroundStyle(DesignTokens.accentBlue.opacity(0.9))
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                } else if isBeingModerated {
                    ProgressView()
                        .controlSize(.small)
                        .tint(DesignTokens.accentBlue)
                        .transition(.opacity)
                } else if action.requiresModeration {
                    Image(systemName: "checkmark.shield")
                        .font(.systemScaled(14, weight: .regular))
                        .foregroundStyle(DesignTokens.accentBlue.opacity(0.7))
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(BereanAccessibility.trayActionLabel(action))
        .animation(
            reduceMotion
                ? .none
                : .spring(response: 0.4).delay(Double(index) * 0.03),
            value: appeared
        )
        .animation(.amenSnappy, value: isBeingModerated)
        .animation(.amenSnappy, value: wasBlocked)
        .disabled(isBeingModerated)
    }

    // MARK: - Tap Handling

    private func handleTap(_ action: TrayAction) {
        if action.requiresModeration {
            runModerationGate(for: action)
        } else {
            HapticManager.impact(style: .medium)
            onSelect(action)
            dismiss()
        }
    }

    private func runModerationGate(for action: TrayAction) {
        guard moderatingAction == nil else { return }

        withAnimation(.amenSnappy) {
            moderatingAction = action
            blockedAction = nil
        }

        Task { @MainActor in
            defer {
                withAnimation(.amenSnappy) {
                    moderatingAction = nil
                }
            }

            let userId = Auth.auth().currentUser?.uid
            let request = BereanAIRequest(
                surface: .bereanChat,
                category: .safetyScreening,
                userInput: "moderation_gate_\(action.rawValue)",
                userId: userId,
                allowCache: false
            )

            let response = await BereanCoreService.shared.process(request)

            if response.safetyFlags.contains(where: { $0.actionRequired == .block }) {
                HapticManager.notification(type: .error)
                withAnimation(.amenSnappy) {
                    blockedAction = action
                }
                // Clear the blocked label after 2 seconds and dismiss.
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                withAnimation(.amenSnappy) {
                    blockedAction = nil
                }
            } else {
                HapticManager.impact(style: .medium)
                onSelect(action)
                dismiss()
            }
        }
    }

    // MARK: - Dismiss

    private func dismiss() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            appeared = false
        }
        // Delay isPresented flip slightly so the collapse animation plays.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            isPresented = false
        }
    }
}

// MARK: - Local Animation Tokens
// amenSpring and amenSnappy are not globally exported from the kit;
// they are also defined locally in AmenSimpleModeView. Redeclare them
// here as private to keep this file self-contained.

private extension Animation {
    static var amenSpring: Animation {
        .spring(response: 0.42, dampingFraction: 0.78)
    }
    static var amenSnappy: Animation {
        .spring(response: 0.22, dampingFraction: 0.70)
    }
}

// MARK: - Preview

#Preview("Action Tray — Default") {
    ZStack(alignment: .bottomLeading) {
        Color(.systemGroupedBackground).ignoresSafeArea()
        AmenActionTray(isPresented: .constant(true)) { action in
            print("Selected: \(action.title)")
        }
    }
}

#Preview("Action Tray — Reduce Transparency") {
    ZStack(alignment: .bottomLeading) {
        Color(.systemGroupedBackground).ignoresSafeArea()
        AmenActionTray(isPresented: .constant(true)) { action in
            print("Selected: \(action.title)")
        }
        // Note: accessibilityReduceTransparency is read-only; test via device/sim Accessibility settings
    }
}
