import SwiftUI

struct LiquidGlassTranslationCapsule: View {
    let sourceLanguage: BereanSupportedLanguage
    @Binding var selectedLanguage: BereanSupportedLanguage
    let availableLanguages: [BereanSupportedLanguage]
    var scrollOffset: CGFloat = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var behavior: LiquidGlassScrollBehavior {
        LiquidGlassScrollBehavior(offset: scrollOffset, velocityHint: 0)
    }

    var body: some View {
        Menu {
            ForEach(availableLanguages) { language in
                Button {
                    selectedLanguage = language
                } label: {
                    Label(language.displayName, systemImage: language == selectedLanguage ? "checkmark" : "globe")
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "captions.bubble")
                    .font(.system(size: 14, weight: .semibold))
                Text(selectedLanguage.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background {
                if reduceTransparency {
                    Capsule().fill(Color(.systemBackground))
                } else {
                    Capsule().fill(.ultraThinMaterial)
                }
            }
            .overlay {
                Capsule().strokeBorder(Color.black.opacity(0.10), lineWidth: 0.7)
            }
            .shadow(color: .black.opacity(behavior.shadowOpacity), radius: 16, x: 0, y: 8)
        }
        .accessibilityLabel("Caption language")
        .accessibilityValue(selectedLanguage.displayName)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: selectedLanguage.rawValue)
    }
}
