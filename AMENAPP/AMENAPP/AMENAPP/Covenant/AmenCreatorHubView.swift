import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - Creator Hub View
// Main community page for a creator — Apple Music artist page meets Patreon hub.
// Parallax banner, sticky header info, membership CTA, stories, tab rail, tab content.

struct AmenCreatorHubView: View {
    let covenantId: String
    @EnvironmentObject var vm: AmenCovenantViewModel
    @StateObject private var hubVM = AmenCreatorHubViewModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scrollOffset: CGFloat = 0
    @State private var paywallCovenant: Covenant?

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                offsetReader

                VStack(spacing: 0) {
                    // 1. Header area (banner + avatar + name)
                    headerArea

                    // 2. Join / Membership CTA strip
                    membershipStrip
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 8)

                    // 3. Story rings
                    if !hubVM.stories.isEmpty {
                        storyRingsSection
                            .padding(.vertical, 12)
                    }

                    Divider()
                        .padding(.horizontal, 20)
                        .padding(.top, 4)

                    // 4. Tab rail
                    CovenantHubTabRail(selectedTab: $hubVM.selectedTab)
                        .padding(.top, 4)

                    // 5. Tab content
                    TabView(selection: $hubVM.selectedTab) {
                        homeTab.tag(0)
                        roomsTab.tag(1)
                        postsTab.tag(2)
                        eventsTab.tag(3)
                        aboutTab.tag(4)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(minHeight: 600)
                    .animation(reduceMotion ? .none : .spring(response: 0.38, dampingFraction: 0.82), value: hubVM.selectedTab)
                }
            }
            .coordinateSpace(name: "hubScroll")
            .ignoresSafeArea(edges: .top)
            .background(Color(uiColor: .systemGroupedBackground))
            .task { await hubVM.load(covenantId: covenantId) }
            .task {
                await vm.loadMembership(for: covenantId)
            }
            .task(id: vm.currentMembership?.id) {
                await hubVM.checkOnboarding(membership: vm.currentMembership)
            }
            .onChange(of: covenantId) { _, newId in
                Task {
                    await hubVM.load(covenantId: newId)
                    await vm.loadMembership(for: newId)
                }
            }

            // Collapsed nav chrome (appears on scroll)
            if scrollOffset < -160 {
                collapsedNavBar
                    .transition(.opacity)
            }
        }
        .sheet(isPresented: $hubVM.showPaywall) {
            if let covenant = paywallCovenant ?? hubVM.covenant {
                AmenCovenantPaywallView(covenant: covenant, context: .general)
            }
        }
        .sheet(isPresented: $hubVM.showStartHere) {
            if let covenant = hubVM.covenant {
                AmenCovenantStartHereView(covenant: covenant)
            }
        }
        .animation(reduceMotion ? .none : .easeInOut(duration: 0.2), value: scrollOffset < -160)
    }

    // MARK: - Scroll Offset Reader

    private var offsetReader: some View {
        GeometryReader { geo in
            Color.clear.preference(
                key: HubScrollOffsetKey.self,
                value: geo.frame(in: .named("hubScroll")).minY
            )
        }
        .frame(height: 0)
        .onPreferenceChange(HubScrollOffsetKey.self) { scrollOffset = $0 }
    }

    // MARK: - Collapsed Nav Bar

    private var collapsedNavBar: some View {
        HStack(spacing: 12) {
            Spacer()
            Text(hubVM.covenant?.name ?? "")
                .font(.headline)
                .lineLimit(1)
            Spacer()
        }
        .padding(.top, 56)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial)
        .overlay(Divider(), alignment: .bottom)
    }

    // MARK: - Header Area

    private var headerArea: some View {
        ZStack(alignment: .bottom) {
            // Banner image with optional parallax
            AsyncImage(url: URL(string: hubVM.covenant?.coverImageURL ?? "")) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                LinearGradient(
                    colors: [Color.purple.opacity(0.45), Color.indigo.opacity(0.45)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .frame(maxWidth: .infinity)
            .frame(height: 200)
            .clipped()
            .offset(y: reduceMotion ? 0 : max(0, scrollOffset * 0.3))

            // Blur overlay on bottom 80pt of banner
            VStack {
                Spacer()
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .frame(height: 80)
            }

            // Avatar + name row floating at bottom of banner
            HStack(alignment: .bottom, spacing: 14) {
                ZStack(alignment: .bottomTrailing) {
                    AsyncImage(url: URL(string: hubVM.covenant?.avatarURL ?? "")) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Color.purple.opacity(0.25)
                    }
                    .frame(width: 64, height: 64)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white, lineWidth: 3))
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 3)

                    // Verification badge overlay
                    if let badges = hubVM.covenant?.trustBadges, badges.contains(.verifiedCreator) {
                        AmenTrustBadge(type: .verifiedCreator, size: .compact)
                            .offset(x: 4, y: 4)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(hubVM.covenant?.name ?? " ")
                        .font(.system(size: 22, weight: .bold))
                        .lineLimit(1)
                    Text("@\(hubVM.covenant?.creatorId ?? "")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(hubVM.covenant?.tagline ?? "")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                // Member count chip
                if let count = hubVM.covenant?.memberCount, count > 0 {
                    VStack(spacing: 2) {
                        Text(formatCount(count))
                            .font(.subheadline.weight(.bold))
                        Text("members")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 14)
        }
        .frame(height: 200)
    }

    // MARK: - Membership CTA Strip

    @ViewBuilder
    private var membershipStrip: some View {
        let membership = vm.currentMembership
        let isCreator = membership?.role == .creator
        let isActiveMember = membership?.status.isActive == true

        if isCreator {
            // Creator: manage button
            Button {
                vm.navigate(to: .manage(covenantId: covenantId))
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Manage Community")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.primary)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .shadow(color: Color.black.opacity(0.06), radius: 8, y: 3)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Manage Community")

        } else if isActiveMember, let m = membership {
            // Active member badge
            HStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 18))
                VStack(alignment: .leading, spacing: 3) {
                    Text("You're a member")
                        .font(.subheadline.weight(.semibold))
                    Text(roleLabel(m.role))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                roleBadge(m.role)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.green.opacity(0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.green.opacity(0.2), lineWidth: 1)
                    )
            )
            .accessibilityLabel("You're a member. Role: \(roleLabel(m.role))")

        } else {
            // Non-member: tier pills + join button
            VStack(alignment: .leading, spacing: 10) {
                if let tiers = hubVM.covenant?.tiers, !tiers.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(tiers.prefix(3)) { tier in
                                HubTierPill(tier: tier)
                            }
                        }
                    }
                }

                Button {
                    paywallCovenant = hubVM.covenant
                    hubVM.handleJoin()
                } label: {
                    HStack {
                        Text("Join This Community")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Image(systemName: "arrow.right.circle.fill")
                    }
                    .foregroundStyle(.white)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.purple)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Join this community")
            }
        }
    }

    private func roleLabel(_ role: CovenantMembership.MemberRole) -> String {
        switch role {
        case .member:    return "Member"
        case .moderator: return "Moderator"
        case .admin:     return "Admin"
        case .creator:   return "Creator"
        }
    }

    @ViewBuilder
    private func roleBadge(_ role: CovenantMembership.MemberRole) -> some View {
        let (label, color): (String, Color) = {
            switch role {
            case .member:    return ("Member", Color.gray)
            case .moderator: return ("Mod", Color.teal)
            case .admin:     return ("Admin", Color.orange)
            case .creator:   return ("Creator", Color.purple)
            }
        }()
        Text(label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(color.opacity(0.12)))
    }

    // MARK: - Story Rings Section

    private var storyRingsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(hubVM.stories.prefix(8)) { story in
                    HubStoryRing(story: story)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Home Tab

    private var homeTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Featured post card
            if let covenant = hubVM.covenant {
                HubFeaturedPostCard(covenant: covenant)
                    .padding(.horizontal, 20)
            }

            // Daily digest preview
            HubDigestCard()
                .padding(.horizontal, 20)

            // Prayer follow-up strip
            HubPrayerFollowUpStrip()
                .padding(.horizontal, 20)

            Spacer(minLength: 40)
        }
        .padding(.top, 20)
    }

    // MARK: - Rooms Tab

    private var roomsTab: some View {
        AmenCovenantRoomsView(covenantId: covenantId)
            .padding(.top, 8)
    }

    // MARK: - Posts Tab

    private var postsTab: some View {
        LazyVStack(spacing: 12) {
            ForEach(HubPostPlaceholder.seeds(covenantId: covenantId)) { post in
                Button {
                    vm.navigate(to: .post(covenantId: covenantId, postId: post.id))
                } label: {
                    HubPostRow(post: post)
                        .padding(.horizontal, 20)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 40)
        }
        .padding(.top, 16)
    }

    // MARK: - Events Tab

    private var eventsTab: some View {
        AmenCovenantEventsView(covenantId: covenantId)
            .padding(.top, 8)
    }

    // MARK: - About Tab

    private var aboutTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Description
            if let desc = hubVM.covenant?.description, !desc.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("About")
                        .font(.headline)
                    Text(desc)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                )
            }

            // Community rules
            VStack(alignment: .leading, spacing: 8) {
                Text("Community Rules")
                    .font(.headline)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(defaultCommunityRules.enumerated()), id: \.offset) { i, rule in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(i + 1)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(width: 20, height: 20)
                                .background(Circle().fill(Color.purple))
                                .padding(.top, 1)
                            Text(rule)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        if i < defaultCommunityRules.count - 1 {
                            Divider().padding(.leading, 46)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                )
            }

            // Tier comparison table
            if let tiers = hubVM.covenant?.tiers, !tiers.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Membership Tiers")
                        .font(.headline)
                    VStack(spacing: 10) {
                        ForEach(tiers) { tier in
                            AboutTierRow(tier: tier)
                        }
                    }
                }
            }

            Spacer(minLength: 40)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    private let defaultCommunityRules = [
        "Treat every member with dignity and respect.",
        "No spam or self-promotion without moderator permission.",
        "Keep discussions spiritually constructive.",
        "Respect theological diversity within the Christian faith.",
        "Financial manipulation or pressure is not tolerated.",
        "Maintain confidentiality for prayer requests shared here."
    ]

    // MARK: - Helpers

    private func formatCount(_ count: Int) -> String {
        count >= 1_000 ? String(format: "%.1fk", Double(count) / 1_000) : "\(count)"
    }
}

