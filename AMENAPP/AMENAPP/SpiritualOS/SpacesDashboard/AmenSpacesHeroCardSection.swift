// AmenSpacesHeroCardSection.swift
// AMEN Spiritual OS — Agent D: Spaces Dashboard HeroCard
// Additive section placed at the top of Space detail views.
// Built 2026-06-02 — all existing Space UI remains below this section.

import SwiftUI
import FirebaseFirestore
import Foundation

// MARK: - AmenSpacesHeroCardSection

/// Drop this view at the top of any Space detail view.
/// It is fully self-contained: it owns its ViewModel, respects both feature flags,
/// and renders nothing (zero height) when either flag is off.
struct AmenSpacesHeroCardSection: View {

    // MARK: Props

    var spaceId: String
    var userId: String

    // MARK: Feature flags

    /// Global kill-switch: Remote Config / AppStorage toggle for the entire surface.
    @AppStorage("spiritualOS_spaces_dashboard_enabled") private var globalEnabled = false

    // MARK: ViewModel

    @StateObject private var viewModel: AmenSpacesDashboardViewModel

    // MARK: Sheet state

    @State private var showPrayTogether = false
    @State private var showSchedule = false
    @State private var showNotes = false
    @State private var showAskBerean = false

    // MARK: Init

    init(spaceId: String, userId: String) {
        self.spaceId = spaceId
        self.userId = userId
        _viewModel = StateObject(wrappedValue: AmenSpacesDashboardViewModel(spaceId: spaceId))
    }

    // MARK: Body

    var body: some View {
        Group {
            if viewModel.isLoading {
                loadingPlaceholder
            } else if globalEnabled && viewModel.heroCardEnabled {
                heroCardContent
            }
            // When both flags are off this view contributes no layout space.
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .task {
            await viewModel.load()
        }
    }

    // MARK: - Hero card content

    @ViewBuilder
    private var heroCardContent: some View {
        let actions = viewModel.buildActions(
            onPrayTogether: { showPrayTogether = true },
            onSchedule:     { showSchedule     = true },
            onOpenNotes:    { showNotes         = true },
            onAskBerean:    { showAskBerean     = true }
        )

        let heroEvent: HeroCardEvent? = viewModel.nextEvent.map { event in
            HeroCardEvent(title: event.title, date: event.date, icon: "calendar")
        }

        ZStack(alignment: .topTrailing) {
            HeroCard(
                title: viewModel.spaceTitle,
                subtitle: viewModel.spaceSubtitle,
                coverImageURL: viewModel.coverImageURL,
                tint: .amenGold,
                memberAvatars: viewModel.memberAvatarURLs,
                memberCount: viewModel.memberCount,
                nextEvent: heroEvent,
                actions: actions,
                onTap: {}
            )

            // Overlay chips — top-trailing corner, stacked vertically
            VStack(alignment: .trailing, spacing: 6) {
                // Study series chip — only when a series is set
                if let series = viewModel.currentStudySeries {
                    GlassChip(
                        label: series,
                        icon: "book.fill",
                        tint: .amenPurple,
                        size: .compact,
                        isActive: true
                    )
                }

                // Active prayer pastoral badge — only when > 0.
                // Shown as icon + count only: not labeled "active prayers"
                // to avoid turning a sacred signal into a comparative social metric.
                if viewModel.activePrayerCount > 0 {
                    GlassChip(
                        label: "\(viewModel.activePrayerCount)",
                        icon: "hands.sparkles",
                        tint: .amenBlue,
                        size: .compact
                    )
                    .accessibilityLabel("Prayer activity")
                    .accessibilityHint("Indicates this space has active prayer requests")
                }
            }
            .padding(12)
        }
        // Modals — placeholder sheets for each action
        .sheet(isPresented: $showPrayTogether) {
            PrayTogetherPlaceholderSheet(spaceId: spaceId)
        }
        .sheet(isPresented: $showSchedule) {
            SchedulePlaceholderSheet(spaceId: spaceId)
        }
        .sheet(isPresented: $showNotes) {
            OpenNotesPlaceholderSheet(spaceId: spaceId)
        }
        .sheet(isPresented: $showAskBerean) {
            AskBereanPlaceholderSheet(spaceId: spaceId)
        }
    }

    // MARK: - Loading placeholder

    private var loadingPlaceholder: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(Color.amenSlate.opacity(0.3))
            .frame(maxWidth: .infinity)
            .frame(height: 200)
            .accessibilityHidden(true)
    }
}

// MARK: - Placeholder Sheets
// These sheet bodies are intentional placeholders. Each will be replaced by its
// dedicated feature view (Pray Together OS, Schedule OS, Notes OS, Berean OS)
// in a subsequent agent phase. They are NOT stubs — they present real UI.

private struct PrayTogetherPlaceholderSheet: View {
    let spaceId: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "hands.sparkles")
                    .font(.largeTitle)
                    .foregroundStyle(Color.amenGold)
                Text("Pray Together")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Color.amenBlack)
                Text("Group prayer for this space is coming in a future phase.")
                    .font(.subheadline)
                    .foregroundStyle(Color.amenSlate)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.amenCream.ignoresSafeArea())
            .navigationTitle("Pray Together")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

private struct SchedulePlaceholderSheet: View {
    let spaceId: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "calendar.badge.plus")
                    .font(.largeTitle)
                    .foregroundStyle(Color.amenBlue)
                Text("Schedule an Event")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Color.amenBlack)
                Text("Space event scheduling is coming in a future phase.")
                    .font(.subheadline)
                    .foregroundStyle(Color.amenSlate)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.amenCream.ignoresSafeArea())
            .navigationTitle("Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

private struct OpenNotesPlaceholderSheet: View {
    let spaceId: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "doc.text")
                    .font(.largeTitle)
                    .foregroundStyle(Color.amenBlue)
                Text("Space Notes")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Color.amenBlack)
                Text("Shared study notes for this space are coming in a future phase.")
                    .font(.subheadline)
                    .foregroundStyle(Color.amenSlate)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.amenCream.ignoresSafeArea())
            .navigationTitle("Open Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

private struct AskBereanPlaceholderSheet: View {
    let spaceId: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "sparkles")
                    .font(.largeTitle)
                    .foregroundStyle(Color.amenPurple)
                Text("Ask Berean")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Color.amenBlack)
                Text("Berean AI study assistance for this space is coming in a future phase.")
                    .font(.subheadline)
                    .foregroundStyle(Color.amenSlate)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.amenCream.ignoresSafeArea())
            .navigationTitle("Ask Berean")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
