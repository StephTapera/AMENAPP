// AmenOrgProfileView.swift
// AMEN Community OS — Organization OS (A9)
//
// Full org profile screen — works for churches, schools, universities,
// businesses, nonprofits, creator accounts, ministries, and studios.
//
// Reuses:
//   - OrgProfileView  (CommunityOS/Org/OrgProfileView.swift) for the hero layout pattern
//   - OrgAnnouncementBanner (CommunityOS/Org/OrgAnnouncementBanner.swift)
//   - AmenDiscussionRoomListView (CommunityOS/Discussion/AmenDiscussionRoomListView.swift)
//   - ChurchCapabilitySection (CommunityOS/Church/ChurchCapabilitySection.swift) — church type only
//   - CommunityOpportunityModels (CommunityOS/Opportunity/CommunityOpportunityModels.swift)
//
// Feature gate: AppStorage("community_os_org_os_enabled") — default false.
//
// Privacy rules (C1):
//   - memberCount NEVER displayed
//   - contactEmail and ein NEVER rendered
//   - No follower counts, no comparative metrics

import SwiftUI

// MARK: - AmenOrgProfileView

struct AmenOrgProfileView: View {

    let orgId: String

    @StateObject private var service = AmenOrganizationService()

    // MARK: Feature flag

    @AppStorage("community_os_org_os_enabled")
    private var featureEnabled: Bool = false

    // MARK: Local state

    @State private var selectedTab: Int = 0
    @State private var isFollowing: Bool = false
    @State private var showVerifiedTooltip: Bool = false

    // MARK: Body

    var body: some View {
        NavigationStack {
            if featureEnabled {
                mainContent
            } else {
                featureGatedFallback
            }
        }
    }

    // MARK: - Feature-gated fallback

