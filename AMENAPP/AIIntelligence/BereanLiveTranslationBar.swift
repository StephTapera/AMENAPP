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
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.black.opacity(0.10), lineWidth: 0.7)
        }
        .shadow(color: .black.opacity(0.08), radius: 14, x: 0, y: 6)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isLive)
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
        .foregroundStyle(.primary)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color(.systemBackground).opacity(0.88)))
        .accessibilityLabel(statusText)
    }

    private var statusText: String {
        if let latencyMs, isLive {
            return "Live \(Int(latencyMs)) ms"
        }
        return isLive ? "Live" : "Paused"
    }
}
