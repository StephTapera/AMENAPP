// AmenChurchDiscoveryView.swift
// AMEN Community OS — Church OS (Phase 3 / Agent A8)
//
// Church discovery: search bar + ServiceStyle filter chips + results list.
// Extends IntegrationOS/Maps/ChurchDiscoveryService (MapKit) with Firestore results.
//
// Location permission graceful degradation:
//   - "Near Me" button only shown when location is available
//   - Text search works without location (no throw on nil location)
//   - If location denied, discovery still works via name/style search
//
// Design rules (C3):
//   - Background: Color(uiColor: .systemGroupedBackground)
//   - Cards: white bg + shadow(radius:16) + cornerRadius(20, style:.continuous)
//   - Accents: Color.accentColor only
//   - memberCount / followersCount: NEVER displayed
//   - Feature-gated by community_os_church_os_enabled (default false)

import SwiftUI
import CoreLocation

// MARK: - AmenChurchDiscoveryView

struct AmenChurchDiscoveryView: View {

    @AppStorage("community_os_church_os_enabled")
    private var featureEnabled: Bool = false

    @StateObject private var service  = AmenChurchService()
    @StateObject private var locMgr   = ChurchDiscoveryLocationManager()

    @State private var searchText     = ""
    @State private var selectedStyle: ServiceStyle? = nil
    @State private var results:       [ChurchOSProfile] = []
    @State private var isSearching    = false
    @State private var hasSearched    = false
    @State private var searchError:   String? = nil
    @State private var searchTask:    Task<Void, Never>? = nil

    var body: some View {
        Group {
            if featureEnabled {
                discoveryContent
            } else {
                unavailablePlaceholder
            }
        }
        .navigationTitle("Find a Church")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Unavailable placeholder

    private var unavailablePlaceholder: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
            Text("Church discovery is coming soon.")
                .font(.headline)
                .foregroundStyle(Color(uiColor: .label))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    // MARK: - Discovery content

    private var discoveryContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                searchBar
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                styleFilterChips
                    .padding(.top, 12)

                nearMeButton
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                resultsSection
                    .padding(.top, 16)
                    .padding(.horizontal, 16)
            }
            .padding(.bottom, 40)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color(uiColor: .tertiaryLabel))

            TextField("Search churches\u{2026}", text: $searchText)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .accessibilityLabel("Search churches by name")
                .onChange(of: searchText) { _, newValue in
                    scheduleSearch(query: newValue)
                }

            if !searchText.isEmpty {
                Button {
                    searchText = ""; results = []; hasSearched = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color(uiColor: .tertiaryLabel))
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }

    // MARK: - Style filter chips

    private var styleFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                styleChip(label: "All", style: nil)
                ForEach(ServiceStyle.allCases, id: \.self) { style in
                    styleChip(label: style.displayName, style: style)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
        }
    }

    private func styleChip(label: String, style: ServiceStyle?) -> some View {
        let isSelected = selectedStyle == style
        return Button {
            selectedStyle = style
            scheduleSearch(query: searchText)
        } label: {
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(isSelected ? .white : Color.accentColor)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? Color.accentColor : Color.accentColor.opacity(0.10))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(
                            isSelected ? Color.clear : Color.accentColor.opacity(0.25),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    // MARK: - Near Me button (only when location is available)

    @ViewBuilder
    private var nearMeButton: some View {
        if locMgr.isAuthorized {
            Button { Task { await searchNearMe() } } label: {
                Label("Search Near Me", systemImage: "location.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.accentColor.opacity(0.10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(Color.accentColor.opacity(0.25), lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Search for churches near your current location")
        }
        // Location denied/unavailable — graceful omission
    }

    // MARK: - Results section

    @ViewBuilder
    private var resultsSection: some View {
        if isSearching {
            VStack(spacing: 12) {
                ProgressView()
                Text("Searching\u{2026}")
                    .font(.subheadline)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
            .accessibilityLabel("Searching for churches")
        } else if let err = searchError {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 32))
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                Text("Something went wrong")
                    .font(.headline)
                    .foregroundStyle(Color(uiColor: .label))
                Text(err)
                    .font(.caption)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Error: \(err)")
        } else if hasSearched && results.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "building.columns")
                    .font(.system(size: 36))
                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
                Text("No churches found")
                    .font(.headline)
                    .foregroundStyle(Color(uiColor: .label))
                Text("Try a different search or remove filters.")
                    .font(.subheadline)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("No churches found. Try adjusting your search.")
        } else if !results.isEmpty {
            LazyVStack(spacing: 12) {
                ForEach(results) { church in
                    let miles = locMgr.location.map { loc in
                        service.distanceMiles(from: loc.coordinate, to: church)
                    }
                    NavigationLink(destination: AmenChurchProfileView(churchId: church.id)) {
                        AmenChurchCard(church: church, distanceMiles: miles)
                    }
                    .buttonStyle(.plain)
                }
            }
        } else {
            // Initial (no search yet)
            VStack(spacing: 14) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.accentColor.opacity(0.50))
                Text("Discover Your Church Home")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color(uiColor: .label))
                Text("Search by name or use Near Me to find churches in your area.")
                    .font(.subheadline)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 48)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Discover your church home. Search by name or use Near Me.")
        }
    }

    // MARK: - Search logic

    private func scheduleSearch(query: String) {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await performSearch(query: query)
        }
    }

    @MainActor
    private func performSearch(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty || selectedStyle != nil else {
            results = []; hasSearched = false; return
        }
        isSearching = true; searchError = nil
        defer { isSearching = false }
        do {
            results = try await service.searchChurches(
                query:        trimmed,
                near:         locMgr.location?.coordinate,
                denomination: nil,
                style:        selectedStyle
            )
            hasSearched = true
        } catch {
            searchError = error.localizedDescription; hasSearched = true
        }
    }

    @MainActor
    private func searchNearMe() async {
        guard let coord = locMgr.location?.coordinate else { return }
        isSearching = true; searchError = nil
        defer { isSearching = false }
        do {
            results = try await service.getNearbyChurches(location: coord, radiusMiles: 25)
            hasSearched = true
        } catch {
            searchError = error.localizedDescription; hasSearched = true
        }
    }
}

