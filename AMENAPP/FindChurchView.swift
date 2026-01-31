//
//  FindChurchView.swift
//  AMENAPP
//
//  Created by Steph on 1/17/26.
//

import SwiftUI
import MapKit
import CoreLocation
import Combine

struct FindChurchView: View {
    @StateObject private var locationManager = LocationManager()
    @StateObject private var churchSearchService: ChurchSearchService = .shared
    @State private var searchText = ""
    @State private var selectedDenomination: ChurchDenomination = .all
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    @State private var showLocationPermissionAlert = false
    @State private var selectedViewMode: ViewMode = .list
    @State private var showSavedChurches = false
    @State private var savedChurchIds: Set<UUID> = []
    @State private var useRealSearch = false
    @State private var hasSearchedOnce = false
    
    enum ViewMode {
        case list
        case map
    }
    
    var userLocation: CLLocationCoordinate2D? {
        locationManager.userLocation
    }
    
    var locationStatusText: String {
        if locationManager.isAuthorized, let location = userLocation {
            return "San Francisco, CA" // You can use reverse geocoding here
        } else {
            return "Location services disabled"
        }
    }
    
    enum ChurchDenomination: String, CaseIterable {
        case all = "All"
        case baptist = "Baptist"
        case catholic = "Catholic"
        case nonDenominational = "Non-Denominational"
        case pentecostal = "Pentecostal"
        case methodist = "Methodist"
        case presbyterian = "Presbyterian"
    }
    
    var filteredChurches: [Church] {
        // Use real search results if available and location is enabled, otherwise use samples
        var churches: [Church]
        
        if useRealSearch && locationManager.isAuthorized && !churchSearchService.searchResults.isEmpty {
            churches = churchSearchService.searchResults
        } else {
            churches = sampleChurches
            
            // Update distances based on user location for sample data
            if let userLoc = userLocation {
                churches = churches.map { church in
                    let distance = calculateDistance(from: userLoc, to: church.coordinate)
                    var updatedChurch = church
                    updatedChurch.distance = String(format: "%.1f miles away", distance)
                    updatedChurch.distanceValue = distance
                    return updatedChurch
                }.sorted { $0.distanceValue < $1.distanceValue }
            }
        }
        
        // Filter by saved if enabled
        if showSavedChurches {
            churches = churches.filter { savedChurchIds.contains($0.id) }
        }
        
        // Filter by denomination
        let filtered = selectedDenomination == .all ? churches : churches.filter { $0.denomination == selectedDenomination.rawValue }
        
        // Filter by search text
        if searchText.isEmpty {
            return filtered
        }
        return filtered.filter { $0.name.localizedCaseInsensitiveContains(searchText) || $0.address.localizedCaseInsensitiveContains(searchText) }
    }
    
    private func calculateDistance(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let fromLocation = CLLocation(latitude: from.latitude, longitude: from.longitude)
        let toLocation = CLLocation(latitude: to.latitude, longitude: to.longitude)
        return fromLocation.distance(from: toLocation) / 1609.34 // Convert meters to miles
    }
    
    private var refreshAction: (() -> Void)? {
        if useRealSearch && locationManager.isAuthorized {
            return { self.performRealSearch() }
        }
        return nil
    }
    
