// CreatorStudioView.swift
// AMENAPP — Creator Studio / Wave 5
//
// ANTI-VANITY GUARDRAIL: Do not add growth charts, follower streaks, "post to grow" nudges,
// or raw number headlines. Numbers must appear as stewardship context, not achievement metrics.
// This is by design and matches the AMEN Constitution.

import SwiftUI

struct CreatorStudioView: View {

    let creatorId: String

    @StateObject private var viewModel = CreatorStudioViewModel()

    // Profile perspective switcher — lets the creator preview their own page
    // from three visitor contexts without exposing silent viewer identities.
    enum ProfilePerspective: String, CaseIterable, Identifiable {
        case publicVisitor    = "Public Visitor"
        case follower         = "Follower"
        case communityMember  = "Community Member"
        var id: String { rawValue }
    }

    @State private var perspective: ProfilePerspective = .publicVisitor

    // MARK: - Body

    var body: some View {
        if !AMENFeatureFlags.shared.creatorStudioDashboardEnabled {
            ContentUnavailableView(
                "Studio is coming soon",
                systemImage: "pencil.and.outline",
                description: Text("Your creator dashboard is being prepared.")
            )
        } else {
            studioContent
                .task { await viewModel.load(creatorId: creatorId) }
        }
    }

    // MARK: - Studio Content

    private var studioContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                perspectivePicker
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 20)

                Divider()
                    .padding(.horizontal, 20)

                stewardshipSection
                    .padding(.top, 20)

                Divider()
                    .padding(.horizontal, 20)
                    .padding(.top, 28)

                updateComposerSection
                    .padding(.top, 20)

                Divider()
                    .padding(.horizontal, 20)
                    .padding(.top, 28)

                bereanAssistSection
                    .padding(.top, 20)

                Spacer(minLength: 60)
            }
        }
        .background(Color(.systemBackground))
        .overlay {
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemBackground).opacity(0.5))
            }
        }
    }

    // MARK: - Perspective Picker

    private var perspectivePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("View as:")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("View as", selection: $perspective) {
                ForEach(ProfilePerspective.allCases) { p in
                    Text(p.rawValue).tag(p)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - Stewardship Section

    private var stewardshipSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(
                title: "Your Stewardship",
                subtitle: "How your content is serving people",
                icon: "heart.text.square.fill"
            )

            if viewModel.insights.isEmpty && !viewModel.isLoading {
                Text("Stewardship insights will appear here once your content is reviewed.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
            } else {
                VStack(spacing: 10) {
                    ForEach(viewModel.insights) { insight in
                        CreatorStudioInsightCard(insight: insight)
                    }

                    // Profile visits shown only as a narrative sentence — never as a headline metric.
                    if viewModel.profileViews > 0 {
                        profileVisitsNarrativeRow
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private var profileVisitsNarrativeRow: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(0.10))
                    .frame(width: 36, height: 36)
                Image(systemName: "eye")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 4) {
                // Numbers framed in narrative context — not a headline
                Text("\(viewModel.profileViews) people visited your page.")
                    .font(.body)
                    .foregroundStyle(.primary)
                Text("This month")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.07), radius: 6, x: 0, y: 2)
        )
    }

    // MARK: - Update Composer Section

    private var updateComposerSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(
                title: "Share an Update",
                subtitle: "Announcements, episodes, events, and more",
                icon: "megaphone.fill"
            )

            CreatorUpdateComposerView()
                .padding(.horizontal, 20)
        }
    }

    // MARK: - Berean Assist Section

    private var bereanAssistSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(
                title: "Berean Assist",
                subtitle: "Berean proposes; you decide",
                icon: "sparkles"
            )

            CreatorBereanAssistView()
                .padding(.horizontal, 20)
        }
    }

    // MARK: - Section Header

    @ViewBuilder
    private func sectionHeader(title: String, subtitle: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
    }
}
