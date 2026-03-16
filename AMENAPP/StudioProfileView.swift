// StudioProfileView.swift
// AMEN Studio — Creator Profile (Public-facing + Self view)
// Premium showcase for creator work, services, and opportunities

import SwiftUI
import FirebaseAuth

struct StudioProfileView: View {
    let userId: String
    var isOwnProfile: Bool = false

    @StateObject private var service = StudioDataService.shared
    @State private var profile: StudioProfile?
    @State private var workItems: [StudioWorkItem] = []
    @State private var services: [StudioService_] = []
    @State private var products: [StudioProduct] = []
    @State private var commissionProfile: StudioCommissionProfile?
    @State private var testimonials: [StudioTestimonial] = []
    @State private var selectedTab: StudioTab = .work
    @State private var scrollOffset: CGFloat = 0
    @State private var isLoading = true
    @State private var activeSheet: StudioProfileSheet?
    @State private var showInquiryForm = false
    @State private var showEditProfile = false

    enum StudioTab: String, CaseIterable, Identifiable {
        case work, services, shop, commissions, about
        var id: String { rawValue }
        var label: String {
            switch self {
            case .work:        return "Work"
            case .services:    return "Services"
            case .shop:        return "Shop"
            case .commissions: return "Commissions"
            case .about:       return "About"
            }
        }
        var icon: String {
            switch self {
            case .work:        return "square.grid.2x2.fill"
            case .services:    return "briefcase.fill"
            case .shop:        return "bag.fill"
            case .commissions: return "pencil.line"
            case .about:       return "person.fill"
            }
        }
    }

