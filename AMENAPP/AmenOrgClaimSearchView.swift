// AmenOrgClaimSearchView.swift
// AMEN App — Org Claim Search Screen
//
// Presented as a sheet or push from AmenOrganizationProfileView's .claimCTA module.
// Uses Algolia `organizations` index for primary search; "Search with Google Maps"
// secondary button invokes the Places fallback.

import SwiftUI

struct AmenOrgClaimSearchView: View {

    // MARK: - Environment / State

    @StateObject private var service = AmenOrgClaimService.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @State private var query: String = ""
    @State private var selectedTypeFilter: AmenOrganizationType? = nil
    @State private var placesResults: [PlaceSearchResult] = []
    @State private var isSearchingPlaces: Bool = false
    @State private var showingPlacesResults: Bool = false

    @State private var selectedOrgForClaim: AmenOrganizationProfile? = nil
    @State private var selectedPlaceForStub: PlaceSearchResult? = nil
    @State private var showClaimSheet: Bool = false
    @State private var showAddListingSheet: Bool = false

    @FocusState private var searchFocused: Bool

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    searchBarSection
                    placesToggleButton

                    if !query.isEmpty {
                        if showingPlacesResults {
                            placesResultsSection
                        } else {
                            algoliaResultsSection
                        }
                    } else {
                        recentlyVerifiedSection
                    }

                    addListingFooter
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Find Your Organization")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(AMENFont.regular(16))
                        .foregroundStyle(AmenTheme.Colors.amenGold)
                }
            }
        }
        // Claim sheet for Algolia results
        .sheet(item: $selectedOrgForClaim) { org in
            AmenOrgClaimSheet(organization: org)
                .presentationDetents([.medium, .large])
                .presentationCornerRadius(24)
                .presentationDragIndicator(.visible)
        }
        // Claim sheet for Places-sourced stub creation
        .sheet(item: $selectedPlaceForStub) { place in
            AmenOrgStubCreationSheet(placeResult: place)
                .presentationDetents([.medium, .large])
                .presentationCornerRadius(24)
                .presentationDragIndicator(.visible)
        }
        // Manual "Add a new listing" sheet
        .sheet(isPresented: $showAddListingSheet) {
            AmenOrgNewListingSheet()
                .presentationDetents([.medium, .large])
                .presentationCornerRadius(24)
                .presentationDragIndicator(.visible)
        }
        .onChange(of: query) { _, newValue in
            showingPlacesResults = false
            placesResults = []
            Task {
                // Brief debounce so rapid typing doesn't spam Algolia
                try? await Task.sleep(for: .milliseconds(320))
                await service.search(query: newValue, type: selectedTypeFilter)
            }
        }
    }

    // MARK: - Search Bar

    private var searchBarSection: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("Search for your church, school, or org", text: $query)
                .font(AMENFont.regular(16))
                .foregroundStyle(Color.primary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)
                .focused($searchFocused)
                .submitLabel(.search)
                .onSubmit {
                    Task { await service.search(query: query, type: selectedTypeFilter) }
                }

            if !query.isEmpty {
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        query = ""
                        service.searchResults = []
                        placesResults = []
                        showingPlacesResults = false
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(glassCard(cornerRadius: 14))
        .onAppear { searchFocused = true }
    }

    // MARK: - Places Toggle

    private var placesToggleButton: some View {
        Button {
            guard !query.isEmpty else { return }
            Task { await performPlacesSearch() }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "map")
                    .font(.system(size: 13, weight: .medium))
                Text("or search with Google Maps")
                    .font(AMENFont.regular(14))
                if isSearchingPlaces {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            .foregroundStyle(AmenTheme.Colors.amenBlue)
        }
        .buttonStyle(.plain)
        .padding(.leading, 2)
        .disabled(query.isEmpty)
        .opacity(query.isEmpty ? 0.4 : 1.0)
        .accessibilityLabel("Search with Google Maps for \(query)")
    }

    // MARK: - Algolia Results

    @ViewBuilder
    private var algoliaResultsSection: some View {
        if service.isSearching {
            HStack {
                ProgressView()
                Text("Searching…")
                    .font(AMENFont.regular(14))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        } else if service.searchResults.isEmpty && !query.isEmpty {
            emptySearchState
        } else {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Results")
                ForEach(service.searchResults) { org in
                    AmenOrgSearchResultCard(organization: org) {
                        selectedOrgForClaim = org
                    }
                }
            }
        }
    }

    private var emptySearchState: some View {
        VStack(spacing: 12) {
            Image(systemName: "binoculars")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)
            Text("No results for \"\(query)\"")
                .font(AMENFont.semiBold(15))
                .foregroundStyle(Color.primary)
            Text("Try a shorter name, city, or tap 'Search with Google Maps' above.")
                .font(AMENFont.regular(13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    // MARK: - Places Results

    @ViewBuilder
    private var placesResultsSection: some View {
        if isSearchingPlaces {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
        } else if placesResults.isEmpty {
            Text("No Google Maps results found.")
                .font(AMENFont.regular(14))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Google Maps Results")
                ForEach(placesResults) { place in
                    AmenPlaceSearchResultCard(place: place) {
                        selectedPlaceForStub = place
                    }
                }
            }
        }
    }

    // MARK: - Recently Verified

    private var recentlyVerifiedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Recently Verified")
            // Skeleton state — real implementation populates via Algolia
            // filter: claimStatus:verified, sorted by updatedAt desc, limit 3
            AmenGlassLoadingSkeleton(cornerRadius: 16, height: 72)
            AmenGlassLoadingSkeleton(cornerRadius: 16, height: 72)
            AmenGlassLoadingSkeleton(cornerRadius: 16, height: 72)
        }
        .onAppear {
            Task {
                // Pre-load recently verified nearby orgs
                await service.search(query: "church", type: nil)
            }
        }
    }

    // MARK: - Add Listing Footer

    private var addListingFooter: some View {
        VStack(spacing: 6) {
            Divider().padding(.vertical, 4)
            HStack(spacing: 8) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AmenTheme.Colors.amenGold)
                Text("Not finding yours?")
                    .font(AMENFont.semiBold(14))
                    .foregroundStyle(Color.primary)
                Spacer()
            }
            HStack {
                Button("Add a new listing") {
                    showAddListingSheet = true
                }
                .font(AMENFont.semiBold(14))
                .foregroundStyle(AmenTheme.Colors.amenGold)
                .buttonStyle(.plain)
                Spacer()
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Helpers

    private func performPlacesSearch() async {
        isSearchingPlaces = true
        showingPlacesResults = true
        placesResults = await service.searchPlaces(query: query)
        isSearchingPlaces = false
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(AMENFont.semiBold(13))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.5)
    }

    @ViewBuilder
    private func glassCard(cornerRadius: CGFloat) -> some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                )
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.38), lineWidth: 0.6)
                )
        }
    }
}

