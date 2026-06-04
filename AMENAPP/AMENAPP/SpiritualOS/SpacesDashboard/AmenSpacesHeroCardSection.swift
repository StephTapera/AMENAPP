// AmenSpacesHeroCardSection.swift
// AMEN Spiritual OS — Spaces Dashboard HeroCard Section
// Full parallax hero + stat row + study callout card + quick actions + activity feed.
// Updated 2026-06-03 — migrated to @Observable ViewModel; real Firestore data.

import SwiftUI
import FirebaseFirestore
import Foundation

// MARK: - Relative date formatter (file-private)

private let relativeFormatter: RelativeDateTimeFormatter = {
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .abbreviated
    return f
}()

// MARK: - Member avatar stack

private struct MemberAvatarStack: View {
    let memberPreviews: [MemberPreview]
    let totalMemberCount: Int

    private let size: CGFloat = 30
    private let overlap: CGFloat = 10

    var body: some View {
        HStack(spacing: -(overlap)) {
            ForEach(Array(memberPreviews.prefix(5).enumerated()), id: \.offset) { index, member in
                CachedAsyncImage(url: member.photoURL, size: CGSize(width: 60, height: 60)) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Circle()
                        .fill(Color.white.opacity(0.2))
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.white.opacity(0.6))
                        )
                }
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Color(hex: "070607"), lineWidth: 1.5))
                .zIndex(Double(5 - index))
            }
        }
    }
}

// MARK: - Hero parallax image

private struct HeroParallaxImage: View {
    let bannerURL: String?
    let spaceName: String
    let scrollOffset: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Gradient fallback (always present)
                LinearGradient(
                    stops: [
                        .init(color: Color(hex: "6E4BB5").opacity(0.85), location: 0.0),
                        .init(color: Color(hex: "245B8F").opacity(0.75), location: 0.45),
                        .init(color: Color(hex: "070607"),               location: 1.0)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // Banner image with optional parallax offset
                if let urlString = bannerURL, let url = URL(string: urlString) {
                    CachedAsyncImage(url: url, size: CGSize(width: 800, height: 600)) { image in
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: geo.size.width, height: 300)
                            .clipped()
                            .offset(y: reduceMotion ? 0 : min(0, scrollOffset * 0.4))
                    } placeholder: {
                        Color.clear
                    }
                }

                // Bottom scrim for readability
                LinearGradient(
                    colors: [Color.clear, Color(hex: "070607").opacity(0.82)],
                    startPoint: .center,
                    endPoint: .bottom
                )
            }
        }
        .accessibilityLabel("\(spaceName) banner photo")
        .accessibilityHidden(false)
    }
}

// MARK: - Space name frosted capsule (bottom-leading, NOT full-width)

private struct SpaceNameCapsule: View {
    let spaceName: String
    let tagline: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(spaceName)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            if let tagline {
                Text(tagline)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5)
                }
        }
    }
}

// MARK: - Stat row (plain background — no glass)

private struct DashboardStatRow: View {
    let memberPreviews: [MemberPreview]
    let totalMemberCount: Int
    let activePrayerCount: Int
    let nextEvent: SpaceEvent?

    private var nextEventLabel: String {
        guard let event = nextEvent else { return "No events" }
        let f = DateFormatter()
        f.dateFormat = "EEE h a"
        return f.string(from: event.startTime)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            // Member avatars + overflow count
            HStack(spacing: 8) {
                MemberAvatarStack(
                    memberPreviews: memberPreviews,
                    totalMemberCount: totalMemberCount
                )
                if totalMemberCount > memberPreviews.count {
                    Text("+\(totalMemberCount - memberPreviews.count)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.65))
                }
            }

            Spacer()

            // Active prayer count
            HStack(spacing: 5) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: "D9A441"))
                Text("\(activePrayerCount) Prayer\(activePrayerCount == 1 ? "" : "s")")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.85))
            }

            Spacer()

            // Next event
            HStack(spacing: 5) {
                Image(systemName: "calendar")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: "245B8F"))
                Text(nextEventLabel)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(statRowA11yLabel)
    }

    private var statRowA11yLabel: String {
        let eventPart: String
        if let event = nextEvent {
            eventPart = event.startTime.formatted(.dateTime.weekday().hour().minute())
        } else {
            eventPart = "none"
        }
        return "\(totalMemberCount) members, \(activePrayerCount) active prayer requests, next event \(eventPart)"
    }
}

