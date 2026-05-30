// CrisisBereanModule.swift
// AMENAPP
//
// Berean in Crisis Reflect Mode.
// Rules:
//   - Calm, present, low-pressure, non-judgmental tone
//   - No debate, no theology-heavy discourse, no productivity framing
//   - Scripture only on request or if confidence threshold is safe
//   - If high-risk language detected → surface 988 inline (escalation banner)
//   - Never implies it replaces professional or emergency help
//   - Quick actions: Breathe, Name it, Get help
//

import SwiftUI

// MARK: - Berean Reflect Module

struct CrisisBereanModule: View {
    @Bindable var viewModel: CrisisSupportViewModel
    @State private var userInput: String = ""
    @FocusState private var inputFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            // Dark Berean card
            bereanCard

            // Escalation banner — shown when high-risk language detected
            if viewModel.bereanEscalationVisible {
                escalationBanner
                    .padding(.top, 10)
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            }
        }
        .animation(reduceMotion ? .none : CrisisAnimationTokens.bereanReveal, value: viewModel.bereanEscalationVisible)
    }

    // MARK: - Berean Card

    private var bereanCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Berean — Reflect Mode")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Presence first. Non-judgmental. Private.")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.52))
                }
                Spacer()
                safeModeBadge
            }
            .padding(.bottom, 16)

            // Response area
            Text(viewModel.bereanPrompt)
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.90))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .animation(reduceMotion ? .none : CrisisAnimationTokens.bereanReveal, value: viewModel.bereanPrompt)

            // Quick actions
            quickActionsRow
                .padding(.top, 16)

            // Divider
            Rectangle()
                .fill(.white.opacity(0.10))
                .frame(height: 0.5)
                .padding(.top, 16)

            // Input row
            inputRow
                .padding(.top, 12)

            // Disclaimer
            Text("Berean supports you but does not replace emergency or professional care.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.34))
                .padding(.top, 14)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(red: 0.071, green: 0.071, blue: 0.082))
                // Subtle top specular
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.06), .clear],
                            startPoint: .top,
                            endPoint: UnitPoint(x: 0.5, y: 0.30)
                        )
                    )
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 0.8)
            }
        )
        .shadow(color: .black.opacity(0.20), radius: 24, y: 10)
    }

    // MARK: - Safe Mode Badge

    private var safeModeBadge: some View {
        Text("Safe mode")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white.opacity(0.55))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(.white.opacity(0.09))
                    .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 0.6))
            )
    }

    // MARK: - Quick Actions

    private var quickActionsRow: some View {
        HStack(spacing: 8) {
            ForEach(["Breathe", "Name it", "Get help"], id: \.self) { label in
                BereanQuickActionPill(label: label) {
                    viewModel.bereanQuickAction(label)
                }
            }
        }
    }

    // MARK: - Input Row

    private var inputRow: some View {
        HStack(spacing: 10) {
            TextField("Say anything — this is private.", text: $userInput, axis: .vertical)
                .font(.system(size: 14))
                .foregroundStyle(.white)
                .tint(.white)
                .lineLimit(1...4)
                .focused($inputFocused)
                .onChange(of: userInput) { _, new in
                    viewModel.detectHighRiskLanguage(in: new)
                }
                .submitLabel(.send)
                .onSubmit { sendMessage() }

            if !userInput.isEmpty {
                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.white.opacity(0.70))
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(.white.opacity(0.10), lineWidth: 0.6)
                )
        )
    }

    // MARK: - Escalation Banner

    private var escalationBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "phone.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.red))

            VStack(alignment: .leading, spacing: 2) {
                Text("You're not alone — help is available now.")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("The 988 Lifeline is free and confidential, 24/7.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                viewModel.callNumber(viewModel.localeResources.crisisHotlineNumber)
            } label: {
                Text("Call")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color.red))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(red: 1.00, green: 0.93, blue: 0.93))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.red.opacity(0.18), lineWidth: 0.7)
                )
        )
    }

    // MARK: - Actions

    private func sendMessage() {
        let text = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        viewModel.bereanQuickAction(text)
        withAnimation(reduceMotion ? nil : CrisisAnimationTokens.bereanReveal) {
            userInput = ""
        }
        inputFocused = false
    }
}

// MARK: - Quick Action Pill

private struct BereanQuickActionPill: View {
    let label: String
    let onTap: () -> Void
    @State private var isPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onTap) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.78))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(.white.opacity(0.09))
                        .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 0.6))
                )
                .scaleEffect(isPressed ? 0.96 : 1.0)
                .animation(reduceMotion ? .none : .interactiveSpring(response: 0.20, dampingFraction: 0.70), value: isPressed)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded   { _ in isPressed = false }
        )
        .accessibilityLabel(label)
    }
}