    var body: some View {
        ZStack {
            // Background gradient matching the image aesthetic
            LinearGradient(
                colors: [
                    Color(red: 0.95, green: 0.85, blue: 0.9),
                    Color(red: 0.85, green: 0.95, blue: 1.0),
                    Color(red: 0.9, green: 1.0, blue: 0.95)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
        VStack(spacing: 0) {
            // Compact Glass Header (reduced padding)
            FindChurchHeader(
                searchText: $searchText,
                locationStatus: locationStatusText,
                onRefresh: refreshAction,
                isSearching: churchSearchService.isSearching
            )
            
            // Smart Permission Banners
            VStack(spacing: 8) {
                // Location permission banner with enhanced messaging
                if !locationManager.isAuthorized {
                    EnhancedLocationPermissionBanner(onRequestLocation: {
                        locationManager.requestPermission()
                        // Also request notifications when location is enabled
                        Task {
                            let notificationManager = ChurchNotificationManager.shared
                            _ = await notificationManager.requestNotificationPermission()
                        }
                    })
                }
                
                // Notification permission banner
                NotificationPermissionBanner()
            }
            
            // Smart filters row
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // Real search toggle (only show if location is enabled)
                    if locationManager.isAuthorized {
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                useRealSearch.toggle()
                                if useRealSearch {
                                    self.performRealSearch()
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                if churchSearchService.isSearching {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                        .tint(.white)
                                } else {
                                    Image(systemName: useRealSearch ? "mappin.and.ellipse" : "map")
                                        .font(.system(size: 12))
                                }
                                Text(useRealSearch ? "Live Search" : "Samples")
                                    .font(.custom("OpenSans-SemiBold", size: 14))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: useRealSearch ? [.green, .mint] : [.gray, .secondary],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                            )
                        }
                        .disabled(churchSearchService.isSearching)
                    }
                    
                    // View mode toggle
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedViewMode = selectedViewMode == .list ? .map : .list
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: selectedViewMode == .list ? "map.fill" : "list.bullet")
                                .font(.system(size: 12))
                            Text(selectedViewMode == .list ? "Map" : "List")
                                .font(.custom("OpenSans-SemiBold", size: 14))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(Color.blue)
                        )
                    }
                    
                    // Saved filter
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            showSavedChurches.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: showSavedChurches ? "bookmark.fill" : "bookmark")
                                .font(.system(size: 12))
                            Text("Saved")
                                .font(.custom("OpenSans-SemiBold", size: 14))
                        }
                        .foregroundStyle(showSavedChurches ? .white : .black)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(showSavedChurches ? Color.black : Color.gray.opacity(0.1))
                        )
                    }
                    
                    ForEach(ChurchDenomination.allCases, id: \.self) { denomination in
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedDenomination = denomination
                            }
                        } label: {
                            Text(denomination.rawValue)
                                .font(.custom("OpenSans-SemiBold", size: 14))
                                .foregroundStyle(selectedDenomination == denomination ? .white : .black)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(selectedDenomination == denomination ? Color.black : Color.gray.opacity(0.1))
                                )
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 12)
            
            // Content based on view mode
            if selectedViewMode == .map {
                // Map View
                ZStack(alignment: .topTrailing) {
                    Map(coordinateRegion: $region, showsUserLocation: locationManager.isAuthorized, annotationItems: filteredChurches) { church in
                        MapAnnotation(coordinate: church.coordinate) {
                            ChurchMapAnnotation(church: church, isSaved: savedChurchIds.contains(church.id))
                        }
                    }
                    .ignoresSafeArea(edges: .bottom)
                    
                    // Center on user location button
                    if locationManager.isAuthorized, let userLoc = userLocation {
                        Button {
                            withAnimation {
                                region.center = userLoc
                            }
                        } label: {
                            Image(systemName: "location.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(12)
                                .background(
                                    Circle()
                                        .fill(Color.blue)
                                        .shadow(color: .black.opacity(0.2), radius: 8, y: 2)
                                )
                        }
                        .padding()
                    }
                }
            } else {
                // List View
                if filteredChurches.isEmpty {
                    EmptyChurchesView(isFiltered: showSavedChurches || selectedDenomination != .all || !searchText.isEmpty)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            // Live search status banner
                            if useRealSearch && !churchSearchService.searchResults.isEmpty {
                                LiveSearchBanner(
                                    churchCount: churchSearchService.searchResults.count,
                                    onRefresh: { self.performRealSearch() }
                                )
                            }
                            
                            // Quick stats banner
                            if locationManager.isAuthorized {
                                QuickStatsBanner(
                                    churchCount: filteredChurches.count,
                                    nearestDistance: filteredChurches.first?.distance ?? "N/A"
                                )
                            }
                            
                            // Smart features info banner
                            if !savedChurchIds.isEmpty {
                                SmartFeaturesBanner(savedCount: savedChurchIds.count)
                            }
                            
                            ForEach(filteredChurches) { church in
                                EnhancedChurchCard(
                                    church: church,
                                    isSaved: savedChurchIds.contains(church.id),
                                    onSave: { self.toggleSave(church) },
                                    onGetDirections: { self.openDirections(to: church) },
                                    onCall: { self.callChurch(church) }
                                )
                            }
                        }
                        .padding(.vertical)
                    }
                }
            }
        }
        .onAppear {
            locationManager.checkLocationAuthorization()
            // Update map to user location if available
            if let userLoc = userLocation {
                region.center = userLoc
                // Auto-perform real search on first appear if location is available
                if !hasSearchedOnce {
                    hasSearchedOnce = true
                    self.performRealSearch()
                }
            }
        }
        .onChange(of: userLocation) { oldValue, newLocation in
            if let newLoc = newLocation {
                withAnimation {
                    region.center = newLoc
                }
                // Perform real search when location becomes available
                if !hasSearchedOnce {
                    hasSearchedOnce = true
                    self.performRealSearch()
                }
            }
        }
    }
}