// MARK: - Study series card (LiquidGlassCard — one callout, per glass rules)

private struct StudySeriesCard: View {
    let series: StudySeries

    var body: some View {
        LiquidGlassCard(contextTint: Color(hex: "6E4BB5"), elevated: false) {
            HStack(spacing: 14) {
                Image(systemName: "book.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color(hex: "D9A441"))

                VStack(alignment: .leading, spacing: 3) {
                    Text(series.seriesTitle)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text("Week \(series.currentWeek) of \(series.totalWeeks)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.65))

                    if let reading = series.suggestedReading, !reading.isEmpty {
                        Text(reading)
                            .font(.system(size: 12))
                            .foregroundStyle(Color(hex: "D9A441").opacity(0.90))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Current study: \(series.seriesTitle), week \(series.currentWeek) of \(series.totalWeeks)"
            + (series.suggestedReading.map { ". Reading: \($0)" } ?? "")
        )
    }
}

// MARK: - Quick action button (.bordered style — NOT glass)

private struct QuickActionButton: View {
    let label: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.system(size: 13, weight: .semibold))
        }
        .buttonStyle(.bordered)
        .tint(Color(hex: "D9A441"))
        .accessibilityLabel(label)
    }
}

// MARK: - Activity row (plain — no glass)

private struct ActivityRow: View {
    let item: ActivityItem

    private var iconName: String {
        switch item.actionType {
        case "prayer": return "hands.sparkles.fill"
        case "note":   return "doc.text.fill"
        case "event":  return "calendar.circle.fill"
        default:       return "text.bubble.fill"
        }
    }

    private var iconTint: Color {
        switch item.actionType {
        case "prayer": return Color(hex: "D9A441")
        case "note":   return Color(hex: "245B8F")
        case "event":  return Color(hex: "D9A441")
        default:       return Color(hex: "6E4BB5")
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CachedAsyncImage(url: item.actorPhotoURL, size: CGSize(width: 72, height: 72)) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Circle()
                    .fill(Color.white.opacity(0.15))
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.white.opacity(0.5))
                    )
            }
            .frame(width: 36, height: 36)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: iconName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(iconTint)

                    Text(item.actorName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }

                Text(item.summary)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 0)

            Text(relativeFormatter.localizedString(for: item.timestamp, relativeTo: Date()))
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.40))
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(item.actorName): \(item.summary), "
            + relativeFormatter.localizedString(for: item.timestamp, relativeTo: Date())
        )
    }
}

// MARK: - Loading placeholder

private struct HeroLoadingPlaceholder: View {
    var body: some View {
        VStack {
            Spacer()
            ProgressView()
                .tint(Color(hex: "D9A441"))
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .frame(height: 260)
        .background(Color(hex: "070607").opacity(0.6))
        .accessibilityHidden(true)
    }
}

// MARK: - Section header (plain label — no glass)

private func dashboardSectionHeader(title: String) -> some View {
    Text(title.uppercased())
        .font(.system(size: 11, weight: .bold))
        .kerning(1.2)
        .foregroundStyle(Color.white.opacity(0.50))
        .padding(.horizontal, 16)
}

// MARK: - AmenSpacesHeroCardSection

/// Drop this view at the top of any Space detail view.
/// Self-contained: owns its ViewModel, fires .task { await vm.load() }.
struct AmenSpacesHeroCardSection: View {

    // MARK: Props

    let spaceId: String
    let bannerURL: String?
    let spaceName: String

    // Legacy support for callers using (spaceId:, userId:) signature
    var userId: String = ""

    // MARK: Feature flag

    @AppStorage("spiritualOS_spaces_dashboard_enabled") private var globalEnabled = true

