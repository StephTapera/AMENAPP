import SwiftUI

// MARK: - GlassToastView

/// A glass pill anchored below the top safe area with an optional action button.
/// Auto-dismisses after `timeout` seconds. Respects Reduce Motion.
@MainActor
struct GlassToastView: View {
    var message: String
    var actionLabel: String?
    var onAction: (() -> Void)?
    @Binding var isVisible: Bool
    var timeout: Double = 5.0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @State private var dismissTask: Task<Void, Never>?

    var body: some View {
        if isVisible {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AmenTheme.Colors.amenGold)
                    .font(.body.weight(.semibold))
                    .accessibilityHidden(true)

                Text(message)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .lineLimit(2)

                if let label = actionLabel {
                    Spacer(minLength: 4)
                    Button(label) {
                        dismiss()
                        onAction?()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AmenTheme.Colors.amenGold)
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background { pillBackground }
            .shadow(
                color: LiquidGlassTokens.shadowFloating.color,
                radius: LiquidGlassTokens.shadowFloating.radius,
                y: LiquidGlassTokens.shadowFloating.y
            )
            .padding(.horizontal, 20)
            .transition(
                reduceMotion
                    ? .opacity
                    : .opacity.combined(with: .move(edge: .top))
            )
            .onAppear { scheduleDismiss() }
            .onDisappear { dismissTask?.cancel() }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(message)
        }
    }

    // MARK: - Helpers

    @ViewBuilder private var pillBackground: some View {
        if reduceTransparency {
            Capsule(style: .continuous)
                .fill(AmenTheme.Colors.surfaceElevated)
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(AmenTheme.Colors.separatorSubtle, lineWidth: 1)
                }
        } else {
            Capsule(style: .continuous)
                .fill(LiquidGlassTokens.blurElevated)
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(AmenTheme.Colors.glassStroke, lineWidth: 0.7)
                }
        }
    }

    private func scheduleDismiss() {
        dismissTask?.cancel()
        dismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }

    private func dismiss() {
        withAnimation(
            reduceMotion
                ? .easeOut(duration: LiquidGlassTokens.motionFast)
                : .spring(response: LiquidGlassTokens.motionNormal, dampingFraction: 0.82)
        ) {
            isVisible = false
        }
    }
}

// MARK: - Convenience modifier

extension View {
    /// Overlays a `GlassToastView` anchored below the safe area top.
    func glassToast(
        message: String,
        actionLabel: String? = nil,
        onAction: (() -> Void)? = nil,
        isVisible: Binding<Bool>,
        timeout: Double = 5.0
    ) -> some View {
        overlay(alignment: .top) {
            GlassToastView(
                message: message,
                actionLabel: actionLabel,
                onAction: onAction,
                isVisible: isVisible,
                timeout: timeout
            )
            .padding(.top, 8)
        }
    }
}
