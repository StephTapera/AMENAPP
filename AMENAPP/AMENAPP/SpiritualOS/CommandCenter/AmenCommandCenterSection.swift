// AmenCommandCenterSection.swift
// AMEN Spiritual OS — Agent F: Command Center
// Private formation overview shown at the TOP of the Profile tab, above the existing header.
// Built 2026-06-02.
//
// FORMATION HARD RULES (enforced in this file):
// - NEVER show counts with comparative language.
// - NEVER show counts as primary headings — always secondary.
// - daysInWordCount NEVER shown unless user explicitly opted in.
// - Label is "days in the Word", never "streak".
// - This section is ADDITIVE — existing profile content is never removed.

import SwiftUI
import Firebase
import FirebaseFirestore
import Foundation

// MARK: - AmenCommandCenterSection

struct AmenCommandCenterSection: View {

    @ObservedObject var viewModel: AmenCommandCenterViewModel
    var userId: String

    @AppStorage("spiritualOS_command_center_enabled") private var isEnabled = false

    // MARK: Body

    var body: some View {
        if !isEnabled {
            EmptyView()
        } else {
            content
                .task {
                    await viewModel.load(userId: userId)
                }
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 20) {
            formationHeader
            statGrid
            readingPlanSection
            gentleStreakSection
            optInSection
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 20)
    }

    // MARK: - Formation Header

    private var formationHeader: some View {
        HStack(spacing: 8) {
            Text("Your Formation")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.amenBlack)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            // Private indicator — subtle, non-alarming
            GlassChip(
                label: "Private",
                icon: "lock.fill",
                tint: .amenSlate,
                size: .compact,
                isActive: false,
                action: nil
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Your Formation — private, only visible to you")
    }

    // MARK: - Stat Grid

    private var statGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ],
            spacing: 12
        ) {
            if viewModel.isLoading {
                ForEach(0..<4, id: \.self) { _ in
                    loadingTilePlaceholder
                }
            } else {
                StatTile(
                    icon: "person.3.fill",
                    label: "Communities",
                    value: "\(viewModel.activeCommunityCount)"
                )
                StatTile(
                    icon: "doc.text.fill",
                    label: "Saved Notes",
                    value: "\(viewModel.savedNotesCount)"
                )
                StatTile(
                    icon: "sparkles",
                    label: "Berean Sessions",
                    value: "\(viewModel.bereanSessionCount)"
                )
                StatTile(
                    icon: "calendar.badge.clock",
                    label: "Upcoming",
                    value: "\(viewModel.upcomingEventCount)"
                )
            }
        }
    }

    // MARK: - Loading Placeholder

    private var loadingTilePlaceholder: some View {
        GlassCard(elevated: false) {
            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.amenSlate.opacity(0.15))
                    .frame(height: 24)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.amenSlate.opacity(0.10))
                    .frame(height: 12)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.amenSlate.opacity(0.10))
                    .frame(height: 20)
            }
            .padding(14)
        }
        .opacity(0.3)
        .accessibilityHidden(true)
    }

    // MARK: - Reading Plan Section

    @ViewBuilder
    private var readingPlanSection: some View {
        if let planTitle = viewModel.readingPlanTitle {
            GlassCard(elevated: false) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "book.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.amenGold)
                            .accessibilityHidden(true)
                        Text(planTitle)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.amenBlack)
                            .lineLimit(1)
                    }

                    ProgressView(value: viewModel.readingPlanProgress)
                        .progressViewStyle(.linear)
                        .tint(Color.amenGold)
                        .accessibilityLabel("Reading progress")
                        .accessibilityValue(
                            "\(Int(viewModel.readingPlanProgress * 100)) percent complete"
                        )

                    Text("\(Int(viewModel.readingPlanProgress * 100))% complete")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.amenSlate)
                }
                .padding(16)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "Reading plan: \(planTitle). \(Int(viewModel.readingPlanProgress * 100)) percent complete."
            )
        }
    }

    // MARK: - Gentle Streak Section (opt-in only)

    @ViewBuilder
    private var gentleStreakSection: some View {
        if viewModel.isFormationTrackingOptedIn, let count = viewModel.daysInWordCount {
            VStack(alignment: .leading, spacing: 10) {
                GlassCard(tint: Color.amenGold.opacity(0.10), elevated: false) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Days in the Word")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.amenSlate)

                        Text("\(count)")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(Color.amenGoldText)
                            .accessibilityLabel("\(count) days in the Word")

                        Text("This is your private count — only you can see this.")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.amenSlate)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                }

                // Toggle to stop tracking
                HStack(spacing: 10) {
                    Toggle(isOn: Binding(
                        get: { viewModel.isFormationTrackingOptedIn },
                        set: { _ in
                            Task { await viewModel.toggleFormationTracking(userId: userId) }
                        }
                    )) {
                        Text("Track days in the Word")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.amenBlack)
                    }
                    .tint(Color.amenGold)
                }

                Text("This count is private. It's an invitation, not a score.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.amenSlate)
                    .padding(.top, 2)
            }
        }
    }

    // MARK: - Opt-In Section (shown only when NOT opted in)

    @ViewBuilder
    private var optInSection: some View {
        if !viewModel.isFormationTrackingOptedIn {
            GlassCard(elevated: false) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Would you like to gently track your time in the Word? This is private and optional.")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.amenSlate)
                        .fixedSize(horizontal: false, vertical: true)

                    GlassChip(
                        label: "Enable gentle tracking",
                        icon: "leaf.fill",
                        tint: .amenGold,
                        size: .regular,
                        isActive: false
                    ) {
                        Task { await viewModel.toggleFormationTracking(userId: userId) }
                    }
                    .accessibilityHint("Enables private, optional tracking of days you spend time in the Word. You can turn this off at any time.")
                }
                .padding(16)
            }
        }
    }
}