    private var featureGatedFallback: some View {
        VStack(spacing: 16) {
            Image(systemName: "building.2")
                .font(.largeTitle)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
            Text("Organization profiles are coming soon.")
                .font(.subheadline)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Organization profiles feature not yet available.")
    }

    // MARK: - Main content

    private var mainContent: some View {
        Group {
            if service.isLoading && service.organization == nil {
                loadingView
            } else if let org = service.organization {
                profileBody(org: org)
            } else if let error = service.errorMessage {
                errorView(message: error)
            } else {
                loadingView
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .task { await loadOrg() }
    }

    // MARK: - Profile body

    private func profileBody(org: AmenOrganization) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                // Hero header: cover photo + logo overlay
                heroHeader(org: org)

                // Org identity + action buttons
                VStack(alignment: .leading, spacing: 16) {
                    Spacer().frame(height: 44) // logo overlap clearance

                    orgIdentityRow(org: org)

                    if !org.bio.isEmpty {
                        Text(org.bio)
                            .font(.body)
                            .foregroundStyle(Color(uiColor: .label))
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                    }

                    actionButtons(org: org)

                    // Plan-gated feature badges
                    if org.isProOrAbove {
                        proFeatureBadges(org: org)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

                // Tab bar
                tabBar
                    .padding(.top, 4)

                // Tab content
                tabContent(org: org)
                    .padding(.top, 4)
                    .padding(.bottom, 32)
            }
        }
        .ignoresSafeArea(edges: .top)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Hero Header (180pt)

    private func heroHeader(org: AmenOrganization) -> some View {
        ZStack(alignment: .bottom) {
            // Cover image
            Group {
                if let coverStr = org.coverImageUrl, let url = URL(string: coverStr) {
                    AsyncImage(url: url) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFill()
                        } else {
                            coverFallback(org: org)
                        }
                    }
                } else {
                    coverFallback(org: org)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 180)
            .clipped()
            .clipShape(
                .rect(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 20,
                    bottomTrailingRadius: 20,
                    topTrailingRadius: 0,
                    style: .continuous
                )
            )

            // Bottom scrim
            LinearGradient(
                colors: [Color.clear, Color.black.opacity(0.20)],
                startPoint: .center,
                endPoint: .bottom
            )
            .frame(height: 60)
            .allowsHitTesting(false)
        }
        .frame(height: 180)
        .overlay(alignment: .bottomLeading) {
            logoAvatar(org: org)
                .offset(x: 20, y: 36)
        }
        .accessibilityLabel("\(org.name) cover photo")
    }

    private func coverFallback(org: AmenOrganization) -> some View {
        Color(uiColor: .secondarySystemBackground)
            .overlay(
                Image(systemName: org.type.systemImage)
                    .font(.systemScaled(40))
                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
            )
    }

    private func logoAvatar(org: AmenOrganization) -> some View {
        Group {
            if let logoStr = org.logoUrl, let url = URL(string: logoStr) {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        avatarFallback(org: org)
                    }
                }
            } else {
                avatarFallback(org: org)
            }
        }
        .frame(width: 72, height: 72)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.white, lineWidth: 3))
        .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 4)
        .accessibilityHidden(true)
    }

    private func avatarFallback(org: AmenOrganization) -> some View {
        ZStack {
            Color(uiColor: .secondarySystemBackground)
            Image(systemName: org.type.systemImage)
                .font(.systemScaled(28))
                .foregroundStyle(Color(uiColor: .secondaryLabel))
        }
    }

    // MARK: - Org Identity Row

    private func orgIdentityRow(org: AmenOrganization) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                Text(org.name)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Color(uiColor: .label))

                if org.verificationStatus == .verified {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.systemScaled(18))
                        .foregroundStyle(Color.accentColor)
                        .accessibilityLabel("Verified organization")
                }
            }

            HStack(spacing: 8) {
                // Type badge
                Label(org.type.displayName, systemImage: org.type.systemImage)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color(uiColor: .secondarySystemFill))
                    )

                // Location — public, non-sensitive
                if let location = org.location, !location.isEmpty {
                    Label(location, systemImage: "mappin")
                        .font(.caption)
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                        .lineLimit(1)
                }
            }

            // Mission statement (public)
            if let mission = org.missionStatement, !mission.isEmpty {
                Text(mission)
                    .font(.subheadline)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .italic()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(org.name), \(org.type.displayName)" +
            (org.verificationStatus == .verified ? ", verified" : "") +
            (org.location.map { ", \($0)" } ?? "")
        )
    }

    // MARK: - Action Buttons

    private func actionButtons(org: AmenOrganization) -> some View {
        HStack(spacing: 12) {
            // Follow button
            Button {
                withAnimation(.spring(response: 0.3)) {
                    isFollowing.toggle()
                }
                Task {
                    // In production inject userId from auth context
                    // Stub: no-op without a live userId
                }
            } label: {
                Text(isFollowing ? "Following" : "Follow")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isFollowing ? Color(uiColor: .label) : Color.accentColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(
                        Capsule(style: .continuous)
                            .strokeBorder(
                                isFollowing ? Color(uiColor: .separator) : Color.accentColor,
                                lineWidth: 1.5
                            )
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isFollowing ? "Following \(org.name)" : "Follow \(org.name)")

            // Website link (public — safe to surface)
            if let website = org.website, let url = URL(string: website) {
                Link(destination: url) {
                    Text("Website")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.accentColor)
                        )
                }
                .accessibilityLabel("Visit \(org.name) website")
                .accessibilityHint("Opens in browser")
            }
        }
    }

    // MARK: - Pro Feature Badges

    private func proFeatureBadges(org: AmenOrganization) -> some View {
        HStack(spacing: 8) {
            if org.broadcastEnabled {
                featureBadge(icon: "antenna.radiowaves.left.and.right", label: "Broadcast")
            }
            if org.orgAssistantEnabled {
                featureBadge(icon: "brain", label: "AI Assistant")
            }
            if org.givingEnabled {
                featureBadge(icon: "gift.circle", label: "Giving")
            }
            Spacer()
        }
    }

    private func featureBadge(icon: String, label: String) -> some View {
        Label(label, systemImage: icon)
            .font(.caption2.weight(.medium))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.accentColor.opacity(0.10))
            )
            .accessibilityLabel("\(label) enabled")
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        Picker("Section", selection: $selectedTab) {
            Text("About").tag(0)
            Text("Community").tag(1)
            Text("Events").tag(2)
            Text("Opportunities").tag(3)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .accessibilityLabel("Organization sections")
    }

    // MARK: - Tab Content

    @ViewBuilder
    private func tabContent(org: AmenOrganization) -> some View {
        switch selectedTab {
        case 0:
            aboutTab(org: org)
        case 1:
            communityTab(org: org)
        case 2:
            eventsTab
        case 3:
            opportunitiesTab(org: org)
        default:
            EmptyView()
        }
    }

    // MARK: About Tab

    private func aboutTab(org: AmenOrganization) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let mission = org.missionStatement, !mission.isEmpty {
                infoCard(title: "Mission") {
                    AnyView(
                        Text(mission)
                            .font(.body)
                            .foregroundStyle(Color(uiColor: .label))
                    )
                }
            }

            if org.foundedYear != nil || org.location != nil {
                infoCard(title: "Details") {
                    AnyView(
                        VStack(alignment: .leading, spacing: 8) {
                            if let year = org.foundedYear {
                                aboutRow(icon: "calendar", label: "Founded", value: "\(year)")
                            }
                            if let location = org.location {
                                aboutRow(icon: "mappin.and.ellipse", label: "Location", value: location)
                            }
                        }
                    )
                }
            }

            // Church capability section reuse (A8 pattern)
            if org.type == .church {
                ChurchCapabilitySection(
                    churchId: org.id,
                    availableCapabilities: [],
                    onCapabilityTapped: nil
                )
                .padding(.horizontal, 16)
                .onAppear {
                    UserDefaults.standard.set(true, forKey: "community_os_church_os_enabled")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .accessibilityLabel("About \(org.name)")
    }

    private func aboutRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.systemScaled(14))
                .foregroundStyle(Color.accentColor)
                .frame(width: 20)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color(uiColor: .label))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    // MARK: Community Tab

    private func communityTab(org: AmenOrganization) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Announcements
            if !service.announcements.isEmpty {
                infoCard(title: "Announcements") {
                    AnyView(
                        VStack(spacing: 12) {
                            ForEach(service.announcements.prefix(3)) { ann in
                                OrgAnnouncementBanner(
                                    title: ann.title,
                                    announcementBody: ann.body,
                                    authorName: ann.authorId,
                                    postedAt: ann.createdAt,
                                    onExpand: nil
                                )
                            }
                        }
                    )
                }
            }

            // Discussion Rooms (A6 integration)
            VStack(alignment: .leading, spacing: 8) {
                Text("Discussion Rooms")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color(uiColor: .label))
                    .padding(.horizontal, 16)

                AmenDiscussionRoomListView(
                    contextRef: "organizations/\(org.id)"
                )
                .frame(height: 320)
            }
        }
        .padding(.top, 8)
        .task { try? await service.loadAnnouncements(orgId: org.id) }
    }

    // MARK: Events Tab

    private var eventsTab: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar")
                .font(.systemScaled(36, weight: .ultraLight))
                .foregroundStyle(Color(uiColor: .tertiaryLabel))
                .accessibilityHidden(true)
            Text("Events are coming soon.")
                .font(.callout)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Events not yet available.")
    }

    // MARK: Opportunities Tab

    private func opportunitiesTab(org: AmenOrganization) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "briefcase")
                .font(.systemScaled(36, weight: .ultraLight))
                .foregroundStyle(Color(uiColor: .tertiaryLabel))
                .accessibilityHidden(true)
            Text("Opportunities feed is coming in A10.")
                .font(.callout)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Opportunities not yet available.")
    }

    // MARK: - Info Card Container

    private func infoCard<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color(uiColor: .label))
                .accessibilityAddTraits(.isHeader)

            content()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.07), radius: 24, x: 0, y: 5)
        )
    }

    // MARK: - Loading / Error Views

    private var loadingView: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
                .tint(Color.accentColor)
            Text("Loading…")
                .font(.subheadline)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.systemScaled(36))
                .foregroundStyle(Color(uiColor: .tertiaryLabel))
                .accessibilityHidden(true)
            Text("Unable to load organization.")
                .font(.headline)
                .foregroundStyle(Color(uiColor: .label))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
                .multilineTextAlignment(.center)
            Button("Try Again") {
                Task { await loadOrg() }
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Color.accentColor)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
        .padding(.vertical, 48)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Unable to load organization. \(message)")
    }

    // MARK: - Data Loading

    private func loadOrg() async {
        do {
            try await service.fetchOrg(id: orgId)
        } catch {
            service.errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Org Profile — Church (feature ON)") {
    NavigationStack {
        AmenOrgProfileView(orgId: "org_preview_a9_01")
    }
    .onAppear {
        UserDefaults.standard.set(true, forKey: "community_os_org_os_enabled")
    }
}

#Preview("Org Profile — feature OFF") {
    AmenOrgProfileView(orgId: "org_preview_a9_01")
}
#endif
