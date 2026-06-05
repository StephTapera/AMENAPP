// AmenJourneySelectionView.swift
// AMEN Spiritual Journey Engine — Selection + Private Growth Views
//
// PART A: AmenJourneySelectionView
//   Full-screen onboarding-style picker for spiritual journey stages.
//   Feature flag: amen_journey_selection_enabled
//
// PART B: AmenJourneyPrivateGrowthView
//   Private, lock-adorned dashboard for personal growth metrics.
//   Zero social data. Zero public visibility.
//
// Glass is used only on the navigation bar (via .toolbarBackground).
// Cards sit on white/systemBackground — no glass-on-glass.

import SwiftUI

// MARK: - SelectionState Enum (shared)

private enum SelectionState { case primary, secondary, unselected }

// MARK: - PART A: AmenJourneySelectionView

struct AmenJourneySelectionView: View {

    @AppStorage("amen_journey_selection_enabled") private var selectionEnabled = true

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // The engine is the single source of truth for persistence.
    private let engine = AmenJourneyEngine.shared

    // MARK: Local selection state

    @State private var primaryStage: SpiritualJourneyStage? = nil
    @State private var secondaryStages: Set<SpiritualJourneyStage> = []
    @State private var customText: String = ""
    @State private var isSaving: Bool = false
    @State private var saveError: String? = nil

    // Derive gradient tint from selected primary stage (max 10 % opacity)
    private var backgroundTint: Color {
        primaryStage?.color.opacity(0.08) ?? Color.clear
    }

    var body: some View {
        if !selectionEnabled {
            EmptyView()
        } else {
            NavigationStack {
                ZStack {
                    // Subtle gradient — max 8 % opacity of the primary stage color
                    LinearGradient(
                        colors: [backgroundTint, Color(uiColor: .systemBackground)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()
                    .animation(.soAdaptive(reduceMotion: reduceMotion), value: primaryStage?.rawValue)

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            headerBlock
                            stageGrid
                            if primaryStage == .custom { customFieldBlock }
                            Spacer(minLength: 120)
                        }
                        .padding(.horizontal, 20)
                    }

                    // Sticky bottom CTA
                    VStack {
                        Spacer()
                        bottomBar
                    }
                    .ignoresSafeArea(edges: .bottom)
                }
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Skip") { dismiss() }
                            .font(.subheadline)
                            .foregroundStyle(Color.amenSlate)
                            .accessibilityLabel("Skip journey selection")
                    }
                }
                .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
            }
        }
    }

    // MARK: - Header

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What's your journey\nright now?")
                .font(.system(size: 28, weight: .bold, design: .default))
                .foregroundStyle(Color.amenBlack)
                .accessibilityAddTraits(.isHeader)

            Text("This helps us show you the right communities, mentors, and resources.")
                .font(.subheadline)
                .foregroundStyle(Color.amenSlate)
                .fixedSize(horizontal: false, vertical: true)

            Text("Choose one primary, up to two more.")
                .font(.caption)
                .foregroundStyle(Color.amenSlate.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 20)
        .padding(.bottom, 24)
    }

    // MARK: - Stage Grid

    private var stageGrid: some View {
        // 3-column adaptive grid
        let columns = [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]

        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(SpiritualJourneyStage.allCases, id: \.rawValue) { stage in
                StageTile(
                    stage: stage,
                    selectionState: tileState(for: stage),
                    onTap: { handleTap(stage) }
                )
            }
        }
    }

    // MARK: - Custom description field

    private var customFieldBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Describe your journey")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.amenBlack)

            TextField("e.g. Navigating grief while deepening faith…", text: $customText, axis: .vertical)
                .lineLimit(3...5)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(
                                    (primaryStage?.color ?? Color.amenSlate).opacity(0.3),
                                    lineWidth: 1
                                )
                        )
                )
                .font(.subheadline)
                .foregroundStyle(Color.amenBlack)
        }
        .padding(.top, 16)
        .transition(.opacity.combined(with: .move(edge: .top)))
        .animation(.soAdaptive(reduceMotion: reduceMotion), value: primaryStage?.rawValue)
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 0) {
            if let errorMsg = saveError {
                Text(errorMsg)
                    .font(.caption)
                    .foregroundStyle(Color.amenError)
                    .padding(.bottom, 8)
                    .padding(.horizontal, 24)
                    .multilineTextAlignment(.center)
            }

            Button(action: confirmJourney) {
                ZStack {
                    if isSaving {
                        ProgressView()
                            .tint(Color(uiColor: .systemBackground))
                    } else {
                        Text("Start My Journey")
                            .font(.body.weight(.semibold))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .foregroundStyle(Color(uiColor: .systemBackground))
                .background(
                    Capsule()
                        .fill(
                            primaryStage != nil
                                ? (primaryStage?.color ?? Color.accentColor)
                                : Color.amenSlate.opacity(0.35)
                        )
                )
            }
            .disabled(primaryStage == nil || isSaving)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 32)
            .background(.ultraThinMaterial)
            .accessibilityLabel("Start My Journey")
            .accessibilityHint(primaryStage == nil ? "Select at least one journey stage first" : "Saves your selected journey and opens your personalized feed")
        }
    }

    // MARK: - Tile state helper

    private func tileState(for stage: SpiritualJourneyStage) -> SelectionState {
        if primaryStage == stage { return .primary }
        if secondaryStages.contains(stage) { return .secondary }
        return .unselected
    }

    // MARK: - Tap handler

    private func handleTap(_ stage: SpiritualJourneyStage) {
        if primaryStage == stage {
            // Deselect primary — also removes from secondary if present
            primaryStage = nil
            secondaryStages.remove(stage)
        } else if secondaryStages.contains(stage) {
            secondaryStages.remove(stage)
        } else if primaryStage == nil {
            // First selection becomes primary
            withAnimation(.soAdaptive(reduceMotion: reduceMotion)) {
                primaryStage = stage
            }
        } else if secondaryStages.count < 2 {
            secondaryStages.insert(stage)
        }
        // If secondaryStages already has 2 and tapping a third: no-op (tile shows disabled state).
    }

    // MARK: - Confirm

    private func confirmJourney() {
        guard let primary = primaryStage else { return }
        isSaving = true
        saveError = nil

        let profile = UserJourneyProfile(
            primaryStage:      primary,
            secondaryStages:   Array(secondaryStages),
            customDescription: primary == .custom && !customText.isEmpty ? customText : nil,
            setAt:             Date(),
            updatedAt:         Date()
        )

        Task {
            do {
                try await engine.saveJourney(profile)
                await engine.updateGrowthSnapshot()
                dismiss()
            } catch {
                saveError = "Couldn't save your journey. Please try again."
            }
            isSaving = false
        }
    }
}