// MARK: - AmenOrgSearchResultCard

struct AmenOrgSearchResultCard: View {
    let organization: AmenOrganizationProfile
    let onClaimTapped: () -> Void

    @GestureState private var isPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var isClaimed: Bool {
        organization.claimStatus.allowsOfficialControls
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Type icon
            Image(systemName: typeIcon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(AmenTheme.Colors.amenGold)
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(AmenTheme.Colors.amenGold.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(organization.name)
                    .font(AMENFont.semiBold(15))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(organization.type.displayName)
                        .font(AMENFont.regular(12))
                        .foregroundStyle(.secondary)

                    if let city = organization.address.city,
                       let state = organization.address.state {
                        Text("·")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Text("\(city), \(state)")
                            .font(AMENFont.regular(12))
                            .foregroundStyle(.secondary)
                    }
                }

                claimStatusChip
            }

            Spacer(minLength: 0)

            if !isClaimed {
                claimButton
            }
        }
        .padding(14)
        .background(cardBackground)
        .scaleEffect(isPressed && !reduceMotion ? 0.97 : 1.0)
        .opacity(isPressed && !reduceMotion ? 0.9 : 1.0)
        .animation(.spring(response: 0.22, dampingFraction: 0.82), value: isPressed)
        .gesture(DragGesture(minimumDistance: 0).updating($isPressed) { _, s, _ in s = true })
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(organization.name), \(organization.type.displayName), \(isClaimed ? "Claimed" : "Available to claim")")
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var claimStatusChip: some View {
        if isClaimed {
            Text("Claimed")
                .font(AMENFont.semiBold(11))
                .foregroundStyle(Color.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(Color(.tertiarySystemFill))
                )
        } else {
            Text("Unclaimed")
                .font(AMENFont.semiBold(11))
                .foregroundStyle(AmenTheme.Colors.amenGold)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(AmenTheme.Colors.amenGold.opacity(0.12))
                )
        }
    }

    private var claimButton: some View {
        Button(action: onClaimTapped) {
            Text("Claim")
                .font(AMENFont.semiBold(13))
                .foregroundStyle(Color(.systemBackground))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(AmenTheme.Colors.amenGold)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Claim \(organization.name)")
    }

    private var typeIcon: String {
        switch organization.type {
        case .church:              return "building.columns.fill"
        case .school, .university: return "graduationcap.fill"
        case .campusGroup:         return "person.3.fill"
        case .business:            return "briefcase.fill"
        case .nonprofit:           return "heart.fill"
        case .ministry:            return "hands.sparkles.fill"
        case .bibleStudy:          return "book.fill"
        case .creatorCommunity:    return "sparkles"
        case .communityGroup:      return "person.2.fill"
        }
    }

    @ViewBuilder
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(.regularMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.30), lineWidth: 0.6)
            )
            .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 3)
    }
}

// MARK: - AmenPlaceSearchResultCard

struct AmenPlaceSearchResultCard: View {
    let place: PlaceSearchResult
    let onSelectTapped: () -> Void

    @GestureState private var isPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(AmenTheme.Colors.amenBlue)
                .frame(width: 40, height: 40)
                .background(Circle().fill(AmenTheme.Colors.amenBlue.opacity(0.10)))