// MARK: - FindChurchView Methods
extension FindChurchView {
    // MARK: - Real Search
    
    func performRealSearch() {
        guard let userLoc = userLocation else {
            print("⚠️ Cannot search: User location not available")
            return
        }
        
        useRealSearch = true
        
        Task {
            do {
                let haptic = UIImpactFeedbackGenerator(style: .light)
                haptic.impactOccurred()
                
                _ = try await $churchSearchService.searchChurches(near: userLoc)
                
                print("✅ Found \(churchSearchService.searchResults.count) churches nearby")
                
                // Success haptic
                let successHaptic = UINotificationFeedbackGenerator()
                successHaptic.notificationOccurred(.success)
                
            } catch {
                print("❌ Church search failed: \(error.localizedDescription)")
                
                // Fall back to sample data
                await MainActor.run {
                    useRealSearch = false
                }
                
                // Error haptic
                let errorHaptic = UINotificationFeedbackGenerator()
                errorHaptic.notificationOccurred(.error)
            }
        }
    }
    
    func toggleSave(_ church: Church) {
        if savedChurchIds.contains(church.id) {
            savedChurchIds.remove(church.id)
            // Remove all notifications when unsaving
            ChurchNotificationManager.shared.removeNotifications(for: church)
        } else {
            savedChurchIds.insert(church.id)
            // Schedule smart notifications for service times
            scheduleSmartNotifications(for: church)
        }
    }
    
    func scheduleSmartNotifications(for church: Church) {
        // Request notification permission if needed
        Task {
            let notificationManager = ChurchNotificationManager.shared
            if !notificationManager.isAuthorized {
                let granted = await notificationManager.requestNotificationPermission()
                if granted {
                    self.enableNotificationsForChurch(church)
                }
            } else {
                self.enableNotificationsForChurch(church)
            }
        }
    }
    
    func enableNotificationsForChurch(_ church: Church) {
        let notificationManager = ChurchNotificationManager.shared
        
        // Weekly service reminder (Saturday evening)
        notificationManager.scheduleWeeklyReminder(for: church)
        
        // Pre-service reminder (1 hour before)
        notificationManager.scheduleServiceReminder(for: church, beforeMinutes: 60)
        
        // Location-based reminder (when near church)
        notificationManager.scheduleLocationReminder(for: church, radius: 500)
    }
    
    func openDirections(to church: Church) {
        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: church.coordinate))
        mapItem.name = church.name
        mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }
    
    func callChurch(_ church: Church) {
        let phoneNumber = church.phone.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
        if let url = URL(string: "tel://\(phoneNumber)") {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - CLLocationCoordinate2D Extension
extension CLLocationCoordinate2D: Equatable {
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}

// MARK: - Location Manager
class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var userLocation: CLLocationCoordinate2D?
    @Published var isAuthorized = false
    
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }
    
    func checkLocationAuthorization() {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            isAuthorized = true
            manager.startUpdatingLocation()
        case .notDetermined:
            // Will show banner to request
            break
        case .denied, .restricted:
            isAuthorized = false
        @unknown default:
            break
        }
    }
    
    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        checkLocationAuthorization()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        userLocation = location.coordinate
    }
}

// MARK: - Compact Glassmorphic Header
struct FindChurchHeader: View {
    @Binding var searchText: String
    let locationStatus: String
    var onRefresh: (() -> Void)? = nil
    var isSearching: Bool = false
    @State private var isExpanded = false
    
