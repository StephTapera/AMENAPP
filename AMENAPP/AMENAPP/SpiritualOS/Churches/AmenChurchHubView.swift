// AmenChurchHubView.swift
// AMEN Spiritual OS — Church Hub
// Apple TV–style immersive church hub: hero, live, sermons, events, small groups,
// prayer wall, team, volunteer, highlights, new-member CTA, stats.
// Liquid Glass ONLY on: back button, share button, hero action pills, LIVE badge.
// All content sections use white/.secondarySystemBackground cards — no glass.
// Created 2026-06-03.

import SwiftUI
import FirebaseFirestore
import SafariServices
import MapKit

// MARK: - Feature flags

private extension AmenChurchHubView {
    var hubEnabled: Bool { _hubEnabled }
    var liveEnabled: Bool { _liveEnabled }
}

// MARK: - AmenChurchHubView

struct AmenChurchHubView: View {

    // MARK: Props

    private let churchId: String
    private let onDismiss: () -> Void

    // MARK: Feature flags

    @AppStorage("amen_church_hub_enabled")      private var _hubEnabled: Bool = true
    @AppStorage("amen_church_hub_live_enabled") private var _liveEnabled: Bool = true

    // MARK: ViewModel

    @State private var viewModel: AmenChurchHubViewModel

    // MARK: Sheet / navigation state

    @State private var safariURL: URL? = nil
    @State private var showShare: Bool = false
    @State private var pulseOpacity: Double = 1.0

    // MARK: Environment

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: Init

    init(churchId: String, onDismiss: @escaping () -> Void) {
        self.churchId = churchId
        self.onDismiss = onDismiss
        _viewModel = State(wrappedValue: AmenChurchHubViewModel(churchId: churchId))
    }

    // MARK: Body

    var body: some View {
        Group {
            if !hubEnabled {
                featureGatedFallback
            } else {
                mainContent
            }
        }
        .task {
            await viewModel.load(churchId: churchId)
        }
        .sheet(isPresented: Binding(
            get: { safariURL != nil },
            set: { if !$0 { safariURL = nil } }
        )) {
            if let url = safariURL {
                ChurchHubSafariView(url: url)
                    .ignoresSafeArea()
            }
        }
    }

    // MARK: - Feature-gated fallback

