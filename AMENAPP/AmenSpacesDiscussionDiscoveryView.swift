import SwiftUI

struct AmenSpacesDiscoverView: View {
    var body: some View {
        AmenSpacesDiscussionDiscoveryView()
    }
}

struct AmenSpacesDiscussionDiscoveryView: View {
    @StateObject private var viewModel = AmenSpacesDiscussionDiscoveryViewModel()
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var promptTrigger = false

    var body: some View {
        NavigationStack {
            ZStack {
                AmenTheme.Colors.backgroundPrimary.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        header
                            .padding(.horizontal, 20)
                            .padding(.top, 10)

                        searchCapsule
                            .padding(.horizontal, 20)

                        AmenSpacesCategoryChips(
                            selectedCategory: $viewModel.filters.selectedCategory,
                            categories: AmenSpacesDiscussionCategory.allCases
                        )

                        AmenSpaceBannerRail(surface: .spacesHome, title: "Featured for Your Spaces")

                        if let hero = viewModel.heroItem {
                            AmenSpacesTrendingDiscussionBanner(
                                item: hero,
                                context: viewModel.accessContext,
                                onJoin: { Task { await viewModel.performPrimaryAction(for: hero) } },
                                onTap: { viewModel.previewItem = hero }
                            )
                            .padding(.horizontal, 20)
                        }

                        membershipCarousel

                        popularSection
                            .padding(.horizontal, 20)

                        nearYouSection
                            .padding(.horizontal, 20)

                        organizationSpotlights

                        liveNowSection
                            .padding(.horizontal, 20)
                    }
                    .padding(.bottom, 34)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .task {
                viewModel.start()
                promptTrigger = true
            }
            .alert("Amen Spaces", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(viewModel.errorMessage)
            }
            .sheet(item: $viewModel.previewItem) { item in
                AmenSpacesDiscussionPreviewSheet(
                    item: item,
                    context: viewModel.accessContext,
                    onJoin: { Task { await viewModel.performPrimaryAction(for: item) } }
                )
                .presentationDetents([.medium, .large])
            }
            .amenSmartPrompt(surface: .amenSpaces, trigger: $promptTrigger)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Spaces")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                Text("Discover discussions, groups, and communities.")
                    .font(.subheadline)
                    .foregroundStyle(.black.opacity(0.58))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            HStack(spacing: 10) {
                headerIcon("magnifyingglass", label: "Search Amen Spaces")
                headerIcon("line.3.horizontal.decrease.circle", label: "Filter Amen Spaces")
                Circle()
                    .fill(Color.black.opacity(0.08))
                    .frame(width: 36, height: 36)
                    .overlay(Image(systemName: "person.crop.circle.fill").foregroundStyle(.black.opacity(0.72)))
                    .accessibilityLabel("Profile")
            }
        }
    }

