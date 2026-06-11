// AmenOrgDiscoveryView.swift
// AMEN Community OS — Organization OS (A9)
//
// Discovery surface for browsing and searching all org types:
//   churches, schools, universities, businesses, nonprofits, teams,
//   creators, ministries, and studios.
//
// Reuses:
//   - OrgType (CommunityOS/Org/OrgProfileModels.swift)
//   - AmenOrganizationService (CommunityOS/Organization/AmenOrganizationService.swift)
//   - AmenOrgProfileView (CommunityOS/Organization/AmenOrgProfileView.swift)
//
// Privacy rules (C1):
//   - memberCount NEVER shown on org cards or in any public discovery surface
//   - No follower counts, no comparative engagement metrics
//
// Feature gate: AppStorage("community_os_org_os_enabled") — default false.
// Design (C3): systemGroupedBackground page, white floating cards, accentColor only.

import SwiftUI

// MARK: - AmenOrgDiscoveryView

struct AmenOrgDiscoveryView: View {

    @StateObject private var service = AmenOrganizationService()

    // MARK: Feature flag

    @AppStorage("community_os_org_os_enabled")
    private var featureEnabled: Bool = true

    // MARK: State

    @State private var selectedType: OrgType? = nil
    @State private var searchText: String = ""
    @State private var searchResults: [AmenOrganization] = []
    @State private var isSearching: Bool = false
    @State private var searchTask: Task<Void, Never>?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: Featured orgs (loaded from followed + discovery)

    private var displayedOrgs: [AmenOrganization] {
        if searchText.isEmpty {
            return service.followedOrgs
        }
        return searchResults
    }

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
            Image(systemName: "magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
            Text("Organization discovery is off")
                .font(.subheadline)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Organization discovery not yet available.")
    }

    // MARK: - Main content

    private var mainContent: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                // Search bar
                searchBar

                // OrgType filter chips
                typeFilterChips
                    .padding(.top, 8)

                // Results list
                if isSearching {
                    searchingIndicator
                } else if displayedOrgs.isEmpty {
                    emptyState
                } else {
                    orgList
                }
            }
        }
        .navigationTitle("Discover Organizations")
        .navigationBarTitleDisplayMode(.large)
        .onChange(of: searchText) { _, newValue in
            scheduleSearch(query: newValue)
        }
        .onChange(of: selectedType) { _, _ in
            scheduleSearch(query: searchText)
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color(uiColor: .secondaryLabel))
                .font(.systemScaled(15))

            TextField("Search churches, schools, nonprofits…", text: $searchText)
                .font(.systemScaled(16))
                .foregroundStyle(Color(uiColor: .label))
                .autocorrectionDisabled()
                .accessibilityLabel("Search organizations")

            if !searchText.isEmpty {
                Button {
                    withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.15)) {
                        searchText = ""
                        searchResults = []
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color(uiColor: .tertiaryLabel))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Type Filter Chips

    private var typeFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // "All" chip
                typeFilterChip(type: nil, label: "All", icon: "square.grid.2x2")

                ForEach(OrgType.allCases, id: \.self) { type in
                    typeFilterChip(type: type, label: type.displayName, icon: type.systemImage)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
    }

    private func typeFilterChip(type: OrgType?, label: String, icon: String) -> some View {
        let isSelected = selectedType == type
        return Button {
            withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.18)) {
                selectedType = isSelected ? nil : type
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.systemScaled(11))
                Text(label)
                    .font(.systemScaled(13, weight: isSelected ? .semibold : .regular))
            }
            .foregroundStyle(isSelected ? Color.accentColor : Color(uiColor: .secondaryLabel))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected
                          ? Color.accentColor.opacity(0.10)
                          : Color(uiColor: .secondarySystemFill))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label) filter, \(isSelected ? "selected" : "not selected")")
    }

    // MARK: - Org List

    private var orgList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 12) {
                if searchText.isEmpty {
                    sectionHeader("Following")
                }

                ForEach(displayedOrgs) { org in
                    NavigationLink(destination: AmenOrgProfileView(orgId: org.id)) {
                        AmenOrgCard(org: org) {
                            Task { try? await service.followOrg(orgId: org.id, userId: "") }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.systemScaled(13, weight: .semibold))
            .foregroundStyle(Color(uiColor: .secondaryLabel))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
            .padding(.bottom, 2)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Searching Indicator

    private var searchingIndicator: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
                .tint(Color.accentColor)
            Text("Searching…")
                .font(.subheadline)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: searchText.isEmpty ? "building.2" : "magnifyingglass")
                .font(.systemScaled(40, weight: .ultraLight))
                .foregroundStyle(Color(uiColor: .tertiaryLabel))
                .accessibilityHidden(true)

            if searchText.isEmpty {
                Text("Find organizations to follow.")
                    .font(.callout)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                    .multilineTextAlignment(.center)
            } else {
                Text("No organizations found for \"\(searchText)\".")
                    .font(.callout)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 40)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            searchText.isEmpty
                ? "No organizations followed yet. Search to find some."
                : "No results for \(searchText)."
        )
    }

    // MARK: - Search Scheduling (debounce)

    private func scheduleSearch(query: String) {
        searchTask?.cancel()
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchResults = []
            return
        }

        searchTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000) // 350ms debounce
            guard !Task.isCancelled else { return }

            isSearching = true
            defer { isSearching = false }

            if let results = try? await service.searchOrgs(query: query, type: selectedType) {
                await MainActor.run {
                    searchResults = results
                }
            }
        }
    }
}