// MARK: - StatTile (private, only used in this file)

private struct StatTile: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        GlassCard(elevated: false) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundStyle(Color.amenGold)
                    .symbolRenderingMode(.hierarchical)
                    .accessibilityHidden(true)

                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.amenSlate)
                    .lineLimit(1)

                Text(value)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.amenBlack)
                    .accessibilityLabel("\(label): \(value)")
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(value)")
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Command Center — opted in") {
    let vm = AmenCommandCenterViewModel()
    // Simulate loaded state
    vm.activeCommunityCount = 3
    vm.savedNotesCount = 12
    vm.bereanSessionCount = 4
    vm.upcomingEventCount = 2
    vm.readingPlanTitle = "Romans"
    vm.readingPlanProgress = 0.5
    vm.isFormationTrackingOptedIn = true
    vm.daysInWordCount = 14

    return ScrollView {
        AmenCommandCenterSection(viewModel: vm, userId: "preview-user")
    }
    .background(Color.amenCream)
    // Override AppStorage flag for preview
    .onAppear {
        UserDefaults.standard.set(true, forKey: "spiritualOS_command_center_enabled")
    }
}

#Preview("Command Center — opt-in prompt") {
    let vm = AmenCommandCenterViewModel()
    vm.activeCommunityCount = 1
    vm.savedNotesCount = 5
    vm.bereanSessionCount = 7
    vm.upcomingEventCount = 0
    vm.isFormationTrackingOptedIn = false
    vm.daysInWordCount = nil

    return ScrollView {
        AmenCommandCenterSection(viewModel: vm, userId: "preview-user")
    }
    .background(Color.amenCream)
    .onAppear {
        UserDefaults.standard.set(true, forKey: "spiritualOS_command_center_enabled")
    }
}

#Preview("Command Center — loading") {
    let vm = AmenCommandCenterViewModel()
    vm.isLoading = true

    return ScrollView {
        AmenCommandCenterSection(viewModel: vm, userId: "preview-user")
    }
    .background(Color.amenCream)
    .onAppear {
        UserDefaults.standard.set(true, forKey: "spiritualOS_command_center_enabled")
    }
}

#Preview("Command Center — disabled") {
    let vm = AmenCommandCenterViewModel()
    return AmenCommandCenterSection(viewModel: vm, userId: "preview-user")
        .onAppear {
            UserDefaults.standard.set(false, forKey: "spiritualOS_command_center_enabled")
        }
}
#endif
