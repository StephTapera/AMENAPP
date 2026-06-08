import SwiftUI

struct BereanLiveTranslationBar: View {
    @Binding var selectedLanguage: BereanSupportedLanguage
    let sourceLanguage: BereanSupportedLanguage
    let availableLanguages: [BereanSupportedLanguage]
    let isLive: Bool
    let latencyMs: Double?
    /// Non-nil when the translation service has encountered a hard failure.
    /// The string is a short user-facing description (e.g. "Connection lost").
    /// When set, the status pill turns red and shows "Unavailable" so that
    /// deaf/HoH users always know captions are broken — not silently "Live".
    var translationError: String? = nil
    /// True while the transport is actively attempting to reconnect after a
    /// transient failure. Shows an amber "Reconnecting…" pill distinct from
    /// both the normal "Live" state and the hard-failure red pill.
    var isReconnecting: Bool = false
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
                        .font(.systemScaled(13, weight: .semibold))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .background(Circle().fill(Color(.systemBackground).opacity(0.92)))
                .overlay(Circle().strokeBorder(Color.black.opacity(0.10), lineWidth: 0.7))
                // Disable pause/resume during a hard failure — there is nothing to pause.
                .disabled(translationError != nil)
                .accessibilityLabel(isLive ? "Pause live captions" : "Resume live captions")

                Button(action: onEnd) {
                    Image(systemName: "xmark")
                        .font(.systemScaled(13, weight: .bold))
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
        // Animate across all three live/reconnecting/error state changes.
        .animation(reduceMotion ? nil : .amenEaseQuick, value: isLive)
        .animation(reduceMotion ? nil : .amenEaseQuick, value: isReconnecting)
        .animation(reduceMotion ? nil : .amenEaseQuick, value: translationError != nil)
    }

    // MARK: - Status pill

    private var statusPill: some View {
        HStack(spacing: 5) {
            statusDot
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
        .background(Capsule().fill(pillBackgroundColor))
        // VoiceOver: announce the full status so deaf/HoH users know if captions failed.
        .accessibilityLabel(accessibilityStatusLabel)
        // Urgent announce when the error state changes so VoiceOver interrupts
        // immediately — silent failure is the bug this fix addresses.
        .accessibilityAddTraits(translationError != nil ? .isStaticText : [])
    }

    private var statusDot: some View {
        Circle()
            .fill(dotColor)
            .frame(width: 7, height: 7)
            // Spinning indicator while reconnecting (suppressed for reduce-motion).
            .overlay {
                if isReconnecting && !reduceMotion {
                    Circle()
                        .trim(from: 0, to: 0.7)
                        .stroke(Color.orange.opacity(0.65), lineWidth: 1.5)
                        .rotationEffect(.degrees(isReconnecting ? 360 : 0))
                        .animation(
                            reduceMotion ? nil :
                                .linear(duration: 1.1).repeatForever(autoreverses: false),
                            value: isReconnecting
                        )
                }
            }
    }

    private var dotColor: Color {
        if translationError != nil { return .red }
        if isReconnecting { return .orange }
        return isLive ? .green : .secondary
    }

    private var pillBackgroundColor: Color {
        if translationError != nil { return Color.red.opacity(0.12) }
        if isReconnecting { return Color.orange.opacity(0.12) }
        return Color(.systemBackground)
    }

    private var statusText: String {
        if translationError != nil { return "Unavailable" }
        if isReconnecting { return "Reconnecting\u{2026}" }
        if let latencyMs, isLive {
            return "Live \(Int(latencyMs)) ms"
        }
        return isLive ? "Live" : "Paused"
    }

    /// Full spoken status for VoiceOver — more descriptive than the compact visual text.
    private var accessibilityStatusLabel: String {
        if let errorDetail = translationError {
            return "Translation unavailable: \(errorDetail). Live captions are not active."
        }
        if isReconnecting { return "Reconnecting to live captions. Please wait." }
        if let latencyMs, isLive { return "Live captions, \(Int(latencyMs)) milliseconds latency" }
        return isLive ? "Live captions active" : "Live captions paused"
    }
}

/// Applies the iOS 26 `.amenGlassEffect()` surface to the translation bar, with a
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
                .amenGlassEffect(in: barShape)
        }
    }
}