    private var featureGatedFallback: some View {
        VStack(spacing: 16) {
            Image(systemName: "building.columns")
                .font(.largeTitle)
                .foregroundStyle(Color(.secondaryLabel))
            Text("Church Hub is not yet available")
                .font(.headline)
                .foregroundStyle(Color(.label))
            Button("Go Back", action: onDismiss)
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    // MARK: - Main content

    private var mainContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                heroSection
                contentSections
            }
        }
        .ignoresSafeArea(edges: .top)
        .background(Color(.systemBackground))
        .overlay(alignment: .topLeading) { backButton }
        .overlay(alignment: .topTrailing) { shareButton }
    }

    // MARK: - Hero (340 pt)

    private var heroSection: some View {
        ZStack(alignment: .bottom) {
            // Full-bleed image
            GeometryReader { geo in
                let parallaxOffset = geo.frame(in: .global).minY
                ZStack {
                    // Fallback background (always present behind image)
                    Color(.systemGroupedBackground)

                    if let urlString = viewModel.church?.heroImageURL,
                       let url = URL(string: urlString) {
                        CachedAsyncImage(url: url, size: CGSize(width: 800, height: 600)) { image in
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: geo.size.width, height: 340)
                                .clipped()
                                .offset(y: reduceMotion ? 0 : min(0, parallaxOffset * 0.35))
                        } placeholder: {
                            Color.clear
                        }
                    }

                    // Bottom scrim for readability
                    LinearGradient(
                        colors: [Color.clear, Color(.systemBackground).opacity(0.75)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                }
            }
            .frame(height: 340)

            // Hero text + action pills overlay
            VStack(alignment: .leading, spacing: 12) {
                if viewModel.isLoadingChurch {
                    heroLoadingPlaceholder
                } else if let church = viewModel.church {
                    heroInfoBlock(church: church)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .frame(height: 340)
        .accessibilityLabel(viewModel.church.map { "\($0.name) church hero" } ?? "Church hero")
    }

    @ViewBuilder
    private func heroInfoBlock(church: ChurchHubProfile) -> some View {
        // Church name + denomination
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(church.name)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                if church.verifiedMinistry {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .accessibilityLabel("Verified ministry")
                }
            }

            if let denomination = church.denomination {
                Text(denomination)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.white.opacity(0.72))
            }

            Text(church.location)
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.55))
        }

        // Action pills (Liquid Glass per rules)
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                // Follow / Following pill
                heroPill(
                    label: viewModel.isFollowing ? "Following" : "Follow",
                    icon: viewModel.isFollowing ? "checkmark" : "plus",
                    tint: viewModel.isFollowing ? Color.accentColor : Color.white
                ) {
                    Task { await viewModel.toggleFollow() }
                }
                .animation(.amenSpringBouncy, value: viewModel.isFollowing)

                // Live pill (only when live)
                if liveEnabled && viewModel.isLiveNow {
                    heroPill(label: "Watch Live", icon: "play.circle.fill", tint: Color.red) {
                        if let urlString = viewModel.church?.liveStreamURL,
                           let url = URL(string: urlString) {
                            safariURL = url
                        }
                    }
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                }

                // Directions pill
                heroPill(label: "Directions", icon: "map.fill", tint: Color.amenBlue) {
                    openDirections(location: church.location)
                }
            }
            .padding(.vertical, 2)
        }
        .animation(.amenSpringStandard, value: viewModel.isLiveNow)
    }

    private func heroPill(label: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .padding(.horizontal, 16)
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
        .accessibilityLabel(label)
    }

    private var heroLoadingPlaceholder: some View {
        ProgressView()
            .tint(Color.accentColor)
            .frame(height: 80)
            .accessibilityHidden(true)
    }

    // MARK: - Glass nav buttons (Liquid Glass — overlay on hero)

    private var backButton: some View {
        Button(action: onDismiss) {
            Image(systemName: "chevron.left")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay {
                            Circle()
                                .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5)
                        }
                }
        }
        .padding(.top, 56)
        .padding(.leading, 20)
        .accessibilityLabel("Go back")
    }

    private var shareButton: some View {
        Button {
            showShare = true
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay {
                            Circle()
                                .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5)
                        }
                }
        }
        .padding(.top, 56)
        .padding(.trailing, 20)
        .accessibilityLabel("Share church")
        .shareSheet(isPresented: $showShare, items: shareItems)
    }

    private var shareItems: [Any] {
        var items: [Any] = []
        if let name = viewModel.church?.name { items.append(name) }
        if let urlString = viewModel.church?.websiteURL, let url = URL(string: urlString) {
            items.append(url)
        }
        return items.isEmpty ? ["Check out this church on AMEN"] : items
    }

    // MARK: - Content sections (white/systemBackground — no glass)

    @ViewBuilder
    private var contentSections: some View {
        VStack(spacing: 0) {
            // 1. Live Now banner
            if liveEnabled && viewModel.isLiveNow {
                liveNowBanner
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.amenSpringStandard, value: viewModel.isLiveNow)
            }

            // 2. Latest Message rail
            sermonsRail

            // 3. Upcoming Events rail
            eventsRail

            // 4. Small Groups rail
            smallGroupsRail

            // 5. Prayer Wall (vertical list)
            prayerWallSection

            // 6. Meet Our Team rail
            ministerRail

            // 7. Get Involved (volunteer 2-col grid)
            volunteerSection

            // 8. Community Highlights gallery
            highlightsGallery

            // 9. New Member CTA banner
            newMemberCTABanner

            // 10. Stats row
            statsRow

            // Bottom breathing room
            Spacer().frame(height: 48)
        }
        .background(Color(.systemBackground))
    }

    // MARK: 1 — Live Now Banner

    private var liveNowBanner: some View {
        Button {
            if let urlString = viewModel.church?.liveStreamURL,
               let url = URL(string: urlString) {
                safariURL = url
            }
        } label: {
            ZStack(alignment: .leading) {
                // Teal gradient background — NOT glass
                LinearGradient(
                    colors: [Color(hex: "0D7377"), Color(hex: "14BDAC")],
                    startPoint: .leading,
                    endPoint: .trailing
                )

                HStack(spacing: 14) {
                    // LIVE badge (Liquid Glass on colored background as per rules)
                    liveBadge

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Live Now")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                        Text("\(viewModel.liveViewerCount) watching")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.white.opacity(0.80))
                    }

                    Spacer()

                    Label("Watch Live", systemImage: "play.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.white.opacity(0.22)))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 4)
        .accessibilityLabel("Live stream. \(viewModel.liveViewerCount) watching. Tap to watch.")
    }

    /// Liquid Glass LIVE badge with pulse
    private var liveBadge: some View {
        ZStack {
            if !reduceMotion {
                Capsule(style: .continuous)
                    .fill(Color.red.opacity(0.35))
                    .frame(width: 54, height: 26)
                    .scaleEffect(pulseOpacity == 1.0 ? 1.18 : 1.0)
                    .opacity(pulseOpacity == 1.0 ? 0 : 0.6)
                    .animation(
                        .easeInOut(duration: 1.1).repeatForever(autoreverses: true),
                        value: pulseOpacity
                    )
            }

            Text("LIVE")
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background {
                    Capsule(style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            Capsule(style: .continuous)
                                .fill(Color.red.opacity(0.75))
                        }
                        .overlay {
                            Capsule(style: .continuous)
                                .strokeBorder(Color.white.opacity(0.30), lineWidth: 0.5)
                        }
                }
        }
        .onAppear {
            if !reduceMotion { pulseOpacity = 0.0 }
        }
        .accessibilityLabel("Live")
    }

    // MARK: 2 — Sermons Rail

    @ViewBuilder
    private var sermonsRail: some View {
        if viewModel.isLoadingSermons {
            sectionLoadingPlaceholder(height: 200)
        } else if !viewModel.sermons.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader(title: "Latest Message", seeAllAction: nil)

                // Featured sermon (large)
                if let featured = viewModel.sermons.first {
                    SermonFeaturedCard(sermon: featured) { url in safariURL = url }
                        .padding(.horizontal, 16)
                }

                // Remaining sermons (small horizontal rail)
                if viewModel.sermons.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(viewModel.sermons.dropFirst()) { sermon in
                                SermonSmallCard(sermon: sermon) { url in safariURL = url }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
            .padding(.vertical, 20)
            .background(Color(.systemBackground))

            sectionDivider
        }
    }

    // MARK: 3 — Events Rail

    @ViewBuilder
    private var eventsRail: some View {
        let churchName = viewModel.church?.name ?? "Church"
        if viewModel.isLoadingEvents {
            sectionLoadingPlaceholder(height: 160)
        } else if !viewModel.events.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader(title: "Upcoming at \(churchName)", seeAllAction: nil)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(viewModel.events) { event in
                            ChurchEventCard(event: event) { url in safariURL = url }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.vertical, 20)
            .background(Color(.systemBackground))

            sectionDivider
        }
    }

    // MARK: 4 — Small Groups Rail

    @ViewBuilder
    private var smallGroupsRail: some View {
        if viewModel.isLoadingGroups {
            sectionLoadingPlaceholder(height: 160)
        } else if !viewModel.smallGroups.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader(title: "Small Groups", seeAllAction: nil)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(viewModel.smallGroups) { group in
                            ChurchSmallGroupCard(group: group)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.vertical, 20)
            .background(Color(.systemBackground))

            sectionDivider
        }
    }

    // MARK: 5 — Prayer Wall (vertical list)

    @ViewBuilder
    private var prayerWallSection: some View {
        if viewModel.isLoadingPrayers {
            sectionLoadingPlaceholder(height: 160)
        } else if !viewModel.prayerWallPreviews.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader(title: "Prayer Wall", seeAllAction: nil)

                VStack(spacing: 10) {
                    ForEach(viewModel.prayerWallPreviews.prefix(3)) { prayer in
                        PrayerPreviewCard(prayer: prayer)
                    }
                }
                .padding(.horizontal, 16)

                Button {
                    // Prayer wall deep-link — routed through existing prayer infrastructure
                } label: {
                    Text("View All Prayers \u{2192}")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.amenBlue)
                }
                .padding(.horizontal, 16)
                .accessibilityLabel("View all prayers")
            }
            .padding(.vertical, 20)
            .background(Color(.systemBackground))

            sectionDivider
        }
    }

    // MARK: 6 — Meet Our Team Rail

    @ViewBuilder
    private var ministerRail: some View {
        if viewModel.isLoadingMinisters {
            sectionLoadingPlaceholder(height: 120)
        } else if !viewModel.ministers.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader(title: "Meet Our Team", seeAllAction: nil)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(viewModel.ministers) { minister in
                            MinisterCircleCard(minister: minister)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.vertical, 20)
            .background(Color(.systemBackground))

            sectionDivider
        }
    }

    // MARK: 7 — Volunteer Grid

    @ViewBuilder
    private var volunteerSection: some View {
        if viewModel.isLoadingVolunteer {
            sectionLoadingPlaceholder(height: 160)
        } else if !viewModel.volunteerOpps.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader(title: "Get Involved", seeAllAction: nil)

                let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(viewModel.volunteerOpps) { opp in
                        VolunteerCard(opportunity: opp)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.vertical, 20)
            .background(Color(.systemBackground))

            sectionDivider
        }
    }

    // MARK: 8 — Community Highlights Gallery

    @ViewBuilder
    private var highlightsGallery: some View {
        if viewModel.isLoadingHighlights {
            sectionLoadingPlaceholder(height: 160)
        } else if !viewModel.communityHighlights.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader(title: "Community Highlights", seeAllAction: nil)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(viewModel.communityHighlights) { highlight in
                            HighlightCard(highlight: highlight)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.vertical, 20)
            .background(Color(.systemBackground))

            sectionDivider
        }
    }

    // MARK: 9 — New Member CTA Banner

    @ViewBuilder
    private var newMemberCTABanner: some View {
        if let church = viewModel.church {
            Button {
                if let urlString = church.websiteURL, let url = URL(string: urlString) {
                    safariURL = url
                }
            } label: {
                HStack(spacing: 16) {
                    // Church logo or default icon
                    Group {
                        if let logoStr = church.logoURL, let url = URL(string: logoStr) {
                            CachedAsyncImage(url: url, size: CGSize(width: 100, height: 100)) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Color(.secondarySystemBackground)
                            }
                        } else {
                            ZStack {
                                Color(.secondarySystemBackground)
                                Image(systemName: "building.columns.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(Color(.secondaryLabel))
                            }
                        }
                    }
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("New to \(church.name)?")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color(.label))
                        Text("Start here \u{2192}")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.amenBlue)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(.tertiaryLabel))
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                        .shadow(color: AmenTheme.Colors.shadowCard, radius: 8, x: 0, y: 2)
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
            .accessibilityLabel("New to \(church.name)? Start here.")
        }
    }

    // MARK: 10 — Stats Row

    @ViewBuilder
    private var statsRow: some View {
        if let church = viewModel.church {
            let eventsThisMonth = viewModel.events.filter {
                Calendar.current.isDate($0.startDate, equalTo: Date(), toGranularity: .month)
            }.count

            HStack(spacing: 0) {
                statCell(
                    value: shortNumber(church.memberCount),
                    label: "Members"
                )
                Divider().frame(height: 36)
                statCell(
                    value: "\(viewModel.smallGroups.count)",
                    label: "Small Groups"
                )
                Divider().frame(height: 36)
                statCell(
                    value: "\(eventsThisMonth)",
                    label: "Events This Month"
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "\(shortNumber(church.memberCount)) members, " +
                "\(viewModel.smallGroups.count) small groups, " +
                "\(eventsThisMonth) events this month"
            )
        }
    }

    private func statCell(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color(.label))
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Color(.secondaryLabel))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Section header

    private func sectionHeader(title: String, seeAllAction: (() -> Void)?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color(.label))

            Spacer()

            if let action = seeAllAction {
                Button("See All", action: action)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.amenBlue)
                    .accessibilityLabel("See all \(title)")
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Helpers

    private var sectionDivider: some View {
        Divider()
            .background(AmenTheme.Colors.separatorSubtle)
            .padding(.horizontal, 16)
    }

    private func sectionLoadingPlaceholder(height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(AmenTheme.Colors.shimmerBase)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .amenSkeleton()
            .accessibilityHidden(true)
    }

    private func shortNumber(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000     { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }

    private func openDirections(location: String) {
        let encoded = location.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "maps://?q=\(encoded)") {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Sermon Featured Card (300x180 pt)

private struct SermonFeaturedCard: View {
    let sermon: ChurchSermon
    let onTap: (URL) -> Void

    var body: some View {
        Button {
            if let urlString = sermon.videoURL, let url = URL(string: urlString) {
                onTap(url)
            }
        } label: {
            ZStack(alignment: .bottomLeading) {
                // Thumbnail
                Group {
                    if let urlString = sermon.thumbnailURL, let url = URL(string: urlString) {
                        CachedAsyncImage(url: url, size: CGSize(width: 600, height: 360)) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Color(.secondarySystemBackground)
                                .overlay(
                                    Image(systemName: "play.rectangle.fill")
                                        .font(.system(size: 36))
                                        .foregroundStyle(Color(.tertiaryLabel))
                                )
                        }
                    } else {
                        Color(.secondarySystemBackground)
                            .overlay(
                                Image(systemName: "play.rectangle.fill")
                                    .font(.system(size: 36))
                                    .foregroundStyle(Color(.tertiaryLabel))
                            )
                    }
                }
                .frame(width: .infinity, height: 180)
                .clipped()

                // Gradient scrim
                LinearGradient(
                    colors: [Color.clear, Color(.systemBackground).opacity(0.72)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 2) {
                    if let series = sermon.series {
                        Text(series.uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .kerning(0.8)
                            .foregroundStyle(Color.accentColor)
                    }
                    Text(sermon.title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Text(sermon.speakerName)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.72))
                }
                .padding(14)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 180)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: AmenTheme.Colors.shadowCard, radius: 8, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(sermon.title) by \(sermon.speakerName). Tap to watch.")
    }
}

// MARK: - Sermon Small Card (160x110 pt)

private struct SermonSmallCard: View {
    let sermon: ChurchSermon
    let onTap: (URL) -> Void

    var body: some View {
        Button {
            if let urlString = sermon.videoURL, let url = URL(string: urlString) {
                onTap(url)
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .bottomLeading) {
                    Group {
                        if let urlString = sermon.thumbnailURL, let url = URL(string: urlString) {
                            CachedAsyncImage(url: url, size: CGSize(width: 320, height: 220)) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Color(.secondarySystemBackground)
                            }
                        } else {
                            Color(.secondarySystemBackground)
                                .overlay(
                                    Image(systemName: "play.rectangle")
                                        .font(.system(size: 18))
                                        .foregroundStyle(Color(.tertiaryLabel))
                                )
                        }
                    }
                    .frame(width: 160, height: 90)
                    .clipped()

                    // Duration badge
                    Text(durationLabel)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color(.secondarySystemBackground).opacity(0.82)))
                        .padding(6)
                }

                Text(sermon.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(.label))
                    .lineLimit(2)
                    .frame(width: 160, alignment: .leading)
            }
            .frame(width: 160)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(color: AmenTheme.Colors.shadowCard, radius: 6, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(sermon.title), \(durationLabel)")
    }

    private var durationLabel: String {
        let mins = sermon.durationSeconds / 60
        return "\(mins) min"
    }
}

// MARK: - Event Card (160x120 pt)

private struct ChurchEventCard: View {
    let event: ChurchEvent
    let onTap: (URL) -> Void

    var body: some View {
        Button {
            if let urlString = event.rsvpURL, let url = URL(string: urlString) {
                onTap(url)
            }
        } label: {
            ZStack(alignment: .topLeading) {
                // Background image or gradient
                Group {
                    if let urlString = event.imageURL, let url = URL(string: urlString) {
                        CachedAsyncImage(url: url, size: CGSize(width: 320, height: 240)) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Color(.secondarySystemBackground)
                        }
                    } else {
                        Color(.secondarySystemBackground)
                    }
                }
                .frame(width: 160, height: 120)
                .clipped()

                // Date badge (top-leading corner)
                VStack(spacing: 0) {
                    Text(dayString)
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(Color(.label))
                    Text(monthString.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color(.secondaryLabel))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color(.systemGroupedBackground).opacity(0.90)))
                .padding(8)

                // Bottom overlay with title + RSVP count
                VStack {
                    Spacer()
                    LinearGradient(
                        colors: [Color.clear, Color(.systemBackground).opacity(0.68)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                    .frame(height: 60)
                    .overlay(alignment: .bottomLeading) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            if event.attendeeCount > 0 {
                                Text("\(event.attendeeCount) going")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color.white.opacity(0.75))
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.bottom, 8)
                    }
                }
            }
            .frame(width: 160, height: 120)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: AmenTheme.Colors.shadowCard, radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(event.title), \(dayString) \(monthString). \(event.attendeeCount) attending.")
    }

    private var dayString: String {
        let f = DateFormatter(); f.dateFormat = "d"; return f.string(from: event.startDate)
    }
    private var monthString: String {
        let f = DateFormatter(); f.dateFormat = "MMM"; return f.string(from: event.startDate)
    }
}

