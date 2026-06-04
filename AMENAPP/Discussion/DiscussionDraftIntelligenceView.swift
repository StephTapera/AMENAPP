// DiscussionDraftIntelligenceView.swift — AMEN App
import SwiftUI
import FirebaseRemoteConfig

@MainActor
final class DraftIntelligenceService {
    static let shared = DraftIntelligenceService()
    private init() {}

    private var isEnabled: Bool {
        RemoteConfig.remoteConfig().configValue(forKey: "draft_intelligence_enabled").boolValue
    }

    struct DraftInsight: Sendable {
        let tone: String
        let encouragement: String
    }

    func analyzeDraft(_ body: String) -> DraftInsight? {
        guard isEnabled, body.count >= 30 else { return nil }
        let tone = body.contains("?") ? "Curious" : body.contains("!") ? "Passionate" : "Reflective"
        return DraftInsight(tone: tone, encouragement: "Your perspective adds value to this discussion.")
    }
}

struct DraftInsightSheet: View {
    let insight: DraftIntelligenceService.DraftInsight
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.white.opacity(0.2))
                .frame(width: 36, height: 4)
                .padding(.top, 8)

            HStack(spacing: 8) {
                Image(systemName: "sparkle")
                    .foregroundStyle(Color(hex: "#C9A84C"))
                Text("Draft Insight")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
            }
            .padding(.horizontal, 20)

            VStack(alignment: .leading, spacing: 8) {
                Label("Tone: \(insight.tone)", systemImage: "waveform")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.white.opacity(0.75))
                Text(insight.encouragement)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)

            Button("Continue Writing") { onDismiss() }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(hex: "#C9A84C"))
                .padding(.bottom, 20)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Color(hex: "#111118"))
        .presentationDetents([.height(220)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(20)
    }
}

struct ReflectionFirstSheet: View {
    let onPost: () -> Void
    let onReflect: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.white.opacity(0.2))
                .frame(width: 36, height: 4)
                .padding(.top, 8)

            Image(systemName: "moon.stars")
                .font(.system(size: 32, weight: .ultraLight))
                .foregroundStyle(Color(hex: "#C9A84C"))

            Text("Take a moment to reflect?")
                .font(.custom("Georgia", size: 18))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text("This discussion is moving quickly. Would you like to pause before posting?")
                .font(.system(size: 14))
                .foregroundStyle(Color.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            HStack(spacing: 12) {
                Button("Post Now") { onPost() }
                    .font(.system(size: 15))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.white.opacity(0.08)))

                Button("Take a Moment") { onReflect() }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hex: "#C9A84C"))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color(hex: "#C9A84C").opacity(0.12)))
            }
            .padding(.bottom, 20)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Color(hex: "#0A0A0F"))
        .presentationDetents([.height(280)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(20)
    }
}