    private func headerIcon(_ systemName: String, label: String) -> some View {
        Button { /* TODO: implement header icon action for \(label) */ } label: {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .frame(width: 36, height: 36)
                .background(glassBackground, in: Circle())
                .overlay(Circle().strokeBorder(controlBorder, lineWidth: contrast == .increased ? 1.1 : 0.7))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var searchCapsule: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.black.opacity(0.50))

            TextField("Search discussions, groups, colleges, churches, topics", text: $viewModel.filters.searchQuery)
                .font(.body)
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            if !viewModel.filters.searchQuery.isEmpty {
                Button {
                    viewModel.filters.searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.black.opacity(0.36))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 15)
        .frame(minHeight: 48)
        .background(glassBackground, in: Capsule())
        .overlay(Capsule().strokeBorder(controlBorder, lineWidth: contrast == .increased ? 1.1 : 0.7))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var membershipCarousel: some View {
        let items = viewModel.basedOnMemberships
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Based on Your Memberships", subtitle: "Related rooms and circles you may want to join.")
                    .padding(.horizontal, 20)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(items) { item in
                            AmenSpacesMembershipCard(
                                item: item,
                                context: viewModel.accessContext,
                                onJoin: { Task { await viewModel.performPrimaryAction(for: item) } },
                                onTap: { viewModel.previewItem = item }
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 2)
                }
            }
        }
    }

    @ViewBuilder
    private var popularSection: some View {
        let items = viewModel.popularItems
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Popular Discussions This Week", subtitle: "Open conversations with active moderation and clear access rules.")
                VStack(spacing: 0) {
                    ForEach(items) { item in
                        AmenSpacesDiscussionRow(
                            item: item,
                            context: viewModel.accessContext,
                            onJoin: { Task { await viewModel.performPrimaryAction(for: item) } },
                            onTap: { viewModel.previewItem = item }
                        )
                        if item.id != items.last?.id { Divider().padding(.leading, 62) }
                    }
                }
                .background(AmenTheme.Colors.surfaceCard)
            }
        }
    }

    @ViewBuilder
    private var nearYouSection: some View {
        let items = viewModel.nearYouItems
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Open Discussions Near You", subtitle: "Approximate region only. Precise location is never shown.")
                ForEach(items.prefix(3)) { item in
                    AmenSpacesDiscussionRow(item: item, context: viewModel.accessContext, onJoin: { Task { await viewModel.performPrimaryAction(for: item) } }, onTap: { viewModel.previewItem = item })
                }
            }
        }
    }

    @ViewBuilder
    private var organizationSpotlights: some View {
        if !viewModel.organizations.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Organization Spotlights", subtitle: "Churches, colleges, universities, nonprofits, and communities.")
                    .padding(.horizontal, 20)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(viewModel.organizations) { organization in
                            AmenSpacesOrganizationSpotlight(organization: organization)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 2)
                }
            }
        }
    }

    @ViewBuilder
    private var liveNowSection: some View {
        let items = viewModel.liveItems
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Live Now", subtitle: "Active huddles, study rooms, meetings, and office hours.")
                ForEach(items.prefix(5)) { item in
                    AmenSpacesDiscussionRow(item: item, context: viewModel.accessContext, onJoin: { Task { await viewModel.performPrimaryAction(for: item) } }, onTap: { viewModel.previewItem = item })
                }
            }
        }
    }

    private func sectionHeader(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.black.opacity(0.56))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var glassBackground: some ShapeStyle {
        reduceTransparency ? AnyShapeStyle(Color.white) : AnyShapeStyle(.ultraThinMaterial)
    }

    private var controlBorder: Color {
        contrast == .increased ? Color.black.opacity(0.18) : Color.black.opacity(0.07)
    }
}

@MainActor
final class AmenSpacesDiscussionDiscoveryViewModel: ObservableObject {
    @Published var items: [AmenSpacesDiscussionDiscoveryItem] = AmenSpacesDiscussionDiscoveryService.sampleItems
    @Published var organizations: [AmenSpacesOrganizationSpotlightItem] = AmenSpacesDiscussionDiscoveryService.sampleOrganizations
    @Published var filters = AmenSpacesDiscussionFilters()
    @Published var previewItem: AmenSpacesDiscussionDiscoveryItem?
    @Published var errorMessage = ""
    @Published var showError = false

    let accessContext = AmenSpacesDiscussionAccessContext(
        isOrganizationMember: true,
        userTierIds: [],
        canAccessYouthProtected: false,
        canViewConfidential: false,
        blockedDiscussionIds: [],
        mutedDiscussionIds: []
    )

    private let service: AmenSpacesDiscussionDiscoveryServicing
    private var hasStarted = false

    init() {
        self.service = AmenSpacesDiscussionDiscoveryService()
    }

    init(service: AmenSpacesDiscussionDiscoveryServicing) {
        self.service = service
    }

    var filteredItems: [AmenSpacesDiscussionDiscoveryItem] {
        AmenSpacesDiscussionDiscoveryService.rankedDiscoveryItems(from: items, filters: filters, context: accessContext)
    }

    var heroItem: AmenSpacesDiscussionDiscoveryItem? {
        AmenSpacesDiscussionDiscoveryService.heroItem(from: filteredItems, context: accessContext)
    }

    var basedOnMemberships: [AmenSpacesDiscussionDiscoveryItem] {
        filteredItems.filter { $0.membershipStatus == .joined || $0.recommendationReason != nil }.prefixArray(8)
    }

