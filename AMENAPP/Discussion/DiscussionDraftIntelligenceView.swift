// DiscussionDraftIntelligenceView.swift — AMEN App
import SwiftUI
import FirebaseFunctions

// MARK: - Service

@MainActor
final class DraftIntelligenceService {
    static let shared = DraftIntelligenceService()
    private init() {}
    private let functions = Functions.functions()

    struct DraftAnalysis: Sendable {
        let hasConcern: Bool
        let observation: String
        let severity: String   // "low" | "medium"
    }

    func analyzeDraft(threadId: String, draftBody: String) async -> DraftAnalysis {
        guard AMENFeatureFlags.shared.draftIntelligenceEnabled else {
            return DraftAnalysis(hasConcern: false, observation: "", severity: "low")
        }
        let callable = functions.httpsCallable("analyzeDraft")
        guard let result = try? await callable.call(["threadId": threadId, "draftBody": draftBody]),
              let data = result.data as? [String: Any],
              let hasConcern = data["hasConcern"] as? Bool, hasConcern else {
            return DraftAnalysis(hasConcern: false, observation: "", severity: "low")
        }
        return DraftAnalysis(
            hasConcern: true,
            observation: data["observation"] as? String ?? "",
            severity: data["severity"] as? String ?? "medium"
        )
    }
}

// MARK: - Draft Insight Sheet

struct DraftInsightSheet: View {
    let analysis: DraftIntelligenceService.DraftAnalysis
    let onRevise: () -> Void
    let onPostAnyway: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Capsule()
                .fill(Color.white.opacity(0.18))
                .frame(width: 36, height: 4)
                .padding(.top, 12)

            VStack(spacing: 8) {
                Image(systemName: "lightbulb.fill")
                    .font(.systemScaled(28))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
                Text("A reflection before you post")
                    .font(.systemScaled(17, weight: .semibold))
                    .foregroundStyle(Color.white)
            }

            Text(analysis.observation)
                .font(.systemScaled(15))
                .foregroundStyle(Color.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            VStack(spacing: 10) {
                Button(action: onRevise) {
                    Text("Revise my comment")
                        .font(.systemScaled(16, weight: .semibold))
                        .foregroundStyle(Color(.systemBackground))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .accessibilityLabel("Revise my comment")
                Button(action: onPostAnyway) {
                    Text("Post anyway")
                        .font(.systemScaled(15))
                        .foregroundStyle(Color.white.opacity(0.45))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .accessibilityLabel("Post anyway without changes")
            }
            .padding(.horizontal, 24)
            Spacer()
        }
        .presentationDetents([.height(320)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(24)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }
}

// MARK: - Reflection First Sheet

struct ReflectionFirstSheet: View {
    let onComment: () -> Void
    let onReflect: () -> Void
    let onPray: () -> Void
    let onSaveToNotes: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Capsule()
                .fill(Color.white.opacity(0.18))
                .frame(width: 36, height: 4)
                .padding(.top, 12)

            Text("What would you like to do?")
                .font(.systemScaled(17, weight: .semibold))
                .foregroundStyle(Color.white)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                reflectionCard(icon: "moon.stars",    label: "Reflect Privately", action: onReflect)
                reflectionCard(icon: "hands.sparkles", label: "Pray",             action: onPray)
                reflectionCard(icon: "book.closed",    label: "Save to Notes",    action: onSaveToNotes)
                reflectionCard(icon: "bubble.left",    label: "Comment",          action: onComment)
            }
            .padding(.horizontal, 20)
            Spacer()
        }
        .presentationDetents([.height(300)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(24)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }

    private func reflectionCard(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: { action(); dismiss() }) {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.systemScaled(22))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
                Text(label)
                    .font(.systemScaled(13, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