    enum StudioProfileSheet: Identifiable {
        case inquiry(InquiryType)
        case booking
        case editProfile
        case earnings
        var id: String {
            switch self {
            case .inquiry(let t): return "inquiry_\(t.rawValue)"
            case .booking:        return "booking"
            case .editProfile:    return "editProfile"
            case .earnings:       return "earnings"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color(.systemBackground).ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        scrollOffsetReader

                        if isLoading {
                            studioLoadingState
                        } else if let profile = profile {
                            studioHeroSection(profile)
                            studioActionBar(profile)
                            studioTabBar
                            studioTabContent(profile)
                        } else {
                            studioNotFoundState
                        }

                        Spacer(minLength: 120)
                    }
                }
                .coordinateSpace(name: "studioScroll")
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                    scrollOffset = value
                }
            }
            .navigationBarHidden(true)
            .task { await loadProfile() }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .inquiry(let type):
                    StudioInquiryView(
                        creatorId: userId,
                        creatorName: profile?.displayName ?? "",
                        inquiryType: type
                    )
                case .booking:
                    StudioBookingView(
                        creatorId: userId,
                        creatorName: profile?.displayName ?? ""
                    )
                case .editProfile:
                    StudioEditProfileView()
                case .earnings:
                    StudioEarningsDashboardView()
                }
            }
        }
    }

    // MARK: - Hero Section

    @ViewBuilder
    private func studioHeroSection(_ profile: StudioProfile) -> some View {
        ZStack(alignment: .bottomLeading) {
            // Banner
            if let bannerURL = profile.bannerURL {
                AsyncImage(url: URL(string: bannerURL)) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    studioBannerGradient(profile)
                }
                .frame(height: 180)
                .clipped()
            } else {
                studioBannerGradient(profile)
                    .frame(height: 180)
            }

            // Dark gradient overlay
            LinearGradient(
                colors: [.clear, .black.opacity(0.45)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 180)

            // Verified badge
            if profile.isVerified, let badgeIcon = profile.verifiedAs.badge {
                HStack(spacing: 4) {
                    Image(systemName: badgeIcon)
                        .font(.system(size: 12, weight: .semibold))
                    Text(profile.verifiedAs.label)
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(16)
            }
        }
        .overlay(alignment: .bottomLeading) {
            // Avatar
            avatarView(profile)
                .offset(x: 16, y: 40)
        }
        .padding(.bottom, 48)

        // Creator info
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(profile.displayName)
                    .font(.custom("OpenSans-Bold", size: 22))
                    .foregroundStyle(.primary)

                if profile.isVerified {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color(red: 0.15, green: 0.45, blue: 0.90))
                }
            }

            if !profile.handle.isEmpty {
                Text("@\(profile.handle)")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
            }

            if !profile.tagline.isEmpty {
                Text(profile.tagline)
                    .font(.custom("OpenSans-SemiBold", size: 15))
                    .foregroundStyle(.primary)
                    .padding(.top, 2)
            }

            // Categories
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(profile.categories.prefix(4), id: \.self) { cat in
                        StudioCategoryChip(category: cat)
                    }
                    if profile.isOpenForWork {
                        openForWorkBadge
                    }
                    if profile.isOpenForCommissions {
                        commissionsBadge
                    }
                }
                .padding(.horizontal, 1)
            }
            .padding(.top, 6)

            // Location
            if profile.locationVisible, let location = profile.location, !location.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text(location)
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    @ViewBuilder
    private func avatarView(_ profile: StudioProfile) -> some View {
        Group {
            if let url = profile.avatarURL, let imageURL = URL(string: url) {
                AsyncImage(url: imageURL) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    initialsAvatar(profile.displayName)
                }
            } else {
                initialsAvatar(profile.displayName)
            }
        }
        .frame(width: 80, height: 80)
        .clipShape(Circle())
        .overlay(Circle().stroke(.white, lineWidth: 3))
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
    }

    @ViewBuilder
    private func initialsAvatar(_ name: String) -> some View {
        Circle()
            .fill(Color(red: 0.15, green: 0.45, blue: 0.90))
            .overlay(
                Text(initials(from: name))
                    .font(.custom("OpenSans-Bold", size: 22))
                    .foregroundStyle(.white)
            )
    }

    @ViewBuilder
    private func studioBannerGradient(_ profile: StudioProfile) -> some View {
        let color = studioColorFromHex(profile.bannerColor)
        LinearGradient(
            colors: [color, color.opacity(0.7)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Action Bar

    @ViewBuilder
    private func studioActionBar(_ profile: StudioProfile) -> some View {
        HStack(spacing: 10) {
            if isOwnProfile {
                // Edit profile
                Button {
                    activeSheet = .editProfile
                } label: {
                    Label("Edit Studio", systemImage: "pencil")
                        .font(.custom("OpenSans-SemiBold", size: 14))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.liquidGlass)

                // Earnings
                Button {
                    activeSheet = .earnings
                } label: {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 40)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.liquidGlass)
            } else {
                // Inquiry CTA
                Button {
                    activeSheet = .inquiry(.general)
                } label: {
                    Label("Inquire", systemImage: "envelope.fill")
                        .font(.custom("OpenSans-SemiBold", size: 14))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Color(red: 0.15, green: 0.45, blue: 0.90), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.liquidGlass)

                // Booking CTA (if open for work)
                if profile.isOpenForWork || profile.isOpenForCommissions {
                    Button {
                        activeSheet = .booking
                    } label: {
                        Image(systemName: "calendar.badge.plus")
                            .font(.system(size: 16))
                            .foregroundStyle(.primary)
                            .frame(width: 44, height: 40)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.liquidGlass)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    // MARK: - Tab Bar

    @ViewBuilder
    private var studioTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(StudioTab.allCases) { tab in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            selectedTab = tab
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 12, weight: .semibold))
                            Text(tab.label)
                                .font(.custom("OpenSans-SemiBold", size: 13))
                        }
                        .foregroundStyle(selectedTab == tab ? .white : .secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            selectedTab == tab
                                ? Color(red: 0.15, green: 0.45, blue: 0.90)
                                : Color.clear,
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.pillTab)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(.ultraThinMaterial)
        .padding(.top, 16)
    }

    // MARK: - Tab Content

    @ViewBuilder
    private func studioTabContent(_ profile: StudioProfile) -> some View {
        switch selectedTab {
        case .work:
            StudioWorkGridView(workItems: workItems, isOwnProfile: isOwnProfile)
        case .services:
            StudioServicesListView(services: services, creatorId: userId, isOwnProfile: isOwnProfile)
        case .shop:
            StudioShopView(products: products, creatorId: userId, isOwnProfile: isOwnProfile)
        case .commissions:
            StudioCommissionsView(
                commissionProfile: commissionProfile,
                creatorId: userId,
                isOwnProfile: isOwnProfile
            )
        case .about:
            StudioAboutView(profile: profile, testimonials: testimonials, isOwnProfile: isOwnProfile)
        }
    }

    // MARK: - Supporting Views

    @ViewBuilder
    private var openForWorkBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color(red: 0.18, green: 0.62, blue: 0.36))
                .frame(width: 7, height: 7)
            Text("Available for Work")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(red: 0.18, green: 0.62, blue: 0.36))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(red: 0.18, green: 0.62, blue: 0.36).opacity(0.12), in: Capsule())
    }

    @ViewBuilder
    private var commissionsBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "pencil.line")
                .font(.system(size: 10, weight: .semibold))
            Text("Open Commissions")
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(Color(red: 0.55, green: 0.25, blue: 0.88))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(red: 0.55, green: 0.25, blue: 0.88).opacity(0.12), in: Capsule())
    }

    @ViewBuilder
    private var scrollOffsetReader: some View {
        GeometryReader { geo in
            Color.clear.preference(
                key: ScrollOffsetPreferenceKey.self,
                value: geo.frame(in: .named("studioScroll")).minY
            )
        }
        .frame(height: 0)
    }

    @ViewBuilder
    private var studioLoadingState: some View {
        VStack(spacing: 24) {
            // Banner skeleton
            RoundedRectangle(cornerRadius: 0)
                .fill(Color(.systemGray5))
                .frame(height: 180)

            // Info skeleton
            VStack(alignment: .leading, spacing: 10) {
                RoundedRectangle(cornerRadius: 6).fill(Color(.systemGray5)).frame(width: 180, height: 22)
                RoundedRectangle(cornerRadius: 6).fill(Color(.systemGray5)).frame(width: 120, height: 16)
                RoundedRectangle(cornerRadius: 6).fill(Color(.systemGray5)).frame(width: 260, height: 16)
            }
            .padding(.horizontal, 16)
            .redacted(reason: .placeholder)
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var studioNotFoundState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.slash.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Studio Not Found")
                .font(.custom("OpenSans-Bold", size: 18))
            Text("This creator hasn't set up their Studio yet.")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(48)
    }

    // MARK: - Helpers

    private func loadProfile() async {
        isLoading = true
        async let profileTask = service.fetchProfile(for: userId)
        async let workTask = service.fetchWorkItems(for: userId)
        async let servicesTask = service.fetchServices(for: userId)
        async let productsTask = service.fetchProducts(for: userId)
        async let commissionTask = service.fetchCommissionProfile(for: userId)

        let (p, w, s, pr, c) = await (profileTask, workTask, servicesTask, productsTask, commissionTask)
        profile = p
        workItems = w
        services = s
        products = pr
        commissionProfile = c
        isLoading = false

        if p != nil {
            service.logView(creatorId: userId, targetId: userId, targetType: "profile", surface: "profile")
        }
    }

    private func initials(from name: String) -> String {
        let parts = name.components(separatedBy: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1)) + String(parts[1].prefix(1))
        }
        return String(name.prefix(2)).uppercased()
    }
}