// MARK: - Small Group Card (160x120 pt)

private struct ChurchSmallGroupCard: View {
    let group: ChurchSmallGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Image or fallback
            Group {
                if let urlString = group.imageURL, let url = URL(string: urlString) {
                    CachedAsyncImage(url: url, size: CGSize(width: 320, height: 180)) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Color(.secondarySystemBackground)
                        .overlay(
                            Image(systemName: "person.3.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(Color(.tertiaryLabel))
                        )
                    }
                } else {
                    Color(.secondarySystemBackground)
                    .overlay(
                        Image(systemName: "person.3.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(Color(.tertiaryLabel))
                    )
                }
            }
            .frame(width: 160, height: 70)
            .clipped()

            VStack(alignment: .leading, spacing: 4) {
                Text(group.name)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color(.label))
                    .lineLimit(1)

                Text(group.meetingSchedule)
                    .font(.system(size: 10))
                    .foregroundStyle(Color(.secondaryLabel))
                    .lineLimit(1)

                Text("Join")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.amenBlue)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(width: 160, alignment: .leading)
        }
        .frame(width: 160)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: AmenTheme.Colors.shadowCard, radius: 6, x: 0, y: 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(group.name). \(group.meetingSchedule). \(group.memberCount) members.")
    }
}

// MARK: - Prayer Preview Card

