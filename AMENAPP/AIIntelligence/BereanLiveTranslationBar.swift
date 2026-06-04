import SwiftUI

struct BereanLiveTranslationBar: View {
    @Binding var selectedLanguage: BereanSupportedLanguage
    let sourceLanguage: BereanSupportedLanguage
    let availableLanguages: [BereanSupportedLanguage]
    let isLive: Bool
    let latencyMs: Double?
    var onPauseResume: () -> Void
    var onEnd: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: 10) {
            LiquidGlassTranslationCapsule(
                sourceLanguage: sourceLanguage,
                selectedLanguage: $selectedLanguage,
                availableLanguages: availableLanguages
            )

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                statusPill

                Button(action: onPauseResume) {
                    Image(systemName: isLive ? "pause.fill" : "play.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .background(Circle().fill(Color(.systemBackground).opacity(0.92)))
                .overlay(Circle().strokeBorder(Color.black.opacity(0.10), lineWidth: 0.7))
                .accessibilityLabel(isLive ? "Pause live captions" : "Resume live captions")

                Button(action: onEnd) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .background(Circle().fill(Color.black))
                .accessibilityLabel("End live translation")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        // barSurface applies the iOS 26 glass effect or the solid accessibility
        // fallback. Glass is last in the modifier chain as required.
        .modifier(TranslationBarSurface(reduceTransparency: reduceTransparency))
        // Use amenEaseQuick for live/paused state swaps (selection-level change).
        .animation(reduceMotion ? nil : .amenEaseQuick, value: isLive)
    }

    private var statusPill: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(isLive ? Color.green : Color.secondary)
                .frame(width: 7, height: 7)
            Text(statusText)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        // Keep foregroundStyle as .primary so it adapts to light/dark while
        // remaining fully opaque — legibility on the glass surface requires this.
        .foregroundStyle(.primary)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        // Opaque pill background: ensures status text is readable over any content
        // visible through the outer glass bar. Do NOT apply a second glass layer here.
        .background(Capsule().fill(Color(.systemBackground)))
        .accessibilityLabel(statusText)
    }

    private var statusText: String {
        if let latencyMs, isLive {
            return "Live \(Int(latencyMs)) ms"
        }
        return isLive ? "Live" : "Paused"
    }
}

/// Applies the iOS 26 `.glassEffect()` surface to the translation bar, with a
/// solid `Color(.systemBackground)` fallback when Reduce Transparency is on.
/// Kept private to this file — do not duplicate glass logic from
/// LiquidGlassTranslationCapsule.
private struct TranslationBarSurface: ViewModifier {
    let reduceTransparency: Bool

    private let barShape = RoundedRectangle(cornerRadius: 8, style: .continuous)

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background {
                    barShape
                        .fill(Color(.systemBackground))
                }
                .clipShape(barShape)
                .shadow(color: .black.opacity(0.08), radius: 14, x: 0, y: 6)
        } else {
            content
                // Shadow before glass so it sits under the specular rim, not on top.
                .shadow(color: .black.opacity(0.08), radius: 14, x: 0, y: 6)
                // iOS 26 Liquid Glass — must be last modifier.
                .glassEffect(GlassEffectStyle.regular, in: barShape)
        }
    }
}
