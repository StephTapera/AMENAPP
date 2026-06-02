// AmenFeedBoundaryCard.swift
// AMENAPP
// Shown in the feed when a post is suppressed by FeedControlService.
// Also contains WhyAmISeeingThisCard for algorithm transparency.

import SwiftUI

// MARK: - Feed Boundary Card

/// Shown in place of a suppressed post.
struct FeedBoundaryCard: View {
    let category: SafetyRiskCategory
    var onUnsuppress: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "eye.slash")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text("Content hidden")
                    .font(.subheadline.bold())
                Text("This post was filtered by your \(category.displayName) settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let onUnsuppress {
                Button("Show", action: onUnsuppress)
                    .font(.caption.bold())
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(12)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
}

// MARK: - Why Am I Seeing This

struct WhyAmISeeingThisCard: View {
    let contentId: String
    @State private var explanation: String?
    @State private var isLoading = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
            } else if let explanation {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Why you're seeing this", systemImage: "info.circle")
                        .font(.subheadline.bold())
                    Text(explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .task {
            guard AMENFeatureFlags.shared.algorithmTransparencyEnabled else { return }
            isLoading = true
            explanation = await AmenIntegrityLabelService.shared.explanationForContent(contentId)
            isLoading = false
        }
    }
}

// MARK: - Algorithm Control Centre

struct AlgorithmControlCenterView: View {
    @StateObject private var feedControl = AmenFeedControlService.shared
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        List {
            Section("Feed Mode") {
                ForEach(HeyFeedMode.allCases, id: \.self) { mode in
                    let isSelected = feedControl.state.activeMode == mode
                    Button {
                        Task {
                            try? await feedControl.applyMode(mode)
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mode.displayName)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                Text(mode.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
            }

            Section("Filtered Categories") {
                ForEach(SafetyRiskCategory.allCases, id: \.self) { category in
                    Toggle(category.displayName, isOn: Binding(
                        get: { feedControl.state.blockedCategories.contains(category) },
                        set: { _ in
                            Task { try? await feedControl.toggleBlockedCategory(category) }
                        }
                    ))
                }
            }

            if AMENFeatureFlags.shared.algorithmTransparencyEnabled {
                Section {
                    Button(role: .destructive) {
                        Task { try? await AmenSocialSafetyService.shared.resetRecommendationTraining() }
                    } label: {
                        Label("Reset Recommendation Training", systemImage: "arrow.counterclockwise")
                    }
                } footer: {
                    Text("This clears your personalization data and starts fresh.")
                        .font(.caption)
                }
            }
        }
        .navigationTitle("Feed Controls")
        .task { await feedControl.load() }
    }
}

// MARK: - Helpers

private extension SafetyRiskCategory {
    var displayName: String {
        switch self {
        case .mentalHealth: return "Mental Health"
        case .exploitation, .grooming: return "Exploitation & Grooming"
        case .harassment, .dogpile, .hate: return "Harassment & Safety"
        case .misinformation, .deepfake: return "Misinformation"
        case .addictiveUse: return "Addictive Content"
        default: return "Safety"
        }
    }
}

private extension HeyFeedMode {
    var subtitle: String {
        switch self {
        case .balanced: return "Default experience with community signals"
        case .friendsFirst: return "Prioritize people you follow"
        case .localCommunity: return "More local and community-oriented content"
        case .ideasLearning: return "Learning and idea-driven content first"
        case .quiet: return "Minimal distractions with calmer browsing"
        }
    }
}
