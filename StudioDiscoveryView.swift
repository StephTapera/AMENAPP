// StudioDiscoveryView.swift
// AMEN Studio — Discovery & Marketplace Search
// Ethical, trust-ranked, transparent discovery

import SwiftUI

struct StudioDiscoveryView: View {
    @StateObject private var service = StudioDataService.shared
    @State private var searchText = ""
    @State private var selectedCategory: StudioCategory?
    @State private var discoverState: DiscoverState = .landing
    @State private var featuredCreators: [StudioProfile] = []
    @State private var featuredServices: [StudioService_] = []
    @State private var featuredProducts: [StudioProduct] = []
    @State private var openCommissions: [StudioProfile] = []
    @State private var searchResults: [StudioProfile] = []
    @State private var isSearching = false
    @State private var isLoading = true
    @State private var selectedProfile: StudioProfile?

    enum DiscoverState {
        case landing, searching, results
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar

                Group {
                    switch discoverState {
                    case .landing:
                        landingContent
                    case .searching:
                        searchingState
                    case .results:
                        searchResultsContent
                    }
                }
            }
            .navigationTitle("Studio")
            .navigationBarTitleDisplayMode(.large)
            .task { await loadDiscoveryContent() }
            .onChange(of: searchText) { _, newValue in
                handleSearchChange(newValue)
            }
            .sheet(item: $selectedProfile) { profile in
                StudioProfileView(userId: profile.userId)
            }
        }
    }

    // MARK: - Search Bar

    @ViewBuilder
    private var searchBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                TextField("Search creators, services, products...", text: $searchText)
                    .font(.custom("OpenSans-Regular", size: 15))
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            discoverState = .searching
                        }
                    }
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        discoverState = .landing
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))

            if discoverState != .landing {
                Button("Cancel") {
                    searchText = ""
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        discoverState = .landing
                    }
                }
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(Color(red: 0.15, green: 0.45, blue: 0.90))
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Landing Content

    @ViewBuilder
    private var landingContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                // Category filter chips
                categoryChipsRow

                // Featured Creators
                if !featuredCreators.isEmpty {
                    discoverySection(title: "Featured Creators", badge: nil) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 14) {
                                ForEach(featuredCreators) { creator in
                                    StudioCreatorCard(profile: creator)
                                        .onTapGesture { selectedProfile = creator }
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                }

                // Open Commissions
                if !openCommissions.isEmpty {
                    discoverySection(title: "Open Commissions", badge: "\(openCommissions.count)") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 14) {
                                ForEach(openCommissions) { creator in
                                    StudioCompactCreatorCard(profile: creator)
                                        .onTapGesture { selectedProfile = creator }
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                }

                // Featured Services
                if !featuredServices.isEmpty {
                    discoverySection(title: "Explore Services", badge: nil) {
                        LazyVStack(spacing: 10) {
                            ForEach(featuredServices) { service_ in
                                StudioServiceCard(service: service_)
                                    .padding(.horizontal, 16)
                            }
                        }
                    }
                }

                // Featured Products
                if !featuredProducts.isEmpty {
                    discoverySection(title: "Digital Resources", badge: nil) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 14) {
                                ForEach(featuredProducts) { product in
                                    StudioProductThumb(product: product)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                }

                // Transparency footer
                transparencyFooter

                Spacer(minLength: 100)
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Searching State

    @ViewBuilder
    private var searchingState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Suggestions")
                    .font(.custom("OpenSans-SemiBold", size: 14))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                ForEach(StudioCategory.allCases.prefix(8)) { cat in
                    Button {
                        searchText = cat.label
                        performSearch()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: cat.icon)
                                .font(.system(size: 16))
                                .foregroundStyle(cat.color)
                                .frame(width: 28)
                            Text(cat.label)
                                .font(.custom("OpenSans-Regular", size: 15))
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "arrow.up.left")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Search Results

    @ViewBuilder
    private var searchResultsContent: some View {
        if isSearching {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if searchResults.isEmpty {
            noResultsState
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    searchResultsHeader
                    ForEach(searchResults) { profile in
                        StudioSearchResultRow(profile: profile)
                            .onTapGesture { selectedProfile = profile }
                            .padding(.horizontal, 16)
                    }
                }
                .padding(.vertical, 8)
                Spacer(minLength: 100)
            }
        }
    }

    @ViewBuilder
    private var searchResultsHeader: some View {
        HStack {
            Text("\(searchResults.count) result\(searchResults.count == 1 ? "" : "s") for \"\(searchText)\"")
                .font(.custom("OpenSans-Regular", size: 13))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var noResultsState: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No results for \"\(searchText)\"")
                .font(.custom("OpenSans-SemiBold", size: 16))
            Text("Try a different search — categories, specialties, or creator names all work.")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Category Chips

    @ViewBuilder
    private var categoryChipsRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Browse by Category")
                .font(.custom("OpenSans-Bold", size: 16))
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // "All" chip
                    Button {
                        selectedCategory = nil
                    } label: {
                        Text("All")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(selectedCategory == nil ? .white : .secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                selectedCategory == nil
                                    ? Color(red: 0.15, green: 0.45, blue: 0.90)
                                    : Color(.systemGray5),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.pillTab)

                    ForEach(StudioCategory.allCases.prefix(12)) { cat in
                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                                selectedCategory = cat
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: cat.icon).font(.system(size: 11))
                                Text(cat.label).font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundStyle(selectedCategory == cat ? .white : cat.color)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                selectedCategory == cat
                                    ? cat.color
                                    : cat.color.opacity(0.12),
                                in: Capsule()
                            )
                        }
                        .buttonStyle(.pillTab)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Transparency Footer

    @ViewBuilder
    private var transparencyFooter: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.secondary)
                .font(.system(size: 14))
            VStack(alignment: .leading, spacing: 4) {
                Text("About Studio Discovery")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Creators are ranked by quality, trust, and relevance — not by who pays the most. Promoted placements are always clearly labeled.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
    }

    // MARK: - Section Builder

    @ViewBuilder
    private func discoverySection<Content: View>(
        title: String,
        badge: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.custom("OpenSans-Bold", size: 17))
                if let badge = badge {
                    Text(badge)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(red: 0.15, green: 0.45, blue: 0.90), in: Capsule())
                }
            }
            .padding(.horizontal, 16)
            content()
        }
    }

    // MARK: - Actions

    private func handleSearchChange(_ query: String) {
        if query.isEmpty {
            discoverState = .landing
            searchResults = []
        } else if discoverState == .landing {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                discoverState = .searching
            }
        }
    }

    private func performSearch() {
        guard !searchText.isEmpty else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            discoverState = .results
            isSearching = true
        }
        Task {
            searchResults = await service.searchCreators(query: searchText, category: selectedCategory)
            isSearching = false
        }
    }

    private func loadDiscoveryContent() async {
        async let creators = service.fetchFeaturedCreators()
        async let services_ = service.fetchFeaturedServices()
        async let commissions = service.fetchOpenCommissions()

        (featuredCreators, featuredServices, openCommissions) = await (creators, services_, commissions)
        isLoading = false
    }
}