private struct PrayerPreviewCard: View {
    let prayer: PrayerPreview
    @State private var hasPrayed = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(prayer.text)
                    .font(.system(size: 14))
                    .foregroundStyle(Color(.label))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 4) {
                    Image(systemName: "hands.sparkles")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.accentColor)
                    Text("\(prayer.prayerCount) \(prayer.prayerCount == 1 ? "prayer" : "prayers")")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(.secondaryLabel))

                    if prayer.anonymous {
                        Text("· Anonymous")
                            .font(.system(size: 12))
                            .foregroundStyle(Color(.tertiaryLabel))
                    }
                }
            }

            Spacer(minLength: 8)

            Button {
                withAnimation(.amenSpringBouncy) { hasPrayed = true }
            } label: {
                Text(hasPrayed ? "Prayed" : "Pray")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(hasPrayed ? Color(.secondaryLabel) : Color.amenBlue)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        Capsule(style: .continuous)
                            .fill(hasPrayed
                                  ? Color(.secondarySystemBackground)
                                  : Color.amenBlue.opacity(0.10))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(hasPrayed
                                          ? Color(.separator)
                                          : Color.amenBlue.opacity(0.30),
                                          lineWidth: 0.75)
                    )
            }
            .disabled(hasPrayed)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .shadow(color: AmenTheme.Colors.shadowCard, radius: 4, x: 0, y: 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(prayer.text). \(prayer.prayerCount) prayers.")
    }
}