// MARK: - StageTile

private struct StageTile: View {

    let stage: SpiritualJourneyStage
    let selectionState: SelectionState
    let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isPrimary:   Bool { selectionState == .primary }
    private var isSecondary: Bool { selectionState == .secondary }
    private var isSelected:  Bool { isPrimary || isSecondary }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(isSelected ? stage.color.opacity(isPrimary ? 0.18 : 0.10) : Color(uiColor: .secondarySystemBackground))
                        .frame(width: 44, height: 44)

                    Image(systemName: stage.iconName)
                        .font(.system(size: 20, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(isSelected ? stage.color : Color.amenSlate)

                    if isSelected {
                        Image(systemName: isPrimary ? "checkmark.circle.fill" : "checkmark.circle")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(stage.color)
                            .frame(width: 44, height: 44, alignment: .topTrailing)
                            .offset(x: 8, y: -8)
                    }
                }

                Text(stage.displayName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isSelected ? stage.color : Color.amenBlack)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 92)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(uiColor: .systemBackground))
                    .shadow(
                        color: isSelected ? stage.color.opacity(0.22) : Color.black.opacity(0.05),
                        radius: isSelected ? 8 : 4,
                        x: 0, y: isSelected ? 3 : 2
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        isSelected ? stage.color.opacity(isPrimary ? 0.55 : 0.30) : Color.clear,
                        lineWidth: isPrimary ? 2 : 1.5
                    )
            )
            .scaleEffect(isSelected ? 1.02 : 1.0)
            .animation(.soAdaptive(reduceMotion: reduceMotion, response: LiquidGlassTokens.motionFast), value: selectionState)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(stage.displayName). \(stage.description)")
        .accessibilityHint(
            isPrimary   ? "Selected as primary journey" :
            isSecondary ? "Selected as secondary journey" :
            "Tap to select as primary journey"
        )
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - PART B: AmenJourneyPrivateGrowthView

struct AmenJourneyPrivateGrowthView: View {

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showJourneyPicker = false
    @State private var userId: String = ""