            VStack(alignment: .leading, spacing: 3) {
                Text(place.displayName)
                    .font(AMENFont.semiBold(15))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                Text(place.displayAddress)
                    .font(AMENFont.regular(12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("Google Maps")
                    .font(AMENFont.regular(11))
                    .foregroundStyle(AmenTheme.Colors.amenBlue)
            }

            Spacer(minLength: 0)

            Button(action: onSelectTapped) {
                Text("Select")
                    .font(AMENFont.semiBold(13))
                    .foregroundStyle(Color(.systemBackground))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(AmenTheme.Colors.amenBlue))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Select \(place.displayName)")
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.30), lineWidth: 0.6)
                )
                .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 3)
        )
        .scaleEffect(isPressed && !reduceMotion ? 0.97 : 1.0)
        .opacity(isPressed && !reduceMotion ? 0.9 : 1.0)
        .animation(.spring(response: 0.22, dampingFraction: 0.82), value: isPressed)
        .gesture(DragGesture(minimumDistance: 0).updating($isPressed) { _, s, _ in s = true })
        .accessibilityElement(children: .combine)
    }
}

// MARK: - AmenOrgStubCreationSheet
// Presented when the user selects a Google Places result.
// Persists ONLY the placeId via `createOrgStub` CF.

struct AmenOrgStubCreationSheet: View {
    let placeResult: PlaceSearchResult

    @StateObject private var service = AmenOrgClaimService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var selectedType: AmenOrganizationType = .church
    @State private var isCreating: Bool = false
    @State private var error: String? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(placeResult.displayName)
                        .font(AMENFont.semiBold(18))
                        .foregroundStyle(Color.primary)
                    Text(placeResult.displayAddress)
                        .font(AMENFont.regular(14))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.regularMaterial)
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text("Organization Type")
                        .font(AMENFont.semiBold(13))
                        .foregroundStyle(.secondary)
                    Picker("Organization type", selection: $selectedType) {
                        ForEach(AmenOrganizationType.allCases) { t in
                            Text(t.displayName).tag(t)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(AmenTheme.Colors.amenGold)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let error {
                    Text(error)
                        .font(AMENFont.regular(13))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer()

                Button {
                    Task { await createStubAndClaim() }
                } label: {
                    Group {
                        if isCreating {
                            ProgressView()
                                .tint(Color(.systemBackground))
                        } else {
                            Text("Add Listing & Claim")
                                .font(AMENFont.semiBold(16))
                        }
                    }
                    .foregroundStyle(Color(.systemBackground))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(isCreating ? AmenTheme.Colors.amenGold.opacity(0.6) : AmenTheme.Colors.amenGold)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isCreating)
                .accessibilityLabel("Add listing and claim \(placeResult.displayName)")
            }
            .padding(20)
            .navigationTitle("Add Listing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(AmenTheme.Colors.amenGold)
                }
            }
        }
    }

    private func createStubAndClaim() async {
        isCreating = true
        error = nil
        do {
            _ = try await service.createOrgStub(
                placeId: placeResult.placeId,
                name: placeResult.displayName,    // display only, CF stores placeId only
                type: selectedType,
                city: "",    // CF derives from placeId
                state: ""
            )
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        isCreating = false
    }
}

// MARK: - AmenOrgNewListingSheet
// "Add a new listing" path when org isn't found anywhere.

struct AmenOrgNewListingSheet: View {
    @StateObject private var service = AmenOrgClaimService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var selectedType: AmenOrganizationType = .church
    @State private var city: String = ""
    @State private var state: String = ""
    @State private var isCreating: Bool = false
    @State private var error: String? = nil

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !city.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Organization Info") {
                    TextField("Name", text: $name)
                    Picker("Type", selection: $selectedType) {
                        ForEach(AmenOrganizationType.allCases) { t in
                            Text(t.displayName).tag(t)
                        }
                    }
                    .tint(AmenTheme.Colors.amenGold)
                }
                Section("Location") {
                    TextField("City", text: $city)
                    TextField("State / Province", text: $state)
                }
                if let error {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(AMENFont.regular(13))
                    }
                }
                Section {
                    Button {
                        Task { await createStub() }
                    } label: {
                        if isCreating {
                            HStack {
                                ProgressView().tint(AmenTheme.Colors.amenGold)
                                Text("Creating…").foregroundStyle(.secondary)
                            }
                        } else {
                            Text("Add Listing")
                                .font(AMENFont.semiBold(15))
                                .foregroundStyle(canSubmit ? AmenTheme.Colors.amenGold : Color.secondary)
                        }
                    }
                    .disabled(!canSubmit || isCreating)
                }
            }
            .navigationTitle("New Listing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(AmenTheme.Colors.amenGold)
                }
            }
        }
    }

    private func createStub() async {
        isCreating = true
        error = nil
        do {
            _ = try await service.createOrgStub(
                placeId: nil,
                name: name.trimmingCharacters(in: .whitespaces),
                type: selectedType,
                city: city.trimmingCharacters(in: .whitespaces),
                state: state.trimmingCharacters(in: .whitespaces)
            )
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        isCreating = false
    }
}