    var popularItems: [AmenSpacesDiscussionDiscoveryItem] {
        filteredItems.filter { !$0.isLive }.prefixArray(8)
    }

    var nearYouItems: [AmenSpacesDiscussionDiscoveryItem] {
        filteredItems.filter { $0.approximateRegion != nil }
    }

    var liveItems: [AmenSpacesDiscussionDiscoveryItem] {
        filteredItems.filter(\.isLive)
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        service.startListening { [weak self] items, organizations, _ in
            guard let self else { return }
            if !items.isEmpty { self.items = items }
            if !organizations.isEmpty { self.organizations = organizations }
        } onError: { [weak self] message in
            self?.presentError(message)
        }
    }

    func performPrimaryAction(for item: AmenSpacesDiscussionDiscoveryItem) async {
        do {
            switch item.accessAction(in: accessContext) {
            case .join:
                if item.joinPolicy == .paidOnly || item.visibility == .paidMemberOnly {
                    presentError("This discussion requires member access before joining.")
                } else {
                    try await service.joinAmenSpaceDiscussion(item)
                    updateMembership(for: item.id, status: .joined)
                }
            case .request:
                try await service.requestAmenSpaceDiscussionAccess(item)
                updateMembership(for: item.id, status: .requested)
            case .joined, .open, .live, .view:
                previewItem = item
            case .unavailable:
                presentError("This discussion is not available with your current access.")
            }
        } catch {
            presentError(AmenSpacesDiscussionDiscoveryService.userSafeMessage(for: error))
        }
    }

    private func updateMembership(for id: String, status: AmenSpacesDiscussionMembershipStatus) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].membershipStatus = status
    }

    private func presentError(_ message: String) {
        errorMessage = message
        showError = true
    }
}

struct AmenSpacesCategoryChips: View {
    @Binding var selectedCategory: AmenSpacesDiscussionCategory
    let categories: [AmenSpacesDiscussionCategory]
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories) { category in
                    Button {
                        selectedCategory = category
                    } label: {
                        Text(category.rawValue)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(selectedCategory == category ? .white : .black.opacity(0.72))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                            .padding(.horizontal, 15)
                            .frame(minHeight: 36)
                            .background(selectedCategory == category ? AnyShapeStyle(Color.black) : chipBackground, in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.black.opacity(contrast == .increased ? 0.16 : 0.06), lineWidth: 0.8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Category: \(category.rawValue)")
                    .accessibilityAddTraits(selectedCategory == category ? [.isSelected] : [])
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 2)
        }
    }

    private var chipBackground: AnyShapeStyle {
        reduceTransparency ? AnyShapeStyle(Color.black.opacity(0.055)) : AnyShapeStyle(.ultraThinMaterial)
    }
}

struct AmenSpacesTrendingDiscussionBanner: View {
    let item: AmenSpacesDiscussionDiscoveryItem
    let context: AmenSpacesDiscussionAccessContext
    let onJoin: () -> Void
    let onTap: () -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                bannerBackground
                    .frame(height: 282)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                VStack(alignment: .leading, spacing: 12) {
                    Text("HAPPENING NOW")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.black.opacity(0.60))