    private let engine = AmenJourneyEngine.shared

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 24) {

                    if engine.isLoading {
                        loadingPlaceholder
                    } else {
                        journeyStagesBlock
                        growthAreasSection
                        opportunitiesSection
                        continueRail
                        monthlyStatsGrid
                        updateJourneyButton
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
            .background(Color(uiColor: .systemBackground).ignoresSafeArea())
            .navigationTitle("Your Journey")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.amenSlate)
                        Text("Your Journey")
                            .font(.headline)
                            .foregroundStyle(Color.amenBlack)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Image(systemName: "lock.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.amenSlate.opacity(0.7))
                        .accessibilityLabel("Private — only visible to you")
                }
            }
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .sheet(isPresented: $showJourneyPicker) {
            AmenJourneySelectionView()
        }
    }

    // MARK: - Loading placeholder

    private var loadingPlaceholder: some View {
        VStack(spacing: 16) {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AmenTheme.Colors.shimmerBase)
                    .frame(height: 80)
                    .amenSkeleton()
            }
        }
    }

    // MARK: - Journey stages block

    private var journeyStagesBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let journey = engine.currentJourney {
                sectionLabel("Your Focus")

                // Primary stage — large card
                JourneyStageCard(stage: journey.primaryStage, isPrimary: true)

                // Secondary stages — compact row
                if !journey.secondaryStages.isEmpty {
                    HStack(spacing: 12) {
                        ForEach(journey.secondaryStages, id: \.rawValue) { stage in
                            JourneyStageCard(stage: stage, isPrimary: false)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }

                if let custom = journey.customDescription, !custom.isEmpty {
                    Text("\u{201C}\(custom)\u{201D}")
                        .font(.subheadline.italic())
                        .foregroundStyle(Color.amenSlate)
                        .padding(.horizontal, 4)
                }
            } else {
                noJourneyPrompt
            }
        }
    }

    private var noJourneyPrompt: some View {
        VStack(spacing: 12) {
            Image(systemName: "map.fill")
                .font(.system(size: 32))
                .foregroundStyle(Color.accentColor)
            Text("You haven't set your journey yet.")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.amenBlack)
            Button("Set My Journey") { showJourneyPicker = true }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(.label))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .amenCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("You haven't set your journey yet. Tap to set your journey.")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Growth areas section

    private var growthAreasSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Growth Areas")

            if let snapshot = engine.growthSnapshot, !snapshot.strongAreas.isEmpty {
                ForEach(snapshot.strongAreas, id: \.self) { area in
                    GrowthAreaCard(
                        areaName: area,
                        isStrength: true,
                        message: encouragementMessage(for: area)
                    )
                }
            } else {
                emptyAreaCard(message: "Complete a study or prayer session to see your strengths.")
            }
        }
    }

    // MARK: - Opportunities section

    private var opportunitiesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Opportunities")

            if let snapshot = engine.growthSnapshot, !snapshot.growthOpportunities.isEmpty {
                ForEach(snapshot.growthOpportunities, id: \.self) { area in
                    GrowthAreaCard(
                        areaName: area,
                        isStrength: false,
                        message: opportunityMessage(for: area)
                    )
                }
            } else {
                emptyAreaCard(message: "Your growth opportunities will appear here over time.")
            }
        }
    }

    // MARK: - Continue rail

    private var continueRail: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !engine.progressItems.isEmpty {
                sectionLabel("Continue Where You Left Off")

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(engine.progressItems.filter { !$0.completed }) { item in
                            ProgressItemCard(item: item)
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
        }
    }

    // MARK: - Monthly stats grid

    private var monthlyStatsGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("This Month")

            if let snapshot = engine.growthSnapshot {
                let stats: [(label: String, value: Int, icon: String)] = [
                    ("Studies Done",   snapshot.studiesCompleted,        "book.closed.fill"),
                    ("In Progress",    snapshot.studiesInProgress,       "book.fill"),
                    ("Prayers",        snapshot.prayerSessionsThisMonth, "hands.sparkles.fill"),
                    ("Mentorships",    snapshot.mentorshipSessionsTotal, "person.badge.plus.fill"),
                    ("Communities",    snapshot.communitiesJoined,       "person.3.fill"),
                    ("Events",         snapshot.eventsAttended,          "calendar"),
                    ("Notes",          snapshot.notesWritten,            "pencil"),
                    ("Discussions",    snapshot.discussionsParticipated, "bubble.left.and.bubble.right.fill")
                ]

                let columns = [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ]

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(stats, id: \.label) { stat in
                        StatCell(label: stat.label, value: stat.value, icon: stat.icon)
                    }
                }
            } else {
                emptyAreaCard(message: "Your monthly stats will appear here.")
            }
        }
    }

    // MARK: - Update journey button

    private var updateJourneyButton: some View {
        Button(action: { showJourneyPicker = true }) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.subheadline.weight(.medium))
                Text("Update Your Journey")
                    .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .foregroundStyle(Color.amenBlack)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.amenSlate.opacity(0.20), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Update your journey")
        .accessibilityHint("Opens the journey selection screen")
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(1.0)
            .foregroundStyle(Color.amenSlate)
            .accessibilityAddTraits(.isHeader)
    }

    private func emptyAreaCard(message: String) -> some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(Color.amenSlate)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .padding(.horizontal, 12)
            .amenCard(cornerRadius: 14)
    }

    private func encouragementMessage(for area: String) -> String {
        switch area {
        case "Bible Study":  return "You\u{2019}re building a deep foundation in Scripture."
        case "Prayer":       return "Your consistent prayer life is bearing fruit."
        case "Mentorship":   return "You\u{2019}re investing in others and being invested in."
        case "Community":    return "You\u{2019}re actively rooted in community."
        case "Events":       return "You show up and engage — that matters."
        case "Notes":        return "Your note-taking shows attentiveness to God\u{2019}s word."
        case "Discussions":  return "You engage thoughtfully with your community."
        default:             return "You are growing in this area."
        }
    }

    private func opportunityMessage(for area: String) -> String {
        switch area {
        case "Bible Study":  return "You haven\u{2019}t started a study yet. Explore studies \u{2192}"
        case "Prayer":       return "You haven\u{2019}t logged a prayer session this month. Start one \u{2192}"
        case "Mentorship":   return "Mentorship deepens faith. Find a mentor \u{2192}"
        case "Community":    return "You haven\u{2019}t joined a community yet. Explore spaces \u{2192}"
        case "Events":       return "There are events near you this week. See what\u{2019}s happening \u{2192}"
        case "Notes":        return "Capture what you\u{2019}re learning in church notes \u{2192}"
        case "Discussions":  return "Join a discussion to engage with your community \u{2192}"
        default:             return "There\u{2019}s room to grow here. Explore resources \u{2192}"
        }
    }
}

