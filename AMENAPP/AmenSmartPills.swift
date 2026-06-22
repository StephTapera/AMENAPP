import SwiftUI

struct AmenSmartPill: View {
    let title: String
    let systemImage: String?
    let variant: AmenLiquidGlassVariant
    let accessibilityHint: String?
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPressed = false

    init(
        title: String,
        systemImage: String? = nil,
        variant: AmenLiquidGlassVariant = .regular,
        accessibilityHint: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.variant = variant
        self.accessibilityHint = accessibilityHint
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            AmenLiquidGlassSurface(
                variant: variant,
                cornerRadius: 16,
                isInteractive: true,
                isPressed: isPressed,
                allowsTint: false,
                contentComplexity: .low,
                localizedDimming: variant == .clear
            ) {
                HStack(spacing: 6) {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .font(.caption.weight(.semibold))
                    }
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isPressed else { return }
                    withAnimation(reduceMotion ? .easeOut(duration: 0.08) : .spring(response: 0.18, dampingFraction: 0.88)) {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    withAnimation(reduceMotion ? .easeOut(duration: 0.08) : .spring(response: 0.22, dampingFraction: 0.88)) {
                        isPressed = false
                    }
                }
        )
        .accessibilityLabel(title)
        .accessibilityHint(accessibilityHint ?? "")
    }
}

struct AmenTranslationPill: View {
    let isShowingOriginal: Bool
    let action: () -> Void

    var body: some View {
        AmenSmartPill(
            title: isShowingOriginal ? "Show Translation" : "Translate",
            systemImage: "globe",
            variant: .regular,
            accessibilityHint: isShowingOriginal ? "Shows translated text" : "Translates this text"
        ) {
            action()
        }
    }
}

struct AmenAIActionPill: View {
    let title: String
    let action: () -> Void

    var body: some View {
        AmenSmartPill(
            title: title,
            systemImage: "sparkles",
            variant: .regular,
            accessibilityHint: "Runs an optional AI-assisted action"
        ) {
            action()
        }
    }
}

struct AmenSafetyStatusPill: View {
    let title: String

    var body: some View {
        AmenSmartPill(
            title: title,
            systemImage: "checkmark.shield",
            variant: .regular,
            accessibilityHint: "Safety and moderation status"
        ) {}
        .allowsHitTesting(false)
    }
}
