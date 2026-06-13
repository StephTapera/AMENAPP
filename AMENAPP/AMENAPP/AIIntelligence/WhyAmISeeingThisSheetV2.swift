// WhyAmISeeingThisSheetV2.swift
// AMEN — Feed Transparency Sheet (V2)
//
// Replaces / extends GlobalResilienceWhyAmISeeingThisSheet with warm, jargon-free
// explanations powered by FeedExplanationService.
//
// Flag gate: AMENFeatureFlags.shared.feedWhyAmISeeingThis
// If flag is OFF, the caller should fall back to GlobalResilienceWhyAmISeeingThisSheet.
//
// Usage:
//   .sheet(isPresented: $showWhySheet) {
//       WhyAmISeeingThisSheetV2(feedItemId: item.id)
//   }

import SwiftUI
import FirebaseFunctions
import FirebaseAuth

// MARK: - View Model

@MainActor
private final class WhyAmISeeingThisV2ViewModel: ObservableObject {

    enum State {
        case loading
        case loaded(FeedExplanation)
        case unavailable   // fail-closed — no explanation available
    }

    @Published private(set) var state: State = .loading

    private let service = FeedExplanationService.shared
    private let functions = Functions.functions()

    func load(feedItemId: String) async {
        state = .loading

        if let explanation = await service.explanation(for: feedItemId) {
            state = .loaded(explanation)
        } else {
            state = .unavailable
        }
    }

    func hideSimilar(feedItemId: String) {
        // Fire-and-forget hide signal — no confirmation needed.
        Task {
            guard let uid = Auth.auth().currentUser?.uid else { return }
            let callable = functions.httpsCallable("hideSimilarFeedContent")
            _ = try? await callable.call(["feedItemId": feedItemId, "uid": uid])
        }
    }
}

// MARK: - Sheet View

struct WhyAmISeeingThisSheetV2: View {

    let feedItemId: String

    @StateObject private var viewModel = WhyAmISeeingThisV2ViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.state {
                case .loading:
                    loadingView

                case .loaded(let explanation):
                    explanationView(explanation)

                case .unavailable:
                    unavailableView
                }
            }
            .navigationTitle("Why am I seeing this?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityLabel("Done")
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .amenGlassEffect()
        .task {
            await viewModel.load(feedItemId: feedItemId)
        }
    }

    // MARK: Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(.circular)
            Text("One moment…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading explanation")
    }

    // MARK: Explanation

    private func explanationView(_ explanation: FeedExplanation) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // Header
                Text("You're seeing this because:")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                // Up to 3 warm-language reason rows
                let displayReasons = Array(explanation.reasons.prefix(3))
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(displayReasons, id: \.self) { reason in
                        warmReasonRow(for: reason)
                    }
                }

                Divider()

                // Human-readable summary generated server-side
                if !explanation.humanReadable.isEmpty {
                    Text(explanation.humanReadable)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Hide similar content — one-tap, no confirmation
                Button {
                    viewModel.hideSimilar(feedItemId: feedItemId)
                    dismiss()
                } label: {
                    Label("Hide similar content", systemImage: "hand.thumbsdown")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Hide similar content")
                .accessibilityHint("Removes content like this from your feed")
            }
            .padding()
        }
    }

    // MARK: Reason Row

    private func warmReasonRow(for code: FeedReasonCode) -> some View {
        HStack(spacing: 12) {
            Image(systemName: iconName(for: code))
                .foregroundStyle(.tint)
                .frame(width: 22)
                .accessibilityHidden(true)
            Text(FeedExplanationService.shared.humanReadable(for: [code], context: [:]))
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func iconName(for code: FeedReasonCode) -> String {
        switch code {
        case .followedAuthor:       return "person.fill"
        case .sharedInterests:      return "sparkles"
        case .prayerContext:        return "hands.sparkles"
        case .friendEngaged:        return "heart.fill"
        case .trendingInCommunity:  return "flame"
        case .liturgicalSeason:     return "calendar"
        case .bookmarkedTopic:      return "bookmark.fill"
        case .groupActivity:        return "person.3.fill"
        }
    }

    // MARK: Unavailable

    private var unavailableView: some View {
        VStack(spacing: 16) {
            Image(systemName: "questionmark.circle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Explanation unavailable")
                .font(.headline)
            Text("We couldn't find an explanation right now.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Explanation unavailable")
    }
}

// MARK: - Flag-Aware Convenience Modifier

extension View {
    /// Present the V2 "Why am I seeing this?" sheet when the flag is enabled,
    /// or fall back to GlobalResilienceWhyAmISeeingThisSheet.
    func whyAmISeeingThisSheet(
        isPresented: Binding<Bool>,
        feedItemId: String,
        legacyPostId: String? = nil
    ) -> some View {
        self.sheet(isPresented: isPresented) {
            if AMENFeatureFlags.shared.feedWhyAmISeeingThis {
                WhyAmISeeingThisSheetV2(feedItemId: feedItemId)
            } else {
                GlobalResilienceWhyAmISeeingThisSheet(postId: legacyPostId ?? feedItemId)
            }
        }
    }
}