// MARK: - Studio Category Chip

struct StudioCategoryChip: View {
    let category: StudioCategory

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: category.icon)
                .font(.system(size: 10, weight: .semibold))
            Text(category.label)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(category.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(category.color.opacity(0.12), in: Capsule())
    }
}

// MARK: - Studio Work Grid View

struct StudioWorkGridView: View {
    let workItems: [StudioWorkItem]
    let isOwnProfile: Bool

    @State private var selectedItem: StudioWorkItem?

    let columns = [GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if workItems.isEmpty {
                emptyWorkState
            } else {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(workItems) { item in
                        StudioWorkCell(item: item)
                            .onTapGesture { selectedItem = item }
                    }
                }
            }
        }
        .padding(.top, 2)
        .sheet(item: $selectedItem) { item in
            StudioWorkDetailView(item: item)
        }
    }

    @ViewBuilder
    private var emptyWorkState: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(isOwnProfile ? "Add your first work" : "No work yet")
                .font(.custom("OpenSans-SemiBold", size: 16))
            if isOwnProfile {
                Text("Showcase your creative projects, designs, and past work.")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(48)
    }
}

// MARK: - Studio Work Cell

struct StudioWorkCell: View {
    let item: StudioWorkItem

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let firstURL = item.mediaURLs.first, let url = URL(string: firstURL) {
                AsyncImage(url: url) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(Color(.systemGray5))
                }
            } else {
                Rectangle()
                    .fill(item.category.color.opacity(0.2))
                    .overlay(
                        Image(systemName: item.category.icon)
                            .font(.system(size: 28))
                            .foregroundStyle(item.category.color)
                    )
            }

            if item.isFeatured {
                Image(systemName: "star.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.yellow)
                    .padding(6)
                    .background(.ultraThinMaterial, in: Circle())
                    .padding(6)
            }
        }
        .aspectRatio(1, contentMode: .fill)
        .clipped()
        .contentShape(Rectangle())
    }
}

// MARK: - Studio Work Detail View

struct StudioWorkDetailView: View {
    let item: StudioWorkItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Media carousel
                    if !item.mediaURLs.isEmpty {
                        TabView {
                            ForEach(item.mediaURLs, id: \.self) { urlStr in
                                AsyncImage(url: URL(string: urlStr)) { img in
                                    img.resizable().aspectRatio(contentMode: .fit)
                                } placeholder: {
                                    Rectangle().fill(Color(.systemGray5))
                                }
                            }
                        }
                        .tabViewStyle(.page)
                        .frame(height: 320)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        StudioCategoryChip(category: item.category)

                        Text(item.title)
                            .font(.custom("OpenSans-Bold", size: 22))

                        if let subtitle = item.subtitle {
                            Text(subtitle)
                                .font(.custom("OpenSans-SemiBold", size: 15))
                                .foregroundStyle(.secondary)
                        }

                        Text(item.description)
                            .font(.custom("OpenSans-Regular", size: 15))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)

