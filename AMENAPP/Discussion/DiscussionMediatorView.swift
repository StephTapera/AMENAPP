// DiscussionMediatorView.swift — AMEN App
import SwiftUI
import FirebaseRemoteConfig

struct MediationResult: Sendable {
    let needsMediation: Bool
    let suggestions: [String]
}

@MainActor
final class DiscussionMediatorService {
    static let shared = DiscussionMediatorService()
    private init() {}

    private var isEnabled: Bool {
        RemoteConfig.remoteConfig().configValue(forKey: "discussion_mediator_enabled").boolValue
    }

    func checkTension(commentCount: Int, duplicateFlags: Int) -> MediationResult {
        guard isEnabled else { return MediationResult(needsMediation: false, suggestions: []) }
        let needsMediation = duplicateFlags > 3 || commentCount > 50
        let suggestions: [String] = needsMediation ? [
            "Consider focusing on areas of agreement.",
            "Remember to engage with grace and truth.",
            "Ask clarifying questions before responding."
        ] : []
        return MediationResult(needsMediation: needsMediation, suggestions: suggestions)
    }
}

struct DiscussionMediatorView: View {
    let result: MediationResult
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.white.opacity(0.2))
                .frame(width: 36, height: 4)
                .padding(.top, 8)

            Image(systemName: "scale.3d")
                .font(.system(size: 32, weight: .ultraLight))
                .foregroundStyle(Color(hex: "#C9A84C"))

            Text("Discussion Climate")
                .font(.custom("Georgia", size: 18))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(result.suggestions, id: \.self) { suggestion in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "leaf")
                            .font(.system(size: 11))
                            .foregroundStyle(Color(hex: "#C9A84C").opacity(0.7))
                            .padding(.top, 2)
                        Text(suggestion)
                            .font(.system(size: 14))
                            .foregroundStyle(Color.white.opacity(0.75))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, 24)

            Button("Got it") { onDismiss() }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(hex: "#C9A84C"))
                .padding(.bottom, 20)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Color(hex: "#0A0A0F"))
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(20)
    }
}
