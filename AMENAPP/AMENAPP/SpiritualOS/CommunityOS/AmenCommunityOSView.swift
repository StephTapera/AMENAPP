// AmenCommunityOSView.swift — AMEN App / Spiritual OS
// Community OS surface — AI-driven pastoral dashboard for space leaders.
// Gated by `spiritualOS_community_os_enabled` AppStorage flag (default OFF).
// Presented as a sheet from AmenSpaceDetailView for the space creator only.

import SwiftUI

// MARK: - AmenCommunityOSView

struct AmenCommunityOSView: View {

    // MARK: Inputs
    var spaceId: String
    var spaceName: String

    // MARK: Feature flag
    @AppStorage("spiritualOS_community_os_enabled") private var isEnabled = false

    // MARK: State
    @StateObject private var viewModel: AmenCommunityOSViewModel
    @Environment(\.dismiss) private var dismiss

    // MARK: Init
    init(spaceId: String, spaceName: String) {
        self.spaceId = spaceId
        self.spaceName = spaceName
        _viewModel = StateObject(wrappedValue: AmenCommunityOSViewModel(spaceId: spaceId))
    }

    // MARK: Body
    var body: some View {
        GlassSheet(title: "Community Insights", tint: .amenPurple, onDismiss: { dismiss() }) {
            if !isEnabled {
                featureGateBody
            } else if viewModel.isLoading {
                loadingBody
            } else {
                dashboardBody
            }
        }
        .task { await viewModel.load() }
    }

    // MARK: - Feature-off state

    private var featureGateBody: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 48))
                .foregroundStyle(Color.amenPurple)
            Text("Community OS")
                .font(.title2.weight(.bold))
                .foregroundStyle(Color.amenBlack)
            Text("Berean-powered pastoral insights for your Space are coming soon.")
                .font(.subheadline)
                .foregroundStyle(Color.amenSlate)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.amenCream)
    }

    // MARK: - Loading state

    private var loadingBody: some View {
        VStack(spacing: 16) {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.amenSlate.opacity(0.2))
                    .frame(maxWidth: .infinity)
                    .frame(height: 72)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .accessibilityHidden(true)
    }

    // MARK: - Dashboard

    private var dashboardBody: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                healthScoreCard
                statsGrid
                if !viewModel.bereanInsights.isEmpty {
                    insightsSection
                }
                Spacer(minLength: 32)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .background(Color.amenCream)
    }

    // MARK: - Health Score Card

    private var healthScoreCard: some View {
        GlassCard(tint: .amenPurple, elevated: true) {
            HStack(spacing: 16) {
                // Score ring
                ZStack {
                    Circle()
                        .stroke(Color.amenPurple.opacity(0.15), lineWidth: 8)
                        .frame(width: 72, height: 72)
                    Circle()
                        .trim(from: 0, to: CGFloat(viewModel.healthScore) / 100.0)
                        .stroke(
                            scoreColor,
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        .frame(width: 72, height: 72)
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(response: 0.7, dampingFraction: 0.75), value: viewModel.healthScore)
                    Text("\(viewModel.healthScore)")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color.amenBlack)
                }
                .accessibilityLabel("Community health score: \(viewModel.healthScore) out of 100")

                VStack(alignment: .leading, spacing: 6) {
                    Text("Community Health")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.amenBlack)
                    Text(healthLabel)
                        .font(.caption)
                        .foregroundStyle(Color.amenSlate)

                    HStack(spacing: 4) {
                        Image(systemName: viewModel.healthTrend.icon)
                            .font(.caption.weight(.semibold))
                        Text(viewModel.healthTrend.rawValue.capitalized)
                            .font(.caption.weight(.medium))
                    }
                    .foregroundStyle(viewModel.healthTrend.color)
                }

                Spacer()
            }
            .padding(16)
        }
    }

    private var scoreColor: Color {
        switch viewModel.healthScore {
        case 70...: return .amenGold
        case 40..<70: return .amenBlue
        default: return .amenSlate
        }
    }

    private var healthLabel: String {
        switch viewModel.healthScore {
        case 80...: return "Your community is flourishing"
        case 60..<80: return "Active and engaged"
        case 40..<60: return "Growing steadily"
        default: return "Needs nurturing"
        }
    }

    // MARK: - Stats Grid

    private var statsGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            spacing: 12
        ) {
            statTile(
                value: viewModel.totalMembers,
                label: "Members",
                icon: "person.3.fill",
                tint: .amenBlue
            )
            statTile(
                value: viewModel.weeklyActiveMembers,
                label: "Active (7d)",
                icon: "chart.bar.fill",
                tint: .amenGold
            )
            statTile(
                value: viewModel.prayerRequestsThisWeek,
                label: "Prayers",
                icon: "hands.sparkles.fill",
                tint: .amenPurple
            )
            statTile(
                value: viewModel.postsThisWeek,
                label: "Posts (7d)",
                icon: "bubble.left.and.bubble.right.fill",
                tint: .amenBlue
            )
        }
    }

    @ViewBuilder
    private func statTile(value: Int, label: String, icon: String, tint: Color) -> some View {
        GlassCard(tint: tint) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(tint)
                Text("\(value)")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Color.amenBlack)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(Color.amenSlate)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    // MARK: - Berean Insights Section

    private var insightsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.amenPurple)
                Text("Berean Pastoral Insights")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.amenSlate)
                    .textCase(.uppercase)
                    .kerning(0.8)
            }
            .padding(.horizontal, 4)

            ForEach(viewModel.bereanInsights, id: \.self) { insight in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lightbulb.min.fill")
                        .font(.caption)
                        .foregroundStyle(Color.amenGold)
                        .padding(.top, 2)
                    Text(insight)
                        .font(.subheadline)
                        .foregroundStyle(Color.amenBlack)
                        .lineSpacing(2)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.amenGold.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.amenGold.opacity(0.2), lineWidth: 0.5)
                }
                .accessibilityLabel("Insight: \(insight)")
            }

            Text("Insights generated by Berean AI · Not pastoral advice")
                .font(.caption2)
                .foregroundStyle(Color.amenSlate.opacity(0.6))
                .padding(.horizontal, 4)
        }
    }
}

// MARK: - Preview

#Preview("Community OS — loaded") {
    AmenCommunityOSView(spaceId: "preview-space", spaceName: "Sunday Worship Team")
}