                    HStack(alignment: .bottom, spacing: 12) {
                        avatar
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.title)
                                .font(.title2.weight(.bold))
                                .foregroundStyle(AmenTheme.Colors.textPrimary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(item.preview(in: context))
                                .font(.subheadline)
                                .foregroundStyle(.black.opacity(0.68))
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                            metadataLine
                        }
                        Spacer(minLength: 4)
                        AmenSpacesJoinButton(item: item, context: context, action: onJoin)
                    }
                }
                .padding(16)
                .background(reduceTransparency ? AnyShapeStyle(Color.white.opacity(0.96)) : AnyShapeStyle(.regularMaterial), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(reduceTransparency ? 0 : 0.45), lineWidth: 0.7))
                .padding(12)
            }
        }
        .buttonStyle(.plain)
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.black.opacity(contrast == .increased ? 0.16 : 0.06), lineWidth: 0.8))
        .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Happening now. \(item.title). \(item.subtitle). \(item.accessAction(in: context).rawValue).")
    }

    private var bannerBackground: some View {
        ZStack {
            if let urlString = item.bannerImageURL, let url = URL(string: urlString) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    editorialGradient
                }
            } else {
                editorialGradient
            }
            Color.white.opacity(0.20)
        }
    }

    private var editorialGradient: some View {
        LinearGradient(
            colors: [Color(red: 0.96, green: 0.98, blue: 1.0), Color(red: 0.94, green: 0.95, blue: 0.91), Color(red: 1.0, green: 0.95, blue: 0.96)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var avatar: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.white.opacity(0.82))
            .frame(width: 44, height: 44)
            .overlay(Image(systemName: item.sourceType == .church ? "building.columns.fill" : "person.3.fill").foregroundStyle(.black.opacity(0.72)))
    }

    private var metadataLine: some View {
        HStack(spacing: 7) {
            if item.isLive { AmenSpacesMetadataPill(text: "Live", systemImage: "dot.radiowaves.left.and.right") }
            AmenSpacesMetadataPill(text: "\(item.participantCount) people", systemImage: "person.2")
            if item.isVerified { AmenSpacesMetadataPill(text: "Verified", systemImage: "checkmark.seal") }
            if item.aiSummary != nil { AmenSpacesMetadataPill(text: "AI-assisted", systemImage: "sparkles") }
        }
    }
}

struct AmenSpacesMembershipCard: View {
    let item: AmenSpacesDiscussionDiscoveryItem
    let context: AmenSpacesDiscussionAccessContext
    let onJoin: () -> Void
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black.opacity(0.055))
                    .frame(height: 104)
                    .overlay(alignment: .bottomLeading) {
                        HStack(spacing: 6) {
                            if item.isLive { AmenSpacesMetadataPill(text: "Live", systemImage: "waveform") }
                            AmenSpacesMetadataPill(text: item.unreadCount > 0 ? "\(item.unreadCount) new" : item.category.rawValue, systemImage: "bubble.left")
                        }
                        .padding(10)
                    }

                Text(item.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(item.recommendationReason(in: context) ?? item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.black.opacity(0.56))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                AmenSpacesJoinButton(item: item, context: context, action: onJoin)
            }
            .frame(width: 218, alignment: .topLeading)
            .padding(12)
            .background(AmenTheme.Colors.surfaceCard, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.8))
            .shadow(color: .black.opacity(0.045), radius: 12, y: 5)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title). \(item.subtitle). \(item.accessAction(in: context).rawValue).")
    }
}

struct AmenSpacesDiscussionRow: View {
    let item: AmenSpacesDiscussionDiscoveryItem
    let context: AmenSpacesDiscussionAccessContext
    let onJoin: () -> Void
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                avatar
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(item.safeSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.black.opacity(0.58))
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(item.sourceType.displayName)
                        Text("•")
                        Text("\(item.participantCount) participants")
                        if item.isVerified { Text("• Verified") }
                    }
                    .font(.caption)
                    .foregroundStyle(.black.opacity(0.48))
                    .lineLimit(1)
                }
                Spacer(minLength: 8)
                AmenSpacesJoinButton(item: item, context: context, action: onJoin)
            }
            .padding(.vertical, 11)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title). \(item.subtitle). \(item.participantCount) participants. \(item.accessAction(in: context).rawValue).")
    }

    private var avatar: some View {
        Circle()
            .fill(Color.black.opacity(0.06))
            .frame(width: 50, height: 50)
            .overlay(Image(systemName: iconName).font(.system(size: 20, weight: .semibold)).foregroundStyle(.black.opacity(0.66)))
    }

    private var iconName: String {
        switch item.sourceType {
        case .church: return "building.columns.fill"
        case .college, .university: return "graduationcap.fill"
        case .marketplace: return "storefront.fill"
        case .mentor: return "person.2.fill"
        case .creator: return "person.crop.rectangle.stack.fill"
        default: return "person.3.fill"
        }
    }
}

struct AmenSpacesJoinButton: View {
    let item: AmenSpacesDiscussionDiscoveryItem
    let context: AmenSpacesDiscussionAccessContext
    let action: () -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let accessAction = item.accessAction(in: context)
        Button(action: action) {
            Text(accessAction.rawValue)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(foreground(for: accessAction))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 16)
                .frame(minHeight: 34)
                .background(background(for: accessAction), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(accessAction == .unavailable)
        .accessibilityLabel("\(accessAction.rawValue) discussion: \(item.title)")
    }