// MARK: - Scroll Offset Preference Key

private struct HubScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Covenant Hub Tab Rail

private struct CovenantHubTabRail: View {
    @Binding var selectedTab: Int
    private let tabs = ["Home", "Rooms", "Posts", "Events", "About"]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(Array(tabs.enumerated()), id: \.offset) { index, tab in
                    Button {
                        selectedTab = index
                    } label: {
                        VStack(spacing: 6) {
                            Text(tab)
                                .font(.subheadline.weight(selectedTab == index ? .semibold : .regular))
                                .foregroundStyle(selectedTab == index ? .primary : .secondary)
                                .padding(.horizontal, 16)
                                .padding(.top, 10)

                            Rectangle()
                                .fill(selectedTab == index ? Color.purple : Color.clear)
                                .frame(height: 2)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedTab == index ? .isSelected : [])
                }
            }
            .padding(.horizontal, 8)
        }
    }
}

// MARK: - Hub Story Ring

private struct HubStoryRing: View {
    let story: AmenCreatorHubViewModel.HubStoryItem

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(
                        story.isUnread
                            ? LinearGradient(colors: [.purple, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(colors: [Color.gray.opacity(0.3), Color.gray.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 2
                    )
                    .frame(width: 56, height: 56)

                Text(story.creatorInitial)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(Color.purple.opacity(story.isUnread ? 0.7 : 0.3)))
            }

            Text("Story")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityLabel("\(story.creatorInitial) story\(story.isUnread ? ", unread" : "")")
    }
}

// MARK: - Hub Tier Pill

private struct HubTierPill: View {
    let tier: CovenantTier