    // MARK: ViewModel (@Observable — use @State, not @StateObject)

    @State private var viewModel: AmenSpacesDashboardViewModel

    // MARK: Sheet state

    @State private var showPrayTogether = false
    @State private var showSchedule = false
    @State private var showNotes = false
    @State private var showAskBerean = false
    @State private var showDiscussion = false

    // MARK: Scroll offset (provided by parent via preference key)

    @State private var scrollOffset: CGFloat = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: Primary init

    init(spaceId: String, bannerURL: String?, spaceName: String) {
        self.spaceId = spaceId
        self.bannerURL = bannerURL
        self.spaceName = spaceName
        _viewModel = State(wrappedValue: AmenSpacesDashboardViewModel(spaceId: spaceId))
    }

    // MARK: Legacy init for existing callers

    init(spaceId: String, userId: String) {
        self.spaceId = spaceId
        self.bannerURL = nil
        self.spaceName = ""
        self.userId = userId
        _viewModel = State(wrappedValue: AmenSpacesDashboardViewModel(spaceId: spaceId))
    }

    // MARK: Body

    var body: some View {
        Group {
            if viewModel.isLoading {
                HeroLoadingPlaceholder()
            } else {
                heroContent
            }
        }
        .task {
            await viewModel.load()
        }
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

    // MARK: - Hero content

    @ViewBuilder
    private var heroContent: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Hero image (260 pt) with frosted name capsule ─────────────────
            ZStack(alignment: .bottomLeading) {
                HeroParallaxImage(
                    bannerURL: bannerURL,
                    spaceName: spaceName,
                    scrollOffset: scrollOffset
                )
                .frame(height: 260)
                .clipped()

                // Frosted name capsule — bottom-leading, NOT full-width
                SpaceNameCapsule(
                    spaceName: spaceName.isEmpty
                        ? (viewModel.memberPreviews.first?.displayName ?? "Space")
                        : spaceName,
                    tagline: viewModel.nextEvent.map { "Next: \($0.title)" }
                )
                .padding(.leading, 16)
                .padding(.bottom, 16)
            }
            .frame(height: 260)

            // ── Stat row (plain background — no glass) ────────────────────────
            DashboardStatRow(
                memberPreviews: viewModel.memberPreviews,
                totalMemberCount: viewModel.totalMemberCount,
                activePrayerCount: viewModel.activePrayerCount,
                nextEvent: viewModel.nextEvent
            )
            .background(Color(hex: "070607"))

            // ── Current study card (single LiquidGlassCard callout — per glass rules) ──
            if let series = viewModel.currentStudySeries {
                StudySeriesCard(series: series)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 4)
            }

            // ── Quick action buttons (.bordered — NOT glass) ──────────────────
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    QuickActionButton(
                        label: "Pray Together",
                        icon: "hands.sparkles"
                    ) { showPrayTogether = true }

                    QuickActionButton(
                        label: "Start Discussion",
                        icon: "bubble.left.and.bubble.right"
                    ) { showDiscussion = true }

                    QuickActionButton(
                        label: "Open Notes",
                        icon: "doc.text"
                    ) { showNotes = true }

                    QuickActionButton(
                        label: "Ask Berean",
                        icon: "sparkles"
                    ) { showAskBerean = true }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(hex: "070607"))

            // ── Recent activity (plain rows — no glass) ──────────────────────
            if !viewModel.recentActivity.isEmpty {
                dashboardSectionHeader(title: "Recent Activity")
                    .padding(.top, 8)
                    .padding(.bottom, 2)

                VStack(spacing: 0) {
                    ForEach(viewModel.recentActivity) { item in
                        ActivityRow(item: item)

                        if item.id != viewModel.recentActivity.last?.id {
                            Divider()
                                .background(Color.white.opacity(0.07))
                                .padding(.horizontal, 16)
                        }
                    }
                }
                .background(Color(hex: "070607"))
                .padding(.bottom, 8)
            }
        }
    }
}

// MARK: - Placeholder Sheets (intentional — each replaced by dedicated OS in a later phase)

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