    var body: some View {
        VStack(spacing: 8) {
            // Compact title row
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Find a Church")
                        .font(.custom("OpenSans-Bold", size: 24))
                        .foregroundStyle(.white)
                    
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "location.fill")
                                .font(.system(size: 10))
                            Text(locationStatus)
                                .font(.custom("OpenSans-Regular", size: 12))
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 10))
                        }
                        .foregroundStyle(.white.opacity(0.8))
                    }
                }
                
                Spacer()
                
                // Refresh button
                if let refresh = onRefresh {
                    Button {
                        let haptic = UIImpactFeedbackGenerator(style: .medium)
                        haptic.impactOccurred()
                        refresh()
                    } label: {
                        Group {
                            if isSearching {
                                ProgressView()
                                    .tint(.white)
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(width: 36, height: 36)
                        .background(
                            Circle()
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                )
                        )
                    }
                    .disabled(isSearching)
                }
            }
            
            // Expandable location details
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundStyle(.green)
                        Text("Live location enabled")
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    
                    HStack(spacing: 12) {
                        Image(systemName: "bell.fill")
                            .foregroundStyle(.orange)
                        Text("Smart notifications active")
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
                .padding(.top, 4)
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .opacity
                ))
            }
            
            // Glassmorphic search bar
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.white.opacity(0.7))
                    .font(.system(size: 16))
                
                TextField("Search churches...", text: $searchText)
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.white)
                    .tint(.white)
                
                if !searchText.isEmpty {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            searchText = ""
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.white.opacity(0.5))
                            .font(.system(size: 16))
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                ZStack {
                    // Frosted glass effect
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.ultraThinMaterial)
                    
                    // Subtle white overlay
                    RoundedRectangle(cornerRadius: 14)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.15),
                                    Color.white.opacity(0.05)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    // Border
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.4),
                                    Color.white.opacity(0.2)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            )
            .shadow(color: Color.black.opacity(0.1), radius: 20, x: 0, y: 10)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }
}

// MARK: - Enhanced Location Permission Banner
struct EnhancedLocationPermissionBanner: View {
    let onRequestLocation: () -> Void
    @State private var isAnimating = false
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 56, height: 56)
                
                Image(systemName: "location.fill.viewfinder")
                    .font(.system(size: 26))
                    .foregroundStyle(.white)
                    .scaleEffect(isAnimating ? 1.1 : 1.0)
                    .animation(
                        Animation.easeInOut(duration: 1.5)
                            .repeatForever(autoreverses: true),
                        value: isAnimating
                    )
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Enable Location Access")
                    .font(.custom("OpenSans-Bold", size: 16))
                    .foregroundStyle(.primary)
                
                Text("Find churches near you and get smart notifications")
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
            }
            
            Spacer()
            
            Button {
                let haptic = UIImpactFeedbackGenerator(style: .medium)
                haptic.impactOccurred()
                onRequestLocation()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                    Text("Enable")
                        .font(.custom("OpenSans-Bold", size: 15))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.blue, .cyan],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .shadow(color: .blue.opacity(0.3), radius: 8, y: 4)
                )
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            LinearGradient(
                                colors: [.blue.opacity(0.3), .cyan.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .onAppear {
            isAnimating = true
        }
    }
}

// MARK: - Dark Glassmorphic Church Card
struct EnhancedChurchCard: View {
    let church: Church
    let isSaved: Bool
    let onSave: () -> Void
    let onGetDirections: () -> Void
    let onCall: () -> Void
    
