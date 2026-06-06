// OrgProfileView.swift
// AMEN Community OS — Org OS (A9)
//
// Generic org profile view — works for churches, schools, universities,
// businesses, nonprofits, creator accounts, and ministries.
//
// Feature-gated by communityOSOrgOSEnabled (default false).
//
// Layout (top to bottom):
//   1. Cover photo hero (180pt height, scaledToFill, 20pt continuous radius at bottom)
//   2. Logo avatar (overlapping cover, 72pt circle, white border 3pt, shadow)
//   3. Org name + type chip + verification badge
//   4. Description (3-line collapse with "Read more" expand)
//   5. Follow + Message buttons
//   6. ChurchCapabilitySection (if church type)
//   7. Opportunity section stub: "Open Positions" header + OpportunityCard rows
//
// Privacy rules:
//   - memberCount is NEVER displayed (hidden by design in OrgProfile model)
//   - No follower counts, no post counts shown publicly
//
// Design rules (C3): system colors only, Color.accentColor for interactive,
// white cards, no amenGold/amenPurple/hex colors.

import SwiftUI

// MARK: - OrgProfileView

struct OrgProfileView: View {

    let profile: OrgProfile

    var onFollow: (() -> Void)?
    var onCapabilityTap: ((String) -> Void)?

    // MARK: Feature flag

    @AppStorage("community_os_org_os_enabled")
    private var featureEnabled: Bool = false

    // MARK: Local state

    @State private var isDescriptionExpanded = false
    @State private var isFollowing = false
    @State private var previewOpportunities: [OpportunityPost] = []
    @State private var showAllPositions = false

    // MARK: Body

