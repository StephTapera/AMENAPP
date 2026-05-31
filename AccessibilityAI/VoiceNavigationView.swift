// VoiceNavigationView.swift
// AMEN Universal Accessibility Engine — A7 Voice Navigation UI

import SwiftUI
import Combine

// MARK: - Voice Navigation FAB

/// Floating action button placed at bottom-trailing.
/// Only renders when `a11yNavigationEnabled` is on.
struct VoiceNavigationFAB: View {
    @ObservedObject private var service = VoiceNavigationService.shared
    @ObservedObject private var flags = TrustAccessibilityFeatureFlags.shared
    @Environment(\.accessibilityReduceMotion) private var reducedMotion

    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        if flags.a11yNavigationEnabled {
            VStack(spacing: 6) {
                // Toast caption above the FAB when a command fires.
                if let toast = service.commandToast {
                    Text(toast)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: Capsule())
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }

                Button {
                    Task {
                        if service.isListening {
                            service.stopListening()
                        } else {
                            await service.startListening()
                        }
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.amenPurple)
                            .frame(width: 56, height: 56)
                        Image(systemName: "mic.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .scaleEffect(service.isListening ? pulseScale : 1.0)
                .accessibilityLabel("Voice navigation. Double-tap to start listening.")
                .accessibilityHint(service.isListening ? "Listening for a command." : "Activates voice control.")
                .onChange(of: service.isListening) { _, listening in
                    if listening && !reducedMotion {
                        startPulse()
                    } else {
                        stopPulse()
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: service.commandToast)
        }
    }

    // MARK: - Pulse Animation

    private func startPulse() {
        withAnimation(
            .easeInOut(duration: 0.8)
            .repeatForever(autoreverses: true)
        ) {
            pulseScale = 1.15
        }
    }

    private func stopPulse() {
        withAnimation(.easeInOut(duration: 0.2)) {
            pulseScale = 1.0
        }
    }
}

// MARK: - Color Token

private extension Color {
    /// Maps to AMEN's amenPurple design token.
    static var amenPurple: Color {
        Color("amenPurple", bundle: nil)
    }
}