// MARK: - Minister Circle Card (80 pt circle)

private struct MinisterCircleCard: View {
    let minister: ChurchMinister

    var body: some View {
        VStack(spacing: 8) {
            Group {
                if let urlString = minister.photoURL, let url = URL(string: urlString) {
                    CachedAsyncImage(url: url, size: CGSize(width: 160, height: 160)) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Circle()
                            .fill(Color(.secondarySystemBackground))
                            .overlay(
                                Image(systemName: "person.fill")
                                    .font(.system(size: 28))
                                    .foregroundStyle(Color(.secondaryLabel))
                            )
                    }
                } else {
                    Circle()
                        .fill(Color(.secondarySystemBackground))
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(Color(.secondaryLabel))
                        )
                }
            }
            .frame(width: 80, height: 80)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .strokeBorder(AmenTheme.Colors.borderSoft, lineWidth: 1)
            )

            VStack(spacing: 2) {
                Text(minister.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(.label))
                    .lineLimit(1)
                    .frame(maxWidth: 90)

                Text(minister.role)
                    .font(.system(size: 10))
                    .foregroundStyle(Color(.secondaryLabel))
                    .lineLimit(1)
                    .frame(maxWidth: 90)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(minister.name), \(minister.role)")
    }
}

// MARK: - Volunteer Card (2-col grid)

