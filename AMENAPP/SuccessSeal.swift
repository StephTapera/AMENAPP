//
//  SuccessSeal.swift
//  AMENAPP
//
//  Reusable glass-pill confirmation that appears near a button after a
//  backend-confirmed action (post, comment, message send, etc.).
//
//  Usage:
//    @StateObject private var seal = SuccessSealController()
//
//    Button { seal.trigger() } label: { ... }
//        .successSeal(isActive: seal.isVisible, label: "Sent")
//

import SwiftUI
import UIKit

// MARK: - SuccessSeal View

/// A frosted-glass capsule showing a checkmark + label.
/// Typically shown for ~0.88 s then auto-dismissed via SuccessSealController.
struct SuccessSeal: View {
    let label: String
    var systemImage: String = "checkmark.circle.fill"

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
    }
}

// MARK: - SuccessSealModifier

struct SuccessSealModifier: ViewModifier {
    let isActive: Bool
    let label: String
    var systemImage: String = "checkmark.circle.fill"
    /// Where the pill appears relative to the modified view.
    var placement: Alignment = .top
    /// Fine-tune offset if the default doesn't clear the button.
    var yOffset: CGFloat = -44

    func body(content: Content) -> some View {
        content
            .overlay(alignment: placement) {
                if isActive {
                    SuccessSeal(label: label, systemImage: systemImage)
                        .offset(y: yOffset)
                        .transition(
                            .asymmetric(
                                insertion: .scale(scale: 0.72, anchor: .bottom)
                                    .combined(with: .opacity),
                                removal: .scale(scale: 0.88, anchor: .bottom)
                                    .combined(with: .opacity)
                            )
                        )
                        .zIndex(100)
                        .allowsHitTesting(false)
                }
            }
            .animation(
                UIAccessibility.isReduceMotionEnabled
                    ? .easeInOut(duration: 0.16)
                    : .spring(response: 0.24, dampingFraction: 0.72),
                value: isActive
            )
    }
}

extension View {
    /// Overlays a brief glass-pill confirmation near the button when `isActive` is true.
    func successSeal(
        isActive: Bool,
        label: String,
        systemImage: String = "checkmark.circle.fill",
        placement: Alignment = .top,
        yOffset: CGFloat = -44
    ) -> some View {
        modifier(SuccessSealModifier(
            isActive: isActive,
            label: label,
            systemImage: systemImage,
            placement: placement,
            yOffset: yOffset
        ))
    }
}

// MARK: - SuccessSealController

/// Manages the timed appearance of a SuccessSeal.
/// Callers just call `trigger()` — no timer bookkeeping needed.
@MainActor
final class SuccessSealController: ObservableObject {
    @Published private(set) var isVisible = false
    private var dismissTask: Task<Void, Never>?

    /// Show the seal for `duration` seconds, then auto-hide.
    /// Calling trigger() while already visible restarts the timer cleanly.
    func trigger(duration: TimeInterval = 0.88) {
        dismissTask?.cancel()
        withAnimation { isVisible = true }
        dismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            withAnimation { isVisible = false }
        }
    }

    deinit { dismissTask?.cancel() }
}

// MARK: - BreathingDotView

/// A standalone pulsing indicator dot for streaming / live / loading states.
/// Distinct from BreathingStreamIndicator inside BereanMessageBubbleView —
/// this one is fully reusable anywhere in the app.
struct BreathingDotView: View {
    var color: Color = .blue
    var size: CGFloat = 8
    /// Set false to pause the animation (e.g., when streaming stops).
    var isAnimating: Bool = true

    @State private var phase = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .scaleEffect(phase ? 1.35 : 0.9)
            .opacity(phase ? 0.35 : 0.85)
            .animation(
                isAnimating
                    ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                    : .default,
                value: phase
            )
            .onAppear { if isAnimating { phase = true } }
            .onChange(of: isAnimating) { _, animating in
                phase = animating
            }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("SuccessSeal") {
    VStack(spacing: 40) {
        SuccessSeal(label: "Sent")
        SuccessSeal(label: "Posted")
        SuccessSeal(label: "Saved", systemImage: "bookmark.circle.fill")

        HStack(spacing: 16) {
            BreathingDotView(color: .blue, size: 10)
            BreathingDotView(color: .green, size: 8)
            BreathingDotView(color: .purple, size: 12)
        }
    }
    .padding()
}
#endif
