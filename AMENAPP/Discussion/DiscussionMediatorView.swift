// DiscussionMediatorView.swift — AMEN App
import SwiftUI
import FirebaseFunctions

struct MediationResult: Sendable {
    var areasOfAgreement: [String] = []
    var differentPerspectives: [String] = []
    var questionsWorthExploring: [String] = []
    var potentialMisunderstandings: [String] = []
    var suggestedClarifications: [String] = []
}

@MainActor
final class DiscussionMediatorService {
    static let shared = DiscussionMediatorService()
    private init() {}
    private let functions = Functions.functions()

    func mediate(threadId: String) async -> MediationResult {
        let callable = functions.httpsCallable("mediateDiscussion")
        guard let result = try? await callable.call(["threadId": threadId]),
              let data = result.data as? [String: Any] else {
            return MediationResult(
                areasOfAgreement: ["Both sides share a commitment to truth"],
                questionsWorthExploring: ["What common ground can we find?"]
            )
        }
        return MediationResult(
            areasOfAgreement:           data["areasOfAgreement"]           as? [String] ?? [],
            differentPerspectives:      data["differentPerspectives"]      as? [String] ?? [],
            questionsWorthExploring:    data["questionsWorthExploring"]    as? [String] ?? [],
            potentialMisunderstandings: data["potentialMisunderstandings"] as? [String] ?? [],
            suggestedClarifications:    data["suggestedClarifications"]    as? [String] ?? []
        )
    }
}

struct DiscussionMediatorView: View {
    let threadId: String
    @State private var result: MediationResult?
    @State private var isLoading = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#0A0A0F").ignoresSafeArea()
                if isLoading {
                    VStack(spacing: 14) {
                        ProgressView().tint(Color(hex: "#C9A84C"))
                        Text("Finding common ground…")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.white.opacity(0.5))
                    }
                } else if let r = result {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 20) {
                            header
                            mediationSection(icon: "hands.sparkles", title: "Areas of Agreement", color: .green, items: r.areasOfAgreement)
                            mediationSection(icon: "arrow.left.arrow.right", title: "Different Perspectives", color: Color(hex: "#C9A84C"), items: r.differentPerspectives)
                            mediationSection(icon: "questionmark.circle", title: "Questions Worth Exploring", color: .blue, items: r.questionsWorthExploring)
                            mediationSection(icon: "exclamationmark.triangle", title: "Potential Misunderstandings", color: .orange, items: r.potentialMisunderstandings)
                            mediationSection(icon: "lightbulb", title: "Suggested Clarifications", color: .purple, items: r.suggestedClarifications)
                        }
                        .padding(20)
                    }
                }
            }
            .navigationTitle("Neutral Facilitator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color(hex: "#C9A84C"))
                }
            }
        }
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Finding Common Ground")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color.white)
            Text("This is a neutral summary to help the conversation move forward productively.")
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.55))
        }
    }

    private func mediationSection(icon: String, title: String, color: Color, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(color)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)
            }
            if items.isEmpty {
                Text("None identified")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.35))
            } else {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Circle().fill(color.opacity(0.5)).frame(width: 5, height: 5).padding(.top, 5)
                        Text(item)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.white.opacity(0.8))
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.07), lineWidth: 1))
        )
    }

    private func load() async {
        isLoading = true
        result = await DiscussionMediatorService.shared.mediate(threadId: threadId)
        isLoading = false
    }
}