    @State private var isExpanded = false
    @State private var isPressed = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Main content
            VStack(alignment: .leading, spacing: 16) {
                // Header with save button
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(church.name)
                            .font(.custom("OpenSans-Bold", size: 20))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                        
                        HStack(spacing: 10) {
                            // Denomination badge
                            Text(church.denomination)
                                .font(.custom("OpenSans-SemiBold", size: 11))
                                .foregroundStyle(church.denominationColor)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule()
                                        .fill(church.denominationColor.opacity(0.2))
                                )
                            
                            // Distance
                            HStack(spacing: 4) {
                                Image(systemName: "location.fill")
                                    .font(.system(size: 10))
                                Text(church.distance)
                                    .font(.custom("OpenSans-SemiBold", size: 12))
                            }
                            .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    
                    Spacer()
                    
                    // Save button
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            onSave()
                            let haptic = UIImpactFeedbackGenerator(style: .medium)
                            haptic.impactOccurred()
                        }
                    } label: {
                        Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(isSaved ? .pink : .white.opacity(0.7))
                            .frame(width: 44, height: 44)
                            .background(
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .background(
                                        Circle()
                                            .fill(Color.black.opacity(0.3))
                                    )
                            )
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
                            )
                    }
                    .scaleEffect(isPressed && isSaved ? 1.1 : 1.0)
                }
                
                // Quick info tiles
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    DarkQuickInfoTile(
                        icon: "clock.fill",
                        title: "Service",
                        value: church.shortServiceTime,
                        color: .blue
                    )
                    
                    if let countdown = church.nextServiceCountdown {
                        DarkQuickInfoTile(
                            icon: "calendar",
                            title: "Next",
                            value: countdown.replacingOccurrences(of: "Next service in ", with: ""),
                            color: .green
                        )
                    }
                }
                
                // Action buttons
                HStack(spacing: 12) {
                    Button {
                        let haptic = UIImpactFeedbackGenerator(style: .light)
                        haptic.impactOccurred()
                        onCall()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "phone.fill")
                                .font(.system(size: 16))
                            Text("Call")
                                .font(.custom("OpenSans-Bold", size: 15))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.blue)
                        )
                    }
                    
                    Button {
                        let haptic = UIImpactFeedbackGenerator(style: .light)
                        haptic.impactOccurred()
                        onGetDirections()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                                .font(.system(size: 16))
                            Text("Directions")
                                .font(.custom("OpenSans-Bold", size: 15))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.ultraThinMaterial)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.black.opacity(0.3))
                                    )
                                
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
                            }
                        )
                    }
                }
                
                // Expandable details
                if isExpanded {
                    VStack(alignment: .leading, spacing: 14) {
                        Divider()
                            .overlay(Color.white.opacity(0.1))
                        
                        DarkDetailRow(icon: "mappin.and.ellipse", text: church.address, color: .blue)
                        DarkDetailRow(icon: "clock", text: church.serviceTime, color: .green)
                        DarkDetailRow(icon: "phone", text: church.phone, color: .orange)
                        
                        if let website = church.website {
                            Link(destination: URL(string: "https://\(website)")!) {
                                HStack(spacing: 12) {
                                    Image(systemName: "globe")
                                        .font(.system(size: 16))
                                        .foregroundStyle(.purple)
                                        .frame(width: 24)
                                    
                                    Text(website)
                                        .font(.custom("OpenSans-Regular", size: 15))
                                        .foregroundStyle(.purple)
                                        .underline()
                                    
                                    Spacer()
                                    
                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.purple)
                                }
                            }
                        }
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .opacity
                    ))
                }
                
                // Show more/less button
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        isExpanded.toggle()
                        let haptic = UIImpactFeedbackGenerator(style: .light)
                        haptic.impactOccurred()
                    }
                } label: {
                    HStack {
                        Text(isExpanded ? "Show Less" : "Show More")
                            .font(.custom("OpenSans-SemiBold", size: 14))
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.white.opacity(0.05))
                    )
                }
            }
            .padding(20)
        }
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.black.opacity(0.4))
                    )
                
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            }
        )
        .shadow(color: .black.opacity(0.4), radius: 25, x: 0, y: 12)
        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 4)
        .padding(.horizontal, 20)
    }
}

// Dark Quick Info Tile
struct DarkQuickInfoTile: View {
    let icon: String
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(color)
            
            Text(title)
                .font(.custom("OpenSans-Regular", size: 11))
                .foregroundStyle(.white.opacity(0.6))
            
            Text(value)
                .font(.custom("OpenSans-Bold", size: 13))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.black.opacity(0.3))
                    )
                
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            }
        )
    }
}

// Dark Detail Row
struct DarkDetailRow: View {
    let icon: String
    let text: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(color)
                .frame(width: 24)
            
            Text(text)
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.white.opacity(0.9))
            
            Spacer()
        }
    }
}