    var body: some View {
        HStack(spacing: 5) {
            if tier.isPopular {
                Image(systemName: "star.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.yellow)
            }
            Text(tier.name)
                .font(.caption.weight(.medium))
            Text(formattedPrice(tier))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(tier.isPopular ? Color.purple.opacity(0.1) : Color(uiColor: .secondarySystemGroupedBackground))
                .overlay(
                    Capsule().stroke(tier.isPopular ? Color.purple.opacity(0.3) : Color.clear, lineWidth: 1)
                )
        )
        .accessibilityLabel("\(tier.name), \(formattedPrice(tier))")
    }

    private func formattedPrice(_ tier: CovenantTier) -> String {
        if tier.price == 0 { return "Free" }
        let fmt = NumberFormatter()
        fmt.numberStyle = .currency
        fmt.currencyCode = tier.currency
        fmt.maximumFractionDigits = 0
        let s = fmt.string(from: NSNumber(value: tier.price)) ?? "\(Int(tier.price))"
        return "\(s)\(tier.billingPeriod.displayLabel)"
    }
}

// MARK: - Hub Featured Post Card

private struct HubFeaturedPostCard: View {
    let covenant: Covenant

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Teaching")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.indigo)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.indigo.opacity(0.1)))

                Spacer()

                Image(systemName: "arrow.right.circle")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }

            Text("Walking in the Spirit: A Community Study")
                .font(.headline)
                .lineLimit(2)

            Text("An in-depth look at Galatians 5 and what it means to yield to the Holy Spirit in daily life…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            HStack(spacing: 6) {
                Image(systemName: "book.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.purple)
                Text("Galatians 5:16-25")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.purple)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.purple.opacity(0.08)))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(0.08), radius: 14, y: 6)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Featured post: Walking in the Spirit")
    }
}

// MARK: - Hub Digest Card

private struct HubDigestCard: View {
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "newspaper.fill")
                .font(.system(size: 22))
                .foregroundStyle(.purple)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.purple.opacity(0.1)))

            VStack(alignment: .leading, spacing: 4) {
                Text("Today's Digest")
                    .font(.subheadline.weight(.semibold))
                Text("3 posts · 2 prayer updates · 1 event")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("Read")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.purple)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Today's Digest: 3 posts, 2 prayer updates, 1 event")
    }
}