private struct VolunteerCard: View {
    let opportunity: VolunteerOpportunity

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Image or icon
            Group {
                if let urlString = opportunity.imageURL, let url = URL(string: urlString) {
                    CachedAsyncImage(url: url, size: CGSize(width: 300, height: 200)) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Color(.secondarySystemBackground)
                            .overlay(
                                Image(systemName: "hands.clap.fill")
                                    .font(.system(size: 24))
                                    .foregroundStyle(Color.accentColor.opacity(0.6))
                            )
                    }
                } else {
                    Color(.secondarySystemBackground)
                        .overlay(
                            Image(systemName: "hands.clap.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(Color.accentColor.opacity(0.6))
                        )
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 80)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(opportunity.title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color(.label))
                    .lineLimit(2)

                Text(opportunity.ministry)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.amenPurple)

                HStack(spacing: 4) {
                    Image(systemName: "person.badge.clock.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(.tertiaryLabel))
                    Text(opportunity.commitment)
                        .font(.system(size: 10))
                        .foregroundStyle(Color(.secondaryLabel))
                }

                if opportunity.spotsRemaining > 0 {
                    Text("\(opportunity.spotsRemaining) spot\(opportunity.spotsRemaining == 1 ? "" : "s") left")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color(.label))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                } else {
                    Text("Full")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color(.secondaryLabel))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color(.secondarySystemFill)))
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
                .shadow(color: AmenTheme.Colors.shadowCard, radius: 6, x: 0, y: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(opportunity.title). \(opportunity.ministry). \(opportunity.commitment). " +
            (opportunity.spotsRemaining > 0 ? "\(opportunity.spotsRemaining) spots remaining." : "Full.")
        )
    }
}