// MARK: - JourneyStageCard

private struct JourneyStageCard: View {
    let stage: SpiritualJourneyStage
    let isPrimary: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(stage.color.opacity(0.14))
                    .frame(width: isPrimary ? 44 : 36, height: isPrimary ? 44 : 36)
                Image(systemName: stage.iconName)
                    .font(.system(size: isPrimary ? 20 : 16, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(stage.color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(isPrimary ? "Primary" : "Also focusing on")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.amenSlate)
                Text(stage.displayName)
                    .font(isPrimary ? .body.weight(.semibold) : .subheadline.weight(.medium))
                    .foregroundStyle(Color.amenBlack)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, isPrimary ? 14 : 10)
        .amenCard(cornerRadius: isPrimary ? 16 : 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(isPrimary ? "Primary journey" : "Secondary journey"): \(stage.displayName). \(stage.description)")
    }
}

// MARK: - GrowthAreaCard

private struct GrowthAreaCard: View {
    let areaName: String
    let isStrength: Bool
    let message: String

    private var icon: String {
        isStrength ? "star.fill" : "arrow.up.forward.circle.fill"
    }

    private var tintColor: Color {
        isStrength ? Color.accentColor : Color.amenBlue
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tintColor)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(areaName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.amenBlack)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(Color.amenSlate)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(16)
        .amenCard(cornerRadius: 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(isStrength ? "Strength" : "Opportunity"): \(areaName). \(message)")
    }
}

// MARK: - ProgressItemCard

private struct ProgressItemCard: View {
    let item: JourneyProgressItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: item.typeIcon)
                    .font(.caption.weight(.medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.amenPurple)
                Text(item.type.capitalized)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.amenSlate)
                Spacer()
            }

            Text(item.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.amenBlack)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.amenSlate.opacity(0.15))
                        .frame(height: 4)
                    Capsule()
                        .fill(Color.amenPurple)
                        .frame(width: geo.size.width * item.progressFraction, height: 4)
                }
            }
            .frame(height: 4)

            Text("\(Int(item.progressFraction * 100))% complete")
                .font(.caption2)
                .foregroundStyle(Color.amenSlate)
        }
        .padding(14)
        .frame(width: 180)
        .amenCard(cornerRadius: 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title). \(item.type.capitalized). \(Int(item.progressFraction * 100)) percent complete.")
        .accessibilityHint("Double-tap to continue")
    }
}

// MARK: - StatCell

private struct StatCell: View {
    let label: String
    let value: Int
    let icon: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.amenSlate)

            Text("\(value)")
                .font(.title3.weight(.bold))
                .foregroundStyle(Color.amenBlack)
                .monospacedDigit()

            Text(label)
                .font(.caption2)
                .foregroundStyle(Color.amenSlate)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.80)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity)
        .amenCard(cornerRadius: 12, shadow: false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

