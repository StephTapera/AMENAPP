import SwiftUI

// MARK: - ExperienceAnalyticsView

/// Admin-only analytics screen showing aggregate stats for an experience.
/// No individual user data is displayed.
struct ExperienceAnalyticsView: View {

    let experience: ContextualExperience
    let userRole: OrgMemberRole

    @StateObject private var viewModel = ContextualExperienceViewModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    loadingSkeleton
                } else if let analytics = viewModel.analytics {
                    analyticsGrid(analytics)
                } else {
                    emptyState
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AmenTheme.Colors.backgroundPrimary)
            .navigationTitle("Analytics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        HapticManager.impact(style: .light)
                        dismiss()
                    }
                    .accessibilityLabel("Close analytics")
                }
            }
        }
        .task {
            await viewModel.loadAnalytics(experienceId: experience.id ?? "")
        }
    }

    // MARK: - Analytics grid

    private func analyticsGrid(_ analytics: ExperienceAnalytics) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(experience.title)
                    .font(AMENFont.bold(18))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 12
                ) {
                    statTile(
                        value: analytics.participantCount,
                        label: "Total Participants",
                        icon: "person.2.fill"
                    )
                    statTile(
                        value: analytics.activeToday,
                        label: "Active Today",
                        icon: "bolt.fill"
                    )
                    statTile(
                        value: analytics.prayerCount,
                        label: "Prayers",
                        icon: "hands.and.sparkles.fill"
                    )
                    statTile(
                        value: analytics.discussionCount,
                        label: "Discussions",
                        icon: "bubble.left.and.bubble.right.fill"
                    )
                    statTile(
                        value: analytics.memoryCount,
                        label: "Memories",
                        icon: "photo.fill"
                    )
                    statTile(
                        value: analytics.joinedLast7Days,
                        label: "Joined (7d)",
                        icon: "person.badge.plus.fill"
                    )
                }
                .padding(.horizontal, 16)

                privacyNote
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
            }
        }
    }

    // MARK: - Stat tile

    private func statTile(value: Int, label: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .imageScale(.medium)
                Spacer()
            }
            Text("\(value)")
                .font(AMENFont.bold(28))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .monospacedDigit()
            Text(label)
                .font(AMENFont.regular(12))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .lineLimit(2)
        }
        .padding(14)
        .background(tileBackground)
        .overlay(tileStroke)
        .shadow(color: .black.opacity(0.07), radius: 6, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    // MARK: - Tile backgrounds

    @ViewBuilder
    private var tileBackground: some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AmenTheme.Colors.surfaceCard)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.3))
            }
        }
    }

    private var tileStroke: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(Color.white.opacity(0.4), lineWidth: 0.5)
    }

    // MARK: - Privacy note

    private var privacyNote: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield.fill")
                .imageScale(.small)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
            Text("Aggregate stats only. No individual user data is displayed.")
                .font(AMENFont.regular(12))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AmenTheme.Colors.surfaceChip)
        )
        .accessibilityLabel("Privacy note: aggregate stats only, no individual user data displayed")
    }

    // MARK: - Loading skeleton

    private var loadingSkeleton: some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            spacing: 12
        ) {
            ForEach(0..<6, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .frame(height: 110)
            }
        }
        .padding(16)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 40))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
            Text("No Analytics Yet")
                .font(AMENFont.bold(16))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
            Text("Analytics become available once participants join.")
                .font(AMENFont.regular(13))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }
}