// MARK: - Hub Prayer Follow-Up Strip

private struct HubPrayerFollowUpStrip: View {
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "hands.sparkles.fill")
                .font(.system(size: 18))
                .foregroundStyle(.indigo)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.indigo.opacity(0.1)))

            VStack(alignment: .leading, spacing: 3) {
                Text("Prayer Requests")
                    .font(.subheadline.weight(.semibold))
                Text("Tap to pray with this community")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.indigo.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.indigo.opacity(0.15), lineWidth: 1)
                )
        )
        .accessibilityLabel("Prayer Requests. Tap to pray with this community.")
    }
}

// MARK: - Hub Post Row

private struct HubPostRow: View {
    let post: HubPostPlaceholder

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(post.postType)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.purple)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.purple.opacity(0.1)))

                Spacer()

                Text(post.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Text(post.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)

            Text(post.excerpt)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 4) {
                Image(systemName: "eye")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Text("\(post.readCount) reads")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(post.title), \(post.postType), \(post.readCount) reads")
    }
}

// MARK: - About Tier Row

private struct AboutTierRow: View {
    let tier: CovenantTier

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(tier.name)
                        .font(.subheadline.weight(.semibold))
                    if tier.isPopular {
                        Text("Popular")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.purple))
                    }
                }
                Text(tier.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if !tier.perks.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(tier.perks.prefix(3), id: \.self) { perk in
                            Label(perk, systemImage: "checkmark")
                                .font(.caption2)
                                .foregroundStyle(.green)
                        }
                    }
                    .padding(.top, 2)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(formattedPriceDisplay(tier))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.purple)
                Text(tier.billingPeriod.displayLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    private func formattedPriceDisplay(_ tier: CovenantTier) -> String {
        if tier.price == 0 { return "Free" }
        let fmt = NumberFormatter()
        fmt.numberStyle = .currency
        fmt.currencyCode = tier.currency
        fmt.maximumFractionDigits = 0
        return fmt.string(from: NSNumber(value: tier.price)) ?? "\(Int(tier.price))"
    }
}

// MARK: - Hub Post Placeholder

struct HubPostPlaceholder: Identifiable {
    let id: String
    let title: String
    let excerpt: String
    let postType: String
    let createdAt: Date
    let readCount: Int
    let covenantId: String

    static func seeds(covenantId: String) -> [HubPostPlaceholder] {
        [
            .init(id: "1", title: "Why the Psalms Belong in Your Morning", excerpt: "A look at how the ancient prayer book of Israel can reshape how you begin each day.", postType: "Devotional", createdAt: Date().addingTimeInterval(-86400), readCount: 312, covenantId: covenantId),
            .init(id: "2", title: "Community Q&A: Spiritual Dryness", excerpt: "Your questions answered on navigating seasons when faith feels distant.", postType: "Q&A", createdAt: Date().addingTimeInterval(-172800), readCount: 198, covenantId: covenantId),
            .init(id: "3", title: "New Study Drop: Hebrews 11", excerpt: "We're going verse by verse through the Hall of Faith. Week 1 starts now.", postType: "Study", createdAt: Date().addingTimeInterval(-259200), readCount: 441, covenantId: covenantId),
        ]
    }
}

// MARK: - Creator Hub View Model

@MainActor
final class AmenCreatorHubViewModel: ObservableObject {
    @Published var covenant: Covenant?
    @Published var isLoading: Bool = false
    @Published var selectedTab: Int = 0
    @Published var showPaywall: Bool = false
    @Published var showStartHere: Bool = false
    @Published var stories: [HubStoryItem] = []

    struct HubStoryItem: Identifiable {
        let id: String
        let creatorInitial: String
        let isUnread: Bool
    }

    private let db = Firestore.firestore()

    func load(covenantId: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let doc = try await db.collection("covenants").document(covenantId).getDocument()
            covenant = try? doc.data(as: Covenant.self)

            // Seed placeholder stories using creator name initial
            let initial = covenant?.name.first.map(String.init) ?? "C"
            stories = (0..<6).map { i in
                HubStoryItem(id: "\(covenantId)-story-\(i)", creatorInitial: initial, isUnread: i < 3)
            }
        } catch {
            // Non-fatal: covenant stays nil, view shows skeleton
        }
    }

    func handleJoin() {
        showPaywall = true
    }

    func checkOnboarding(membership: CovenantMembership?) async {
        guard let membership, membership.status.isActive else { return }
        let joinedDate = membership.joinedAt.dateValue()
        let hoursSinceJoin = Date().timeIntervalSince(joinedDate) / 3600
        if hoursSinceJoin < 48 {
            showStartHere = true
        }
    }
}