// MARK: - AmenChurchCard

/// Discovery result card shown in the list.
/// Distance is optional — never shows memberCount/followersCount.
struct AmenChurchCard: View {
    let church: ChurchOSProfile
    let distanceMiles: Double?

    private var todayService: AmenServiceTime? { church.serviceTimesToday.first }

    private var distanceLabel: String? {
        guard let d = distanceMiles, d >= 0 else { return nil }
        if d < 0.1 { return "< 0.1 mi" }
        return d < 10 ? String(format: "%.1f mi", d) : String(format: "%.0f mi", d)
    }

    var body: some View {
        HStack(spacing: 14) {
            Group {
                if let logoStr = church.logoUrl, let url = URL(string: logoStr) {
                    AsyncImage(url: url) { phase in
                        if case .success(let img) = phase { img.resizable().scaledToFill() }
                        else { logoFallback }
                    }
                } else { logoFallback }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(church.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(uiColor: .label))
                        .lineLimit(1)
                    if church.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.accentColor)
                            .accessibilityLabel("Verified")
                    }
                }

                if let denomination = church.denomination {
                    Text(denomination)
                        .font(.caption)
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    if let service = todayService {
                        Label(service.startTime, systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                    }
                    if let dist = distanceLabel {
                        Label(dist, systemImage: "location")
                            .font(.caption)
                            .foregroundStyle(Color(uiColor: .secondaryLabel))
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(Color(uiColor: .tertiaryLabel))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(uiColor: .systemBackground))
                .shadow(color: .black.opacity(0.07), radius: 16, x: 0, y: 4)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(a11yLabel)
    }

    private var logoFallback: some View {
        Color(uiColor: .secondarySystemBackground)
            .overlay(
                Image(systemName: "building.columns.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
            )
    }

    private var a11yLabel: String {
        var parts = [church.name]
        if church.isVerified { parts.append("Verified") }
        if let d = church.denomination { parts.append(d) }
        if let s = todayService { parts.append("Service today at \(s.startTime)") }
        if let dist = distanceLabel { parts.append(dist + " away") }
        return parts.joined(separator: ". ")
    }
}

// MARK: - ChurchDiscoveryLocationManager

/// Minimal CLLocationManager wrapper. Gracefully degrades on location denial.
private final class ChurchDiscoveryLocationManager: NSObject, ObservableObject,
                                                     CLLocationManagerDelegate {
    @Published var location: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

    private let manager = CLLocationManager()

    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        authorizationStatus = manager.authorizationStatus
        if isAuthorized { manager.requestLocation() }
        else if authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
    }

    func locationManager(_ manager: CLLocationManager,
                         didUpdateLocations locations: [CLLocation]) {
        location = locations.last
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Location unavailable — discovery falls back to text-only search
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if isAuthorized { manager.requestLocation() }
    }
}

// MARK: - Preview

#Preview("Church Discovery") {
    NavigationStack {
        AmenChurchDiscoveryView()
    }
    .onAppear {
        UserDefaults.standard.set(true, forKey: "community_os_church_os_enabled")
    }
}