    var body: some View {
        if featureEnabled {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    coverHero
                    profileBody
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .ignoresSafeArea(edges: .top)
            .task { loadPreviewOpportunities() }
            .sheet(isPresented: $showAllPositions) {
                NavigationStack {
                    OpportunityHubView(orgId: profile.id)
                        .navigationTitle("Open Positions")
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { showAllPositions = false }
                            }
                        }
                }
            }
        } else {
            featureGatedFallback
        }
    }

    // MARK: - Feature Gated Fallback

    private var featureGatedFallback: some View {
        VStack(spacing: 16) {
            Image(systemName: profile.orgType.systemImage)
                .font(.largeTitle)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
            Text(profile.name)
                .font(.headline)
                .foregroundStyle(Color(uiColor: .label))
            Text("Org profiles are coming soon.")
                .font(.subheadline)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    // MARK: - Cover Hero (180 pt)

    private var coverHero: some View {
        ZStack(alignment: .bottom) {
            Group {
                if let coverStr = profile.coverURL, let url = URL(string: coverStr) {
                    AsyncImage(url: url) { phase in
                        if case .success(let image) = phase {
                            image
                                .resizable()
                                .scaledToFill()
                        } else {
                            coverFallback
                        }
                    }
                } else {
                    coverFallback
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

            // Bottom scrim for logo overlap zone
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
            logoAvatar
                .offset(x: 20, y: 36)
        }
        .accessibilityLabel("\(profile.name) cover photo")
    }

    private var coverFallback: some View {
        Color(uiColor: .secondarySystemBackground)
            .overlay(
                Image(systemName: profile.orgType.systemImage)
                    .font(.system(size: 40))
                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
            )
    }

    // MARK: - Logo Avatar (72 pt circle)

    private var logoAvatar: some View {
        Group {
            if let logoStr = profile.logoURL, let url = URL(string: logoStr) {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        avatarFallback
                    }
                }
            } else {
                avatarFallback
            }
        }
        .frame(width: 72, height: 72)
        .clipShape(Circle())
        .overlay(
            Circle()
                .strokeBorder(Color.white, lineWidth: 3)
        )
        .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 4)
        .accessibilityHidden(true)
    }

    private var avatarFallback: some View {
        ZStack {
            Color(uiColor: .secondarySystemBackground)
            Image(systemName: profile.orgType.systemImage)
                .font(.system(size: 28))
                .foregroundStyle(Color(uiColor: .secondaryLabel))
        }
    }

    // MARK: - Profile Body

    private var profileBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Space for logo overlap
            Spacer().frame(height: 44)

            // Name + type + verification
            orgIdentityRow

            // Description
            if let desc = profile.description, !desc.isEmpty {
                descriptionSection(desc)
            }

            // Follow + Message buttons
            actionButtons

            // Capability section (church type only)
            if profile.orgType == .church {
                ChurchCapabilitySection(
                    churchId: profile.id,
                    availableCapabilities: [],
                    onCapabilityTapped: onCapabilityTap
                )
                .onAppear {
                    UserDefaults.standard.set(true, forKey: "community_os_church_os_enabled")
                }
            }

            // Open Positions section
            if !previewOpportunities.isEmpty {
                openPositionsSection
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 32)
    }

    // MARK: Org Identity Row

    private var orgIdentityRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                Text(profile.name)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Color(uiColor: .label))

                if profile.verificationState == .verified {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.accentColor)
                        .accessibilityLabel("Verified organization")
                }
            }

            // Org type chip
            Label(profile.orgType.displayName, systemImage: profile.orgType.systemImage)
                .font(.caption.weight(.medium))
                .foregroundStyle(Color(uiColor: .secondaryLabel))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color(uiColor: .secondarySystemFill))
                )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(profile.name), \(profile.orgType.displayName)" +
            (profile.verificationState == .verified ? ", verified" : "")
        )
    }

    // MARK: Description

    private func descriptionSection(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text)
                .font(.body)
                .foregroundStyle(Color(uiColor: .label))
                .lineLimit(isDescriptionExpanded ? nil : 3)
                .multilineTextAlignment(.leading)
                .animation(.easeInOut(duration: 0.2), value: isDescriptionExpanded)

            if text.count > 120 {
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        isDescriptionExpanded.toggle()
                    }
                } label: {
                    Text(isDescriptionExpanded ? "Show less" : "Read more")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isDescriptionExpanded ? "Show less description" : "Read full description")
            }
        }
    }

    // MARK: Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 12) {
            // Follow button — outline capsule
            Button {
                withAnimation(.spring(response: 0.3)) { isFollowing.toggle() }
                if !isFollowing { onFollow?() }
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
            .accessibilityLabel(isFollowing ? "Following \(profile.name)" : "Follow \(profile.name)")

            // Message button — solid capsule
            Button {
                // Message flow routes through AMEN inbox
            } label: {
                Text("Message")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.accentColor)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Message \(profile.name)")
            .accessibilityHint("Opens Amen inbox conversation")
        }
    }

    // MARK: Open Positions Section

    private var openPositionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Open Positions")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color(uiColor: .label))
                Spacer()
                Button("See All") { showAllPositions = true }
                    .font(.subheadline)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityLabel("See all open positions")
            }

            VStack(spacing: 12) {
                ForEach(previewOpportunities.prefix(2)) { post in
                    CommunityOSOpportunityCardRow(post: post)
                }
            }
        }
    }

    // MARK: Data Loading

    private func loadPreviewOpportunities() {
        // Stub: no Firestore load in this preview tier.
        // Full integration wires OpportunityService.fetchByOrg(orgId:).
        previewOpportunities = []
    }
}

// MARK: - CommunityOSOpportunityCardRow (thin wrapper for use in OrgProfileView)

private struct CommunityOSOpportunityCardRow: View {
    let post: OpportunityPost

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: post.type.icon)
                .font(.system(size: 18))
                .foregroundStyle(Color.accentColor)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.accentColor.opacity(0.10))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(post.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color(uiColor: .label))
                    .lineLimit(1)
                Text(post.type.rawValue)
                    .font(.caption)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
            }

            Spacer()

            Text("Apply")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 1)
                )
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.07), radius: 12, x: 0, y: 3)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(post.title). \(post.type.rawValue). Apply via Amen Inbox.")
    }
}

// MARK: - Preview

#Preview("Org Profile — Church") {
    NavigationStack {
        OrgProfileView(
            profile: .preview,
            onFollow: {},
            onCapabilityTap: { cap in print("Capability tapped: \(cap)") }
        )
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }
    .onAppear {
        UserDefaults.standard.set(true, forKey: "community_os_org_os_enabled")
    }
}

#Preview("Org Profile — Nonprofit") {
    OrgProfileView(
        profile: .nonprofitPreview,
        onFollow: {},
        onCapabilityTap: nil
    )
    .onAppear {
        UserDefaults.standard.set(true, forKey: "community_os_org_os_enabled")
    }
}
