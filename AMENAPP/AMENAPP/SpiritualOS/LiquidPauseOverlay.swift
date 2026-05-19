import SwiftUI

struct LiquidPauseOverlay: View {
    let triggerType: MomentTriggerType?
    let riskScore: Double
    let onAction: (MomentUserAction) -> Void

    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Blur backdrop
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture {} // consume taps

            VStack(spacing: 24) {
                BreathPauseRing(isAnimating: appeared)
                    .frame(width: 80, height: 80)

                VStack(spacing: 10) {
                    Text("Pause.")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Color.primary)
                    Text("This moment may matter more than the message.")
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 10) {
                    pauseActionButton(label: "Breathe for 10 seconds", icon: "wind", action: .breathed, primary: true)
                    pauseActionButton(label: "Pray first", icon: "hands.sparkles", action: .prayedFirst, primary: false)
                    pauseActionButton(label: "Save as draft", icon: "tray.and.arrow.down", action: .savedDraft, primary: false)
                    pauseActionButton(label: "Run Peace Check", icon: "checkmark.seal", action: .ranPeaceCheck, primary: false)
                }

                Button(action: { onAction(.continuedAnyway) }) {
                    Text("Continue anyway")
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                }
                .accessibilityLabel("Continue anyway without pausing")
            }
            .padding(28)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
            .shadow(color: Color.black.opacity(0.15), radius: 40, y: 16)
            .padding(.horizontal, 24)
            .scaleEffect(appeared ? 1.0 : (reduceMotion ? 1.0 : 0.92))
            .opacity(appeared ? 1.0 : 0.0)
        }
        .onAppear {
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                    appeared = true
                }
            }
        }
    }

    private func pauseActionButton(label: String, icon: String, action: MomentUserAction, primary: Bool) -> some View {
        Button(action: { onAction(action) }) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 24)
                Text(label)
                    .font(.subheadline.weight(primary ? .semibold : .regular))
                Spacer()
            }
            .foregroundStyle(primary ? Color.primary : Color.secondary)
            .padding(.horizontal, 18)
            .padding(.vertical, 13)
            .background {
                if primary {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.primary.opacity(0.07))
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.clear)
                }
            }
        }
        .accessibilityLabel(label)
    }
}

// MARK: - Breath Pause Ring

struct BreathPauseRing: View {
    let isAnimating: Bool

    @State private var scale: CGFloat = 1.0
    @State private var opacity: Double = 0.5
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.15), lineWidth: 3)
            Circle()
                .stroke(Color.secondary.opacity(opacity), lineWidth: 2)
                .scaleEffect(scale)
            Image(systemName: "leaf")
                .font(.title2)
                .foregroundStyle(Color.secondary)
        }
        .onAppear {
            guard isAnimating, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 4.0).repeatForever(autoreverses: true)) {
                scale = 1.3
                opacity = 0.9
            }
        }
        .accessibilityLabel("Breathing ring animation")
        .accessibilityHidden(true)
    }
}

// MARK: - Moment Interception Overlay

struct MomentInterceptionOverlay: View {
    @StateObject private var service = MomentInterceptionService.shared

    var body: some View {
        if service.shouldShowOverlay {
            LiquidPauseOverlay(
                triggerType: service.currentTrigger,
                riskScore: service.currentRiskScore,
                onAction: { action in
                    Task {
                        await service.recordUserAction(
                            action,
                            triggerType: service.currentTrigger ?? .impulsiveSend,
                            source: "overlay"
                        )
                    }
                }
            )
            .transition(reduceMotionTransition)
            .zIndex(100)
        }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var reduceMotionTransition: AnyTransition {
        reduceMotion ? .opacity : .scale(scale: 0.95).combined(with: .opacity)
    }
}