// MARK: - AmenOrgCard

struct AmenOrgCard: View {

    let org: AmenOrganization
    var onFollow: () -> Void

    @State private var isFollowing: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            // Logo circle (44pt)
            orgLogo

            // Name + type + tagline
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(org.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(uiColor: .label))
                        .lineLimit(1)

                    if org.verificationStatus == .verified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.systemScaled(12))
                            .foregroundStyle(Color.accentColor)
                            .accessibilityHidden(true)
                    }
                }

                // Type badge pill
                Label(org.type.displayName, systemImage: org.type.systemImage)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color(uiColor: .secondarySystemFill))
                    )

                if let tagline = org.tagline, !tagline.isEmpty {
                    Text(tagline)
                        .font(.caption)
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }

            Spacer(minLength: 8)

            // Follow button (trailing)
            Button {
                withAnimation(.spring(response: 0.3)) {
                    isFollowing.toggle()
                }
                if isFollowing { onFollow() }
            } label: {
                Text(isFollowing ? "Following" : "Follow")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isFollowing ? Color(uiColor: .secondaryLabel) : Color.accentColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .strokeBorder(
                                isFollowing ? Color(uiColor: .separator) : Color.accentColor,
                                lineWidth: 1
                            )
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isFollowing ? "Following \(org.name)" : "Follow \(org.name)")
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.07), radius: 16, x: 0, y: 4)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(org.name), \(org.type.displayName)" +
            (org.tagline.map { ". \($0)" } ?? "") +
            (org.verificationStatus == .verified ? ". Verified." : "")
        )
    }

    // MARK: Logo

    private var orgLogo: some View {
        Group {
            if let logoStr = org.logoUrl, let url = URL(string: logoStr) {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        logoFallback
                    }
                }
            } else {
                logoFallback
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(Circle())
        .overlay(
            Circle()
                .strokeBorder(Color(uiColor: .separator), lineWidth: 0.5)
        )
        .accessibilityHidden(true)
    }

    private var logoFallback: some View {
        ZStack {
            Color(uiColor: .secondarySystemBackground)
            Image(systemName: org.type.systemImage)
                .font(.systemScaled(18))
                .foregroundStyle(Color(uiColor: .secondaryLabel))
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Org Discovery — feature ON") {
    AmenOrgDiscoveryView()
        .onAppear {
            UserDefaults.standard.set(true, forKey: "community_os_org_os_enabled")
        }
}

#Preview("Org Card") {
    VStack(spacing: 16) {
        AmenOrgCard(org: .preview, onFollow: {})
        AmenOrgCard(org: .nonprofitPreview, onFollow: {})
    }
    .padding()
    .background(Color(uiColor: .systemGroupedBackground))
}
#endif