// MARK: - Location Permission Banner (OLD - Keep for reference)
struct LocationPermissionBanner: View {
    let onRequestLocation: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "location.fill.viewfinder")
                .font(.system(size: 24))
                .foregroundStyle(.blue)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Enable Location")
                    .font(.custom("OpenSans-Bold", size: 14))
                
                Text("Find churches near you")
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button {
                onRequestLocation()
            } label: {
                Text("Enable")
                    .font(.custom("OpenSans-Bold", size: 14))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color.blue)
                    )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.blue.opacity(0.1))
        )
        .padding(.horizontal)
        .padding(.top, 8)
    }
}

// MARK: - Notification Permission Banner
struct NotificationPermissionBanner: View {
    @State private var showBanner = false
    
    var body: some View {
        Group {
            if showBanner {
                HStack(spacing: 12) {
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.orange)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Enable Notifications")
                            .font(.custom("OpenSans-Bold", size: 14))
                        
                        Text("Get reminders for service times")
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Button {
                        requestNotificationPermission()
                    } label: {
                        Text("Enable")
                            .font(.custom("OpenSans-Bold", size: 14))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(Color.orange)
                            )
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.orange.opacity(0.1))
                )
                .padding(.horizontal)
                .padding(.top, 8)
            }
        }
        .onAppear {
            checkNotificationStatus()
        }
    }
    
    func checkNotificationStatus() {
        Task {
            let notificationManager = ChurchNotificationManager.shared
            let isAuthorized = await notificationManager.checkAuthorizationStatus()
            await MainActor.run {
                showBanner = !isAuthorized
            }
        }
    }
    
    func requestNotificationPermission() {
        Task {
            let notificationManager = ChurchNotificationManager.shared
            let granted = await notificationManager.requestNotificationPermission()
            if granted {
                await MainActor.run {
                    showBanner = false
                }
            }
        }
    }
}

// MARK: - Quick Stats Banner
struct QuickStatsBanner: View {
    let churchCount: Int
    let nearestDistance: String
    
    var body: some View {
        HStack(spacing: 0) {
            // Churches count
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.blue, .cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: "building.2.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.white)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(churchCount)")
                        .font(.custom("OpenSans-Bold", size: 22))
                        .foregroundStyle(.primary)
                    
                    Text("Churches Found")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            
            Divider()
                .frame(height: 40)
            
            // Nearest distance
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.green, .mint],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: "location.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.white)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(nearestDistance.replacingOccurrences(of: " away", with: ""))
                        .font(.custom("OpenSans-Bold", size: 18))
                        .foregroundStyle(.primary)
                    
                    Text("Nearest Church")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color(.systemGray5), lineWidth: 1)
                )
        )
        .padding(.horizontal, 20)
    }
}

// MARK: - Empty State
struct EmptyChurchesView: View {
    let isFiltered: Bool
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "building.2")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            
            Text(isFiltered ? "No Churches Found" : "No Churches Nearby")
                .font(.custom("OpenSans-Bold", size: 20))
            
            Text(isFiltered ? "Try adjusting your filters" : "We couldn't find any churches in this area")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Map Annotation
struct ChurchMapAnnotation: View {
    let church: Church
    let isSaved: Bool
    
    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(isSaved ? Color.pink : Color.blue)
                    .frame(width: 32, height: 32)
                
                Image(systemName: isSaved ? "bookmark.fill" : "building.2.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
            }
            
            Text(church.name)
                .font(.custom("OpenSans-SemiBold", size: 10))
                .foregroundStyle(.primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemBackground))
                        .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
                )
        }
    }
}

