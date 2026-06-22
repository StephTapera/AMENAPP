import SwiftUI

struct SilenceInsightCard: View {
    let signal: SilenceSignal
    @StateObject private var service = SilenceIntelligenceService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: targetIcon)
                .font(.title3)
                .foregroundStyle(Color.secondary)
                .frame(width: 36, height: 36)
                .background(Color.secondary.opacity(0.07), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(gentlePrompt)
                    .font(.subheadline)
                    .foregroundStyle(Color.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(signal.targetType.displayName)
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
            }

            Spacer()

            Button(action: { Task { await service.resolveSilenceSignal(signal) } }) {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
                    .padding(6)
                    .background(Color.secondary.opacity(0.1), in: Circle())
            }
            .accessibilityLabel("Dismiss this quiet pattern signal")
        }
        .padding(14)
        .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(gentlePrompt). \(signal.targetType.displayName). Double-tap to dismiss.")
    }

    private var gentlePrompt: String {
        let count = signal.avoidanceCount
        switch signal.targetType {
        case .prayerThread:
            return "You've passed by this prayer \(count) times. Want help approaching it?"
        case .discernmentItem:
            return "This discernment item has been waiting. No pressure — just here when you're ready."
        case .savedVerse:
            return "You saved this verse but haven't revisited it. Might be worth a moment."
        case .avoidedConversation:
            return "You've skipped this conversation a few times. Would prayer help first?"
        case .walkWithChristPath:
            return "Your walk path has been waiting. Even a few minutes counts."
        case .dismissedPrompt:
            return "This keeps coming back. It might be worth sitting with."
        }
    }

    private var targetIcon: String {
        switch signal.targetType {
        case .prayerThread: return "hands.sparkles"
        case .discernmentItem: return "scale.3d"
        case .savedVerse: return "bookmark"
        case .avoidedConversation: return "bubble.left.and.bubble.right"
        case .walkWithChristPath: return "figure.walk"
        case .dismissedPrompt: return "arrow.circlepath"
        }
    }
}

// MARK: - Gentle Return Prompt (inline nudge, not a full sheet)

struct GentleReturnPrompt: View {
    let targetType: SilenceTargetType
    let onReturn: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.uturn.backward.circle")
                .font(.subheadline)
                .foregroundStyle(Color.secondary)
            Text(promptText)
                .font(.subheadline)
                .foregroundStyle(Color.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("Return", action: onReturn)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.primary)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(0.05), radius: 10, y: 3)
        .accessibilityElement(children: .contain)
    }

    private var promptText: String {
        switch targetType {
        case .prayerThread: return "Want to revisit this prayer?"
        case .savedVerse: return "This verse is still here."
        default: return "Ready to return to this?"
        }
    }
}