// MARK: - Highlight Card (150x150 pt)

private struct HighlightCard: View {
    let highlight: ChurchHighlight

    var body: some View {
        ZStack(alignment: .bottom) {
            if let url = URL(string: highlight.imageURL) {
                CachedAsyncImage(url: url, size: CGSize(width: 300, height: 300)) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color(.secondarySystemBackground)
                }
            } else {
                Color(.secondarySystemBackground)
            }

            // Caption overlay
            if !highlight.caption.isEmpty {
                LinearGradient(
                    colors: [Color.clear, Color(.systemBackground).opacity(0.65)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                Text(highlight.caption)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
            }
        }
        .frame(width: 150, height: 150)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: AmenTheme.Colors.shadowCard, radius: 5, x: 0, y: 1)
        .accessibilityLabel(highlight.caption.isEmpty ? "Community highlight photo" : highlight.caption)
    }
}

// MARK: - ChurchHubSafariView (UIViewControllerRepresentable)

private struct ChurchHubSafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

// MARK: - Share sheet helper

private extension View {
    func shareSheet(isPresented: Binding<Bool>, items: [Any]) -> some View {
        self.sheet(isPresented: isPresented) {
            ShareSheetView(items: items)
                .ignoresSafeArea()
        }
    }
}

private struct ShareSheetView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
