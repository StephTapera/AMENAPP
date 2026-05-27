import SwiftUI

/// Center-screen floating indicator for transient feedback (playback speed, volume, etc.).
/// Auto-dismisses after `timeout` seconds with a fade-out; each new `value` resets the timer.
struct GlassHUD<Content: View>: View {
    /// Bind to whatever value triggers the HUD (speed, volume level, etc.).
    var triggerValue: AnyHashable
    var timeout: Double = 1.2
    @ViewBuilder var content: () -> Content

    @State private var isVisible = false
    @State private var dismissTask: Task<Void, Never>?

    @Environment(\.accessibilityReduceMotion)       private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        content()
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background { hudBackground }
            .shadow(
                color: LiquidGlassTokens.shadowFloating.color,
                radius: LiquidGlassTokens.shadowFloating.radius,
                y: LiquidGlassTokens.shadowFloating.y
            )
            .scaleEffect(isVisible ? 1 : 0.9)
            .opacity(isVisible ? 1 : 0)
            .animation(
                reduceMotion ? .easeOut(duration: LiquidGlassTokens.motionFast)
                             : .spring(response: 0.28, dampingFraction: 0.80),
                value: isVisible
            )
            .onChange(of: triggerValue) { _, _ in show() }
            .onAppear { show() }
            .onDisappear { dismissTask?.cancel() }
            .allowsHitTesting(false)
    }

    private func show() {
        isVisible = true
        dismissTask?.cancel()
        dismissTask = Task {
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation { isVisible = false }
            }
        }
    }

    @ViewBuilder private var hudBackground: some View {
        let r = LiquidGlassTokens.cornerRadiusLarge
        if reduceTransparency {
            RoundedRectangle(cornerRadius: r, style: .continuous)
                .fill(Color(.systemBackground))
                .overlay {
                    RoundedRectangle(cornerRadius: r, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                }
        } else {
            RoundedRectangle(cornerRadius: r, style: .continuous)
                .fill(LiquidGlassTokens.blurElevated)
                .overlay {
                    RoundedRectangle(cornerRadius: r, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.36), lineWidth: 0.75)
                }
        }
    }
}

// MARK: - Convenience modifier

extension View {
    /// Overlays a `GlassHUD` centered on screen, shown whenever `value` changes.
    func glassHUD<T: Hashable>(
        for value: T,
        timeout: Double = 1.2,
        @ViewBuilder content: @escaping () -> some View
    ) -> some View {
        overlay(alignment: .center) {
            GlassHUD(triggerValue: AnyHashable(value), timeout: timeout, content: content)
        }
    }
}