struct ChurchCard: View {
    let church: Church
    let isSaved: Bool
    let onSave: () -> Void
    let onGetDirections: () -> Void
    let onCall: () -> Void
    
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.15))
                        .frame(width: 56, height: 56)
                    
                    Image(systemName: "building.2.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.blue)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(church.name)
                        .font(.custom("OpenSans-Bold", size: 16))
                        .foregroundStyle(.primary)
                    
                    Text(church.denomination)
                        .font(.custom("OpenSans-SemiBold", size: 12))
                        .foregroundStyle(.blue)
                    
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        
                        Text(church.distance)
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                VStack(spacing: 8) {
                    Button {
                        onSave()
                    } label: {
                        Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(isSaved ? .pink : .secondary)
                    }
                    
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            if isExpanded {
                Divider()
                
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.blue)
                        
                        Text(church.address)
                            .font(.custom("OpenSans-Regular", size: 14))
                            .foregroundStyle(.primary)
                    }
                    
                    HStack(spacing: 8) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.blue)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(church.serviceTime)
                                .font(.custom("OpenSans-Regular", size: 14))
                                .foregroundStyle(.primary)
                            
                            if let nextService = church.nextServiceCountdown {
                                Text(nextService)
                                    .font(.custom("OpenSans-SemiBold", size: 12))
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    
                    HStack(spacing: 8) {
                        Image(systemName: "phone.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.blue)
                        
                        Text(church.phone)
                            .font(.custom("OpenSans-Regular", size: 14))
                            .foregroundStyle(.primary)
                    }
                    
                    if let website = church.website {
                        HStack(spacing: 8) {
                            Image(systemName: "globe")
                                .font(.system(size: 14))
                                .foregroundStyle(.blue)
                            
                            Link(website, destination: URL(string: "https://\(website)")!)
                                .font(.custom("OpenSans-Regular", size: 14))
                                .foregroundStyle(.blue)
                        }
                    }
                }
                
                HStack(spacing: 12) {
                    Button {
                        onCall()
                    } label: {
                        HStack {
                            Image(systemName: "phone.fill")
                            Text("Call")
                                .font(.custom("OpenSans-Bold", size: 14))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.black)
                        )
                    }
                    
                    Button {
                        onGetDirections()
                    } label: {
                        HStack {
                            Image(systemName: "location.fill")
                            Text("Directions")
                                .font(.custom("OpenSans-Bold", size: 14))
                        }
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.gray.opacity(0.1))
                        )
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
        )
        .padding(.horizontal)
    }
}

struct Church: Identifiable {
    let id = UUID()
    let name: String
    let denomination: String
    let address: String
    var distance: String
    var distanceValue: Double = 0.0
    let serviceTime: String
    let phone: String
    let coordinate: CLLocationCoordinate2D
    let website: String?
    let nextServiceCountdown: String?
}

// MARK: - Church Extensions for Smart Features
extension Church {
    var gradientColors: [Color] {
        switch denomination {
        case "Baptist":
            return [.blue, .cyan]
        case "Catholic":
            return [.purple, .pink]
        case "Non-Denominational":
            return [.green, .teal]
        case "Pentecostal":
            return [.orange, .red]
        case "Methodist":
            return [.indigo, .blue]
        case "Presbyterian":
            return [.mint, .green]
        default:
            return [.gray, .secondary]
        }
    }
    
    var denominationColor: Color {
        switch denomination {
        case "Baptist":
            return .blue
        case "Catholic":
            return .purple
        case "Non-Denominational":
            return .green
        case "Pentecostal":
            return .orange
        case "Methodist":
            return .indigo
        case "Presbyterian":
            return .mint
        default:
            return .gray
        }
    }
    
    var shortServiceTime: String {
        // Extract first time from service string
        let components = serviceTime.split(separator: " ")
        if let timeIndex = components.firstIndex(where: { $0.contains(":") }) {
            return String(components[timeIndex])
        }
        return "Sunday"
    }
}

// MARK: - Smart Features Banner
struct SmartFeaturesBanner: View {
    let savedCount: Int
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.orange, .pink],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: "sparkles")
                        .font(.system(size: 18))
                        .foregroundStyle(.white)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Smart Reminders Active")
                        .font(.custom("OpenSans-Bold", size: 16))
                        .foregroundStyle(.primary)
                    
                    Text("\(savedCount) church\(savedCount == 1 ? "" : "es") saved")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isExpanded.toggle()
                        let haptic = UIImpactFeedbackGenerator(style: .light)
                        haptic.impactOccurred()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up.circle.fill" : "info.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.orange)
                }
            }
            
            if isExpanded {
                VStack(spacing: 0) {
                    Divider()
                        .padding(.vertical, 12)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        SmartFeatureRow(
                            icon: "bell.badge.fill",
                            title: "Service Reminders",
                            description: "1 hour before services start",
                            color: .blue
                        )
                        
                        SmartFeatureRow(
                            icon: "calendar.badge.clock",
                            title: "Weekly Alerts",
                            description: "Saturday evening preview",
                            color: .green
                        )
                        
                        SmartFeatureRow(
                            icon: "location.fill.viewfinder",
                            title: "Nearby Alerts",
                            description: "When you're near your church",
                            color: .purple
                        )
                    }
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            LinearGradient(
                                colors: [.orange.opacity(0.3), .pink.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .padding(.horizontal, 20)
    }
}

struct SmartFeatureRow: View {
    let icon: String
    let title: String
    let description: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.1))
                    .frame(width: 36, height: 36)
                
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(color)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.custom("OpenSans-SemiBold", size: 14))
                    .foregroundStyle(.primary)
                
                Text(description)
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
    }
}

