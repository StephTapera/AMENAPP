// GlobalResilienceWhyAmISeeingThisSheet.swift
// AMEN — Global Resilience System
//
// SwiftUI sheet that explains why a specific post appeared in the user's feed.
// Calls the Firebase Functions callable "feedRanking-getRankingExplanation"
// with { userId, postId } and renders the structured response.
//
// Usage:
//   .sheet(isPresented: $showWhySheet) {
//       GlobalResilienceWhyAmISeeingThisSheet(postId: post.id)
//   }

import SwiftUI
import FirebaseFunctions
import FirebaseAuth

// MARK: - Response Model

private struct RankingExplanationResponse: Decodable {
    let reasons: [String]
    let topFactor: String
    let signals: RankingSignalsSummary
}

private struct RankingSignalsSummary: Decodable {
    let safetyScore: Double?
}

// MARK: - View Model

@MainActor
private final class WhyAmISeeingThisViewModel: ObservableObject {

    enum State {
        case idle
        case loading
        case loaded(RankingExplanationResponse)
        case error(String)
    }

    @Published var state: State = .idle

    private let functions = Functions.functions()

    func fetchExplanation(postId: String) async {
        guard let userId = Auth.auth().currentUser?.uid else {
            state = .error("Sign in to see this explanation.")
            return
        }

        state = .loading

        do {
            let callable = functions.httpsCallable("feedRanking-getRankingExplanation")
            let result = try await callable.call(["userId": userId, "postId": postId])

            guard let data = result.data as? [String: Any] else {
                state = .error("Unexpected response format.")
                return
            }

            let jsonData = try JSONSerialization.data(withJSONObject: data)
            let decoded = try JSONDecoder().decode(RankingExplanationResponse.self, from: jsonData)
            state = .loaded(decoded)
        } catch {
            state = .error(error.localizedDescription)
        }
    }
}

// MARK: - Sheet View

/// Presents a ranked explanation for why a specific post appears in the feed.
///
/// Parameters:
///   - postId: The Firestore document ID of the post being explained.
struct GlobalResilienceWhyAmISeeingThisSheet: View {

    let postId: String

    @StateObject private var viewModel = WhyAmISeeingThisViewModel()
    @Environment(\.dismiss) private var dismiss

    // VoiceOver: compose a single announcement string once the result loads.
    @State private var accessibilityAnnouncement: String = ""

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.state {
                case .idle:
                    // Kick off the fetch; show nothing while idle.
                    Color.clear
                        .onAppear {
                            Task {
                                await viewModel.fetchExplanation(postId: postId)
                            }
                        }

                case .loading:
                    loadingView

                case .loaded(let explanation):
                    explanationView(explanation)

                case .error(let message):
                    errorView(message)
                }
            }
            .navigationTitle("Why am I seeing this?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .amenGlassEffect()
        // VoiceOver: read the full explanation as a single announcement when it loads.
        .onChange(of: accessibilityAnnouncement) { _, newValue in
            guard !newValue.isEmpty else { return }
            UIAccessibility.post(notification: .announcement, argument: newValue)
        }
    }

    // MARK: Loading State

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(1.4)
            Text("Loading explanation…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading ranking explanation")
    }

    // MARK: Explanation State

    private func explanationView(_ explanation: RankingExplanationResponse) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // Header
                Text("You're seeing this because:")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                // Bulleted reasons list
                if explanation.reasons.isEmpty {
                    Text("No specific reasons available.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(explanation.reasons, id: \.self) { reason in
                            HStack(alignment: .top, spacing: 8) {
                                Text("\u{2022}")
                                    .accessibilityHidden(true)
                                Text(reason)
                                    .font(.subheadline)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }

                // Top factor highlight
                topFactorRow(explanation.topFactor)

                // Safety reviewed badge
                if let safetyScore = explanation.signals.safetyScore, safetyScore == 1.0 {
                    safetyBadge
                }

                Divider()

                // Feedback button
                Button {
                    dismiss()
                    NotificationCenter.default.post(
                        name: .whyAmISeeingThisOpenFeedback,
                        object: nil,
                        userInfo: ["postId": postId]
                    )
                } label: {
                    Label("Report a problem with this ranking", systemImage: "flag")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Report a problem with this ranking")
                .accessibilityHint("Dismisses this sheet and opens a feedback form.")
            }
            .padding()
        }
        .onAppear {
            // Build a single VoiceOver announcement from the full explanation.
            let reasonText = explanation.reasons.joined(separator: ". ")
            let safetyText: String
            if let score = explanation.signals.safetyScore, score == 1.0 {
                safetyText = " Safety reviewed."
            } else {
                safetyText = ""
            }
            accessibilityAnnouncement =
                "You're seeing this because: \(reasonText). Top factor: \(explanation.topFactor).\(safetyText)"
        }
    }

    // MARK: Top Factor Row

    private func topFactorRow(_ factor: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "star.fill")
                .foregroundStyle(.yellow)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Top factor")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(factor)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            Spacer()
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Top factor: \(factor)")
    }

    // MARK: Safety Badge

    private var safetyBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.shield.fill")
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            Text("Safety reviewed")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.green)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.green.opacity(0.12), in: Capsule())
        .accessibilityLabel("Safety reviewed")
        .accessibilityAddTraits(.isStaticText)
    }

    // MARK: Error State

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("Explanation unavailable")
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Try Again") {
                Task {
                    await viewModel.fetchExplanation(postId: postId)
                }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Explanation unavailable. \(message). Double tap to try again.")
    }
}

// MARK: - Notification Name

extension Notification.Name {
    /// Posted when the user taps "Report a problem with this ranking."
    /// userInfo["postId"] contains the relevant post identifier.
    static let whyAmISeeingThisOpenFeedback = Notification.Name("OpenFeedbackSheet")
}