// MARK: - Creator Card (horizontal scroll)

struct StudioCreatorCard: View {
    let profile: StudioProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Banner/avatar
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(studioColorFromHex(profile.bannerColor))
                    .frame(height: 90)

                Circle()
                    .fill(Color(red: 0.15, green: 0.45, blue: 0.90))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Text(String(profile.displayName.prefix(1)))
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                    )
                    .overlay(Circle().stroke(.white, lineWidth: 2))
                    .offset(x: 10, y: 22)
            }
            .padding(.bottom, 18)

            // Info
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(profile.displayName)
                        .font(.custom("OpenSans-SemiBold", size: 14))
                        .lineLimit(1)
                    if profile.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color(red: 0.15, green: 0.45, blue: 0.90))
                    }
                }
                Text(profile.tagline)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let firstCat = profile.categories.first {
                    StudioCategoryChip(category: firstCat)
                }
            }
        }
        .padding(12)
        .frame(width: 170)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(.systemGray4).opacity(0.35), lineWidth: 0.5)
        )
        .overlay(alignment: .topTrailing) {
            if let expiry = profile.boostExpiry, expiry > Date() {
                Text("Promoted")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color(.systemGray5), in: Capsule())
                    .padding(8)
            }
        }
    }
}

// MARK: - Compact Creator Card

struct StudioCompactCreatorCard: View {
    let profile: StudioProfile

    var body: some View {
        VStack(spacing: 8) {
            Circle()
                .fill(Color(red: 0.55, green: 0.25, blue: 0.88).opacity(0.15))
                .frame(width: 52, height: 52)
                .overlay(
                    Text(String(profile.displayName.prefix(1)))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color(red: 0.55, green: 0.25, blue: 0.88))
                )

            Text(profile.displayName)
                .font(.custom("OpenSans-SemiBold", size: 12))
                .lineLimit(1)

            HStack(spacing: 3) {
                Circle()
                    .fill(Color(red: 0.55, green: 0.25, blue: 0.88))
                    .frame(width: 5, height: 5)
                Text("Open")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(red: 0.55, green: 0.25, blue: 0.88))
            }
        }
        .padding(12)
        .frame(width: 100)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(red: 0.55, green: 0.25, blue: 0.88).opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Product Thumbnail

struct StudioProductThumb: View {
    let product: StudioProduct

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(product.category.color.opacity(0.15))
                    .frame(width: 120, height: 90)
                Image(systemName: product.category.icon)
                    .font(.system(size: 28))
                    .foregroundStyle(product.category.color)
            }

            Text(product.title)
                .font(.custom("OpenSans-SemiBold", size: 12))
                .lineLimit(2)
                .frame(width: 120, alignment: .leading)

            Text(product.isFree ? "Free" : product.price.formatted(.currency(code: product.currency)))
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(product.isFree ? Color(red: 0.18, green: 0.62, blue: 0.36) : .primary)
        }
        .padding(10)
        .frame(width: 140)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.systemGray4).opacity(0.3), lineWidth: 0.5)
        )
    }
}

// MARK: - Search Result Row

struct StudioSearchResultRow: View {
    let profile: StudioProfile

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(red: 0.15, green: 0.45, blue: 0.90).opacity(0.15))
                .frame(width: 48, height: 48)
                .overlay(
                    Text(String(profile.displayName.prefix(1)))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color(red: 0.15, green: 0.45, blue: 0.90))
                )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(profile.displayName)
                        .font(.custom("OpenSans-SemiBold", size: 15))
                    if profile.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color(red: 0.15, green: 0.45, blue: 0.90))
                    }
                }
                Text(profile.tagline)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if profile.isOpenForWork {
                        HStack(spacing: 3) {
                            Circle().fill(Color(red: 0.18, green: 0.62, blue: 0.36)).frame(width: 5, height: 5)
                            Text("For Hire").font(.system(size: 10, weight: .semibold)).foregroundStyle(Color(red: 0.18, green: 0.62, blue: 0.36))
                        }
                    }
                    if profile.isOpenForCommissions {
                        Text("Commissions Open").font(.system(size: 10, weight: .semibold)).foregroundStyle(Color(red: 0.55, green: 0.25, blue: 0.88))
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(.systemGray4).opacity(0.3), lineWidth: 0.5)
        )
    }
}
