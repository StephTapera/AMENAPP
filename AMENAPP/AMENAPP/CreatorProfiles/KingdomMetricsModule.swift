// KingdomMetricsModule.swift
// AMEN — Creator Profiles (ministry hubs) — Wave 3 UI
//
// Creator-facing dashboard of CreatorHubMetrics. Framed as KINGDOM IMPACT — discipleship,
// prayer, answered reports — NOT vanity counts (no followers, no likes, no reach). Two derived
// signals (retentionSignal / communityHealthSignal) render as calm gauges, not leaderboards.
//
// Loads via CreatorHubService.metrics(creatorId:). Skeleton-first; error + retry.
//
// Conventions: white bg / black text; translucent glass tiles on plain background (no
// glass-on-glass); AmenTheme.Colors.* tokens; Dynamic Type; VoiceOver labels; reduce-motion
// safe (gauges are static bars, no implicit animation).

import SwiftUI

struct KingdomMetricsModule: View {
    let creatorId: String

    @State private var metrics: CreatorHubMetrics?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if isLoading && metrics == nil {
                skeletonGrid
            } else if let errorMessage {
                errorState(errorMessage)
            } else if let metrics {
                impactGrid(metrics)
                signalsSection(metrics)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task { await load() }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Kingdom impact")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text("Lives touched, not numbers chased.")
                .font(.footnote)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
        }
    }

    // MARK: Impact grid

    private func impactGrid(_ m: CreatorHubMetrics) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                  spacing: 12) {
            tile("People discipled", value: m.peopleDiscipled, icon: "person.2")
            tile("Prayers received", value: m.prayersReceived, icon: "hands.and.sparkles")
            tile("Prayers prayed", value: m.prayersPrayed, icon: "heart")
            tile("Answered reports", value: m.answeredReports, icon: "sparkles")
            tile("Plans completed", value: m.plansCompleted, icon: "checkmark.circle")
            tile("Notes created", value: m.notesCreated, icon: "note.text")
            tile("Study sessions", value: m.studySessions, icon: "book")
            tile("Groups launched", value: m.groupsLaunched, icon: "person.3")
            tile("Resources downloaded", value: m.resourcesDownloaded, icon: "arrow.down.doc")
        }
    }

    private func tile(_ label: String, value: Int, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(AmenTheme.Colors.amenGoldText)
                .accessibilityHidden(true)
            Text("\(value)")
                .font(.title2.weight(.bold))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
            Text(label)
                .font(.caption)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .amenGlassCard(cornerRadius: 18)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    // MARK: Signals (gauges)

    private func signalsSection(_ m: CreatorHubMetrics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Health signals")
                .font(.headline)
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)

            gauge("Returning over time", value: m.retentionSignal)
            gauge("Community health", value: m.communityHealthSignal)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .amenGlassCard(cornerRadius: 18)
    }

    private func gauge(_ label: String, value: Double) -> some View {
        let clamped = min(max(value, 0), 1)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                Spacer()
                Text("\(Int((clamped * 100).rounded()))%")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AmenTheme.Colors.surfaceChip)
                    Capsule()
                        .fill(AmenTheme.Colors.amenGoldText)
                        .frame(width: geo.size.width * clamped)
                }
            }
            .frame(height: 10)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(Int((clamped * 100).rounded())) percent")
    }

    // MARK: Loading / error

    private var skeletonGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                  spacing: 12) {
            ForEach(0..<6, id: \.self) { _ in
                SkeletonBlock(height: 92, cornerRadius: 18)
            }
        }
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 8) {
            Text(message)
                .font(.footnote)
                .foregroundStyle(AmenTheme.Colors.statusError)
                .multilineTextAlignment(.center)
            Button("Try again") { Task { await load() } }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    // MARK: Load

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            metrics = try await CreatorHubService.shared.metrics(creatorId: creatorId)
        } catch {
            errorMessage = "Couldn't load your impact dashboard."
        }
    }
}

#if DEBUG
#Preview("KingdomMetricsModule") {
    ScrollView {
        KingdomMetricsModule(creatorId: "demo")
    }
    .background(AmenTheme.Colors.backgroundPrimary)
}
#endif
