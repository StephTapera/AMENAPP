// BereanVoiceButton.swift
// AMENAPP — Blue voice orb for the Berean composer.
// Frozen contract: BereanVoiceButton(isActive: Bool, onToggle: () -> Void)

import SwiftUI

struct BereanVoiceButton: View {

    let isActive: Bool
    let onToggle: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Drives the pulse scale when active. Animated only when reduce-motion is off.
    @State private var pulseScale: CGFloat = 1.0

    // MARK: - Body

    var body: some View {
        Button(action: handleToggle) {
            ZStack {
                Circle()
                    .fill(DesignTokens.accentBlue)
                    .frame(width: 44, height: 44)
                    .shadow(
                        color: isActive
                            ? Color.blue.opacity(0.35)
                            : Color.black.opacity(0.20),
                        radius: isActive ? 12 : 8,
                        x: 0,
                        y: isActive ? 0 : 4
                    )

                Image(systemName: "waveform")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.white)
                    .allowsHitTesting(false)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isActive && !reduceMotion ? pulseScale : 1.0)
        .animation(.amenEaseQuick, value: isActive)
        .accessibilityLabel(
            isActive
                ? "Voice active, tap to stop"
                : "Start voice input"
        )
        .onChange(of: isActive) { _, newValue in
            if newValue && !reduceMotion {
                startPulse()
            } else {
                stopPulse()
            }
        }
        .onAppear {
            if isActive && !reduceMotion {
                startPulse()
            }
        }
    }

    // MARK: - Pulse

    private func startPulse() {
        withAnimation(
            .easeInOut(duration: 0.75)
            .repeatForever(autoreverses: true)
        ) {
            pulseScale = 1.10
        }
    }

    private func stopPulse() {
        withAnimation(.amenEaseQuick) {
            pulseScale = 1.0
        }
    }

    // MARK: - Actions

    private func handleToggle() {
        HapticManager.impact(style: .medium)
        onToggle()
    }
}

// MARK: - Preview

#Preview("Inactive") {
    BereanVoiceButton(isActive: false, onToggle: {})
        .padding()
}

#Preview("Active") {
    BereanVoiceButton(isActive: true, onToggle: {})
        .padding()
}