// MARK: - Live Search Banner
struct LiveSearchBanner: View {
    let churchCount: Int
    let onRefresh: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.green, .mint],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
                
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 20))
                    .foregroundStyle(.white)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text("Live Search Active")
                    .font(.custom("OpenSans-Bold", size: 15))
                    .foregroundStyle(.primary)
                
                Text("\(churchCount) real churches from Apple Maps")
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button {
                let haptic = UIImpactFeedbackGenerator(style: .light)
                haptic.impactOccurred()
                onRefresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.green)
                    .padding(10)
                    .background(
                        Circle()
                            .fill(Color.green.opacity(0.1))
                    )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            LinearGradient(
                                colors: [.green.opacity(0.3), .mint.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .padding(.horizontal, 20)
    }
}

// MARK: - Sample Churches Data

let sampleChurches = [
    Church(
        name: "Grace Community Church",
        denomination: "Non-Denominational",
        address: "123 Main St, San Francisco, CA 94102",
        distance: "0.5 miles away",
        distanceValue: 0.5,
        serviceTime: "Sunday 9:00 AM & 11:00 AM",
        phone: "(415) 555-0123",
        coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        website: "gracechurch.org",
        nextServiceCountdown: "Next service in 2 days"
    ),
    Church(
        name: "First Baptist Church",
        denomination: "Baptist",
        address: "456 Oak Ave, San Francisco, CA 94103",
        distance: "1.2 miles away",
        distanceValue: 1.2,
        serviceTime: "Sunday 10:30 AM",
        phone: "(415) 555-0456",
        coordinate: CLLocationCoordinate2D(latitude: 37.7849, longitude: -122.4094),
        website: "firstbaptist.org",
        nextServiceCountdown: "Next service in 2 days"
    ),
    Church(
        name: "New Life Fellowship",
        denomination: "Pentecostal",
        address: "789 Pine St, San Francisco, CA 94104",
        distance: "2.1 miles away",
        distanceValue: 2.1,
        serviceTime: "Sunday 8:00 AM & 10:00 AM",
        phone: "(415) 555-0789",
        coordinate: CLLocationCoordinate2D(latitude: 37.7649, longitude: -122.4294),
        website: "newlifesf.org",
        nextServiceCountdown: "Next service in 2 days"
    ),
    Church(
        name: "St. Mary's Catholic Church",
        denomination: "Catholic",
        address: "321 Market St, San Francisco, CA 94105",
        distance: "1.8 miles away",
        distanceValue: 1.8,
        serviceTime: "Saturday 5:00 PM, Sunday 8:00 AM, 10:00 AM & 12:00 PM",
        phone: "(415) 555-0321",
        coordinate: CLLocationCoordinate2D(latitude: 37.7799, longitude: -122.4144),
        website: "stmaryssf.org",
        nextServiceCountdown: "Next service in 1 day"
    ),
    Church(
        name: "City Church SF",
        denomination: "Non-Denominational",
        address: "555 Mission St, San Francisco, CA 94106",
        distance: "0.9 miles away",
        distanceValue: 0.9,
        serviceTime: "Sunday 9:30 AM & 11:30 AM",
        phone: "(415) 555-0555",
        coordinate: CLLocationCoordinate2D(latitude: 37.7699, longitude: -122.4244),
        website: "citychurchsf.com",
        nextServiceCountdown: "Next service in 2 days"
    )
]

#Preview {
    FindChurchView()
}
