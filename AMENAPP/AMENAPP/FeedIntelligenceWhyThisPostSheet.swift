// FeedIntelligenceWhyThisPostSheet.swift
import SwiftUI

struct FeedIntelligenceWhyThisPostSheet: View {
    let postId: String
    @Environment(\.dismiss) private var dismiss
    @State private var explanation: WhyThisPostResponse? = nil
    @State private var isLoading = true
    @State private var actionApplied: PostRecommendationAction? = nil
    @State private var isApplyingAction = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    loadingView
                } else if let explanation {
                    contentView(explanation)
                } else {
                    fallbackView
                }
            }
            .navigationTitle("Why this post?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task { await loadExplanation() }
        .onAppear { FeedDirectionAnalytics.whyThisPostOpened(postId: postId) }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView().tint(.secondary)
            Text("Loading explanation…").font(.subheadline).foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var fallbackView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "questionmark.circle").font(.systemScaled(36)).foregroundStyle(.secondary)
            Text("Amen is still learning your preferences.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Spacer()
        }
        .padding(24)
    }

    private func contentView(_ ex: WhyThisPostResponse) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                // Main reasons
                VStack(alignment: .leading, spacing: 8) {
                    Text(ex.title).font(.title3.bold())
                    ForEach(ex.reasons, id: \.self) { reason in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "circle.fill")
                                .font(.systemScaled(5))
                                .foregroundStyle(.secondary)
                                .padding(.top, 6)
                            Text(reason).font(.subheadline).foregroundStyle(.primary)
                        }
                    }
                }
                // Preference signals
                if !ex.preferenceSignals.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your preferences").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(ex.preferenceSignals, id: \.self) { signal in
                            HStack(spacing: 6) {
                                Image(systemName: "slider.horizontal.3").font(.caption).foregroundStyle(.secondary)
                                Text(signal).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                // Safety notes
                if !ex.safetyNotes.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(ex.safetyNotes, id: \.self) { note in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "info.circle").font(.caption).foregroundStyle(.secondary)
                                Text(note).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                // Actions
                if ex.canAdjust { adjustmentButtons }
            }
            .padding(20)
        }
    }

    private var adjustmentButtons: some View {
        VStack(spacing: 8) {
            Text("Adjust this").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                adjustButton("More like this", icon: "plus.circle", action: .moreLikeThis)
                adjustButton("Less like this", icon: "minus.circle", action: .lessLikeThis)
                adjustButton("Hide topic", icon: "eye.slash", action: .hideTopic)
                adjustButton("Reset related", icon: "arrow.counterclockwise", action: .resetRelated)
            }
        }
    }

    private func adjustButton(_ label: String, icon: String, action: PostRecommendationAction) -> some View {
        let applied = actionApplied == action
        return Button {
            guard !isApplyingAction else { return }
            isApplyingAction = true
            actionApplied = action
            FeedDirectionAnalytics.adjustmentTapped(action: action.rawValue, postId: postId)
            Task {
                try? await AmenFeedDirectionService.shared.adjustPostRecommendationSignal(postId: postId, action: action)
                isApplyingAction = false
            }
        } label: {
            Label(label, systemImage: applied ? "checkmark" : icon)
                .font(.systemScaled(13, weight: .medium))
                .foregroundStyle(applied ? .green : .primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isApplyingAction && actionApplied != action)
    }

    private func loadExplanation() async {
        isLoading = true
        explanation = try? await AmenFeedDirectionService.shared.explainWhyThisPost(postId: postId)
        isLoading = false
    }
}