    private func foreground(for action: AmenSpacesDiscussionAccessAction) -> Color {
        switch action {
        case .join, .request, .live: return .white
        case .unavailable: return .black.opacity(0.35)
        default: return .black
        }
    }

    private func background(for action: AmenSpacesDiscussionAccessAction) -> AnyShapeStyle {
        switch action {
        case .join, .request, .live:
            return AnyShapeStyle(Color.black)
        case .unavailable:
            return AnyShapeStyle(Color.black.opacity(0.06))
        default:
            return reduceTransparency ? AnyShapeStyle(Color.black.opacity(0.06)) : AnyShapeStyle(.ultraThinMaterial)
        }
    }
}

struct AmenSpacesOrganizationSpotlight: View {
    let organization: AmenSpacesOrganizationSpotlightItem
    var onView: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AmenTheme.Colors.surfaceChip)
                .frame(height: 92)
                .overlay(alignment: .bottomLeading) {
                    Circle()
                        .fill(AmenTheme.Colors.surfaceCard)
                        .frame(width: 46, height: 46)
                        .overlay(Image(systemName: "checkmark.seal.fill").foregroundStyle(organization.isVerified ? AmenTheme.Colors.textPrimary : AmenTheme.Colors.textTertiary))
                        .padding(10)
                }

            Text(organization.name)
                .font(.headline.weight(.semibold))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .lineLimit(2)

            Text(organization.subtitle)
                .font(.caption)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .lineLimit(1)

            Text("\(organization.openDiscussionCount) open discussions • \(organization.upcomingEventCount) events")
                .font(.caption2.weight(.medium))
                .foregroundStyle(AmenTheme.Colors.textTertiary)
                .lineLimit(2)

            Button(action: onView ?? {}) {
                Text("View")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .background(AmenTheme.Colors.surfaceChip, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(onView == nil)
            .accessibilityLabel("View organization: \(organization.name)")
        }
        .frame(width: 214, alignment: .topLeading)
        .padding(12)
        .background(AmenTheme.Colors.surfaceCard, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(AmenTheme.Colors.borderSoft, lineWidth: 0.8))
        .shadow(color: .black.opacity(0.045), radius: 12, y: 5)
    }
}

struct AmenSpacesMetadataPill: View {
    let text: String
    let systemImage: String
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(AmenTheme.Colors.textSecondary)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(reduceTransparency ? AnyShapeStyle(AmenTheme.Colors.surfaceChip) : AnyShapeStyle(.ultraThinMaterial), in: Capsule())
    }
}

struct AmenSpacesDiscussionPreviewSheet: View {
    let item: AmenSpacesDiscussionDiscoveryItem
    let context: AmenSpacesDiscussionAccessContext
    let onJoin: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Capsule()
                .fill(Color.black.opacity(0.18))
                .frame(width: 40, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 8) {
                Text(item.title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                Text(item.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.black.opacity(0.58))
                Text(item.preview(in: context))
                    .font(.body)
                    .foregroundStyle(.black.opacity(0.76))
                    .fixedSize(horizontal: false, vertical: true)
                if item.aiSummary != nil {
                    AmenSpacesMetadataPill(text: "AI-assisted", systemImage: "sparkles")
                }
            }

            HStack(spacing: 8) {
                AmenSpacesMetadataPill(text: "\(item.participantCount) participants", systemImage: "person.2")
                AmenSpacesMetadataPill(text: item.category.rawValue, systemImage: "tag")
                if item.isVerified { AmenSpacesMetadataPill(text: "Verified", systemImage: "checkmark.seal") }
            }

            Spacer()
            AmenSpacesJoinButton(item: item, context: context, action: onJoin)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(20)
        .background(AmenTheme.Colors.surfaceCard)
        .accessibilityElement(children: .contain)
    }
}

private extension Array {
    func prefixArray(_ maxLength: Int) -> [Element] {
        Array(prefix(maxLength))
    }
}
