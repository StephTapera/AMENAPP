// CrisisGroundingModule.swift
// AMENAPP
//
// Adaptive grounding tools module for the Crisis Support screen.
// One tool at a time, haptically guided, visually calm, no information overload.
// Supports: 5-4-3-2-1 sensory, box breathing, temperature reset, Psalm 23.
//

import SwiftUI

// MARK: - Grounding Module Content

struct CrisisGroundingModule: View {
    @Bindable var viewModel: CrisisSupportViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Tool selector pills
            toolSelectorRow

            // Active tool prompt
            if let mode = viewModel.activeGroundingMode {
                groundingPromptCard(mode: mode)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.97, anchor: .top)),
                            removal: .opacity
                        )
                    )
            } else {
                emptyPrompt
                    .transition(.opacity)
            }
        }
    }

    // MARK: - Tool Selector

    private var toolSelectorRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CrisisGroundingMode.allCases) { mode in
                    GroundingToolPill(
                        mode: mode,
                        isActive: viewModel.activeGroundingMode == mode,
                        onTap: { viewModel.selectGroundingMode(mode) }
                    )
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Grounding Prompt Card

    private func groundingPromptCard(mode: CrisisGroundingMode) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: mode.systemImage)
                    .font(.systemScaled(14, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(mode.label)
                    .font(.systemScaled(14, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Text(mode.prompt)
                .font(.systemScaled(15))
                .foregroundStyle(Color(UIColor.label).opacity(0.80))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            // Breathing ring for box breathing
            if mode == .boxBreathing {
                BreathingRingView()
                    .frame(height: 72)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.black.opacity(0.05), lineWidth: 0.6)
                )
        )
    }

    // MARK: - Empty State

    private var emptyPrompt: some View {
        Text("Choose a tool above. Take your time.")
            .font(.systemScaled(14))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
    }
}

// MARK: - Grounding Tool Pill

private struct GroundingToolPill: View {
    let mode: CrisisGroundingMode
    let isActive: Bool
    let onTap: () -> Void
    @State private var isPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: mode.systemImage)
                    .font(.systemScaled(11, weight: .semibold))
                Text(mode.label)
                    .font(.systemScaled(13, weight: .medium))
            }
            .foregroundStyle(isActive ? .white : .secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                Capsule()
                    .fill(isActive ? Color.black : Color(UIColor.secondarySystemGroupedBackground))
                    .shadow(
                        color: isActive ? .black.opacity(0.20) : .clear,
                        radius: 8,
                        y: 4
                    )
            )
            .scaleEffect(isPressed ? 0.96 : 1.0)
            .animation(
                reduceMotion ? nil : .interactiveSpring(response: 0.22, dampingFraction: 0.72),
                value: isPressed
            )
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded   { _ in isPressed = false }
        )
        .accessibilityLabel(mode.label)
        .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : .isButton)
    }
}

// MARK: - Breathing Ring

/// Gentle pulsing ring for box breathing guidance.
private struct BreathingRingView: View {
    @State private var phase: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.blue.opacity(0.10), lineWidth: 4)
                .frame(width: 56, height: 56)

            Circle()
                .stroke(Color.blue.opacity(0.35), lineWidth: 3)
                .frame(width: 56, height: 56)
                .scaleEffect(1.0 + 0.18 * sin(phase))
                .animation(
                    .easeInOut(duration: 4.0).repeatForever(autoreverses: true),
                    value: phase
                )

            Text("breathe")
                .font(.systemScaled(9, weight: .medium))
                .foregroundStyle(Color.blue.opacity(0.55))
        }
        .onAppear { phase = 1 }
    }
}