                        if item.clientVisible, let clientName = item.clientName {
                            Divider()
                            HStack(spacing: 6) {
                                Image(systemName: "building.2.fill")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                                Text("Client: \(clientName)")
                                    .font(.custom("OpenSans-Regular", size: 13))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if let projectURL = item.projectURL, let url = URL(string: projectURL) {
                            Link(destination: url) {
                                HStack(spacing: 6) {
                                    Image(systemName: "link")
                                    Text("View Project")
                                }
                                .font(.custom("OpenSans-SemiBold", size: 14))
                                .foregroundStyle(Color(red: 0.15, green: 0.45, blue: 0.90))
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            .navigationTitle("Work")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.custom("OpenSans-SemiBold", size: 15))
                }
            }
        }
    }
}

// MARK: - Studio About View

struct StudioAboutView: View {
    let profile: StudioProfile
    let testimonials: [StudioTestimonial]
    let isOwnProfile: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Bio
            if !profile.bio.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    sectionHeader("About")
                    Text(profile.bio)
                        .font(.custom("OpenSans-Regular", size: 15))
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 16)
            }

            // Specialties
            if !profile.specialties.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    sectionHeader("Specialties")
                    FlowLayout(spacing: 8) {
                        ForEach(profile.specialties, id: \.self) { specialty in
                            Text(specialty)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color(.systemGray6), in: Capsule())
                        }
                    }
                }
                .padding(.horizontal, 16)
            }

            // Availability
            if profile.isOpenForWork || profile.isOpenForCommissions {
                VStack(alignment: .leading, spacing: 8) {
                    sectionHeader("Availability")
                    HStack(spacing: 12) {
                        if profile.isOpenForWork {
                            availabilityItem(icon: "briefcase.fill", label: "Available for Work", color: Color(red: 0.18, green: 0.62, blue: 0.36))
                        }
                        if profile.isOpenForCommissions {
                            availabilityItem(icon: "pencil.line", label: "Open Commissions", color: Color(red: 0.55, green: 0.25, blue: 0.88))
                        }
                    }
                    if let note = profile.availabilityNote, !note.isEmpty {
                        Text(note)
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)
            }

            // Testimonials
            if !testimonials.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    sectionHeader("Client Appreciation")
                    ForEach(testimonials) { t in
                        StudioTestimonialCard(testimonial: t)
                    }
                }
                .padding(.horizontal, 16)
            }

            // Trust info
            trustInfoSection

            Spacer(minLength: 32)
        }
        .padding(.top, 20)
    }

    @ViewBuilder
    private var trustInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("About Studio")
            VStack(alignment: .leading, spacing: 6) {
                trustRow(icon: "lock.shield.fill", text: "Inquiries are moderated for your safety")
                trustRow(icon: "hand.thumbsup.fill", text: "Transactions protected by AMEN")
                trustRow(icon: "exclamationmark.triangle", text: "Report concerns using the … menu")
            }
            .padding(14)
            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 14))
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func availabilityItem(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func trustRow(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.custom("OpenSans-Bold", size: 16))
            .foregroundStyle(.primary)
    }
}

// MARK: - Studio Testimonial Card

struct StudioTestimonialCard: View {
    let testimonial: StudioTestimonial

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Circle()
                    .fill(Color(red: 0.15, green: 0.45, blue: 0.90).opacity(0.2))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Text(String(testimonial.authorName.prefix(1)))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color(red: 0.15, green: 0.45, blue: 0.90))
                    )

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(testimonial.authorName)
                            .font(.custom("OpenSans-SemiBold", size: 14))
                        if testimonial.isVerified {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(Color(red: 0.15, green: 0.45, blue: 0.90))
                        }
                    }
                    if let role = testimonial.authorRole {
                        Text(role)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Text(testimonial.content)
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(.systemGray4).opacity(0.4), lineWidth: 0.5)
        )
    }
}

// FlowLayout is defined in FlowLayout.swift

// MARK: - Hex Color Helper

func studioColorFromHex(_ hex: String) -> Color {
    let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    var int: UInt64 = 0
    Scanner(string: h).scanHexInt64(&int)
    guard h.count == 6 else { return Color(red: 0.10, green: 0.10, blue: 0.20) }
    let r = Double((int >> 16) & 0xFF) / 255
    let g = Double((int >> 8) & 0xFF) / 255
    let b = Double(int & 0xFF) / 255
    return Color(red: r, green: g, blue: b)
}
