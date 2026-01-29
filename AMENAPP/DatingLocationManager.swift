//
//  DatingLocationManager.swift
//  AMENAPP
//
//  Created by Steph on 1/19/26.
//

import Foundation
import CoreLocation
import Combine

/// Manages location services for Christian Dating feature
@MainActor
class DatingLocationManager: NSObject, ObservableObject {
    static let shared = DatingLocationManager()
    
    @Published var currentLocation: CLLocationCoordinate2D?
    @Published var currentCity: String?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var errorMessage: String?
    
    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()
    
    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = 1000 // Update every ~1km
        
        authorizationStatus = locationManager.authorizationStatus
    }
    
    // MARK: - Permission Management
    
    func requestLocationPermission() {
        switch authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
            
        case .denied, .restricted:
            errorMessage = "Location access is required to find matches near you. Please enable it in Settings."
            
        case .authorizedWhenInUse, .authorizedAlways:
            startUpdatingLocation()
            
        @unknown default:
            break
        }
    }
    
    func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
    
    // MARK: - Location Updates
    
    func startUpdatingLocation() {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            return
        }
        
        locationManager.startUpdatingLocation()
    }
    
    func stopUpdatingLocation() {
        locationManager.stopUpdatingLocation()
    }
    
    func getCurrentLocation() -> CLLocationCoordinate2D? {
        return currentLocation
    }
    
    // MARK: - Geocoding
    
    func updateCityName(for coordinate: CLLocationCoordinate2D) async {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            
            if let placemark = placemarks.first {
                let city = placemark.locality ?? placemark.subLocality ?? ""
                let state = placemark.administrativeArea ?? ""
                
                if !city.isEmpty {
                    currentCity = state.isEmpty ? city : "\(city), \(state)"
                }
            }
        } catch {
            print("⚠️ Geocoding error: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Distance Calculation
    
    func distance(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let fromLocation = CLLocation(latitude: from.latitude, longitude: from.longitude)
        let toLocation = CLLocation(latitude: to.latitude, longitude: to.longitude)
        
        let distanceInMeters = fromLocation.distance(from: toLocation)
        let distanceInMiles = distanceInMeters / 1609.34
        
        return distanceInMiles
    }
    
    func formatDistance(_ miles: Double) -> String {
        if miles < 1 {
            return "Less than a mile away"
        } else if miles < 10 {
            return "\(Int(miles)) miles away"
        } else {
            return "\(Int(miles))+ miles away"
        }
    }
    
    // MARK: - Profile Filtering by Distance
    
    func filterProfilesByDistance(
        profiles: [DatingProfile],
        maxDistance: Double
    ) -> [DatingProfile] {
        guard let currentLocation = currentLocation else {
            return profiles
        }
        
        return profiles.filter { profile in
            guard let profileLocation = profile.location else {
                return false
            }
            
            let distance = self.distance(from: currentLocation, to: profileLocation)
            return distance <= maxDistance
        }
    }
    
    func sortProfilesByDistance(profiles: [DatingProfile]) -> [DatingProfile] {
        guard let currentLocation = currentLocation else {
            return profiles
        }
        
        return profiles.sorted { profile1, profile2 in
            guard let location1 = profile1.location,
                  let location2 = profile2.location else {
                return false
            }
            
            let distance1 = self.distance(from: currentLocation, to: location1)
            let distance2 = self.distance(from: currentLocation, to: location2)
            
            return distance1 < distance2
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension DatingLocationManager: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus
            
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                startUpdatingLocation()
                errorMessage = nil
                
            case .denied, .restricted:
                errorMessage = "Location access denied. Enable it in Settings to find matches near you."
                stopUpdatingLocation()
                
            case .notDetermined:
                break
                
            @unknown default:
                break
            }
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        Task { @MainActor in
            let coordinate = location.coordinate
            
            // Only update if location changed significantly
            if let current = currentLocation {
                let distance = self.distance(from: current, to: coordinate)
                guard distance > 0.5 else { return } // Only update if moved more than 0.5 miles
            }
            
            currentLocation = coordinate
            
            // Update city name
            await updateCityName(for: coordinate)
            
            // Update user's dating profile location
            if var profile = ChristianDatingService.shared.currentUserProfile {
                profile.locationLat = coordinate.latitude
                profile.locationLon = coordinate.longitude
                profile.locationCity = currentCity ?? profile.locationCity
                
                // Update in service (will sync to backend)
                try? await ChristianDatingService.shared.updateProfile(profile)
            }
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            print("❌ Location error: \(error.localizedDescription)")
            errorMessage = "Failed to get your location. Please try again."
        }
    }
}

// MARK: - Privacy Helper

struct LocationPrivacyHelper {
    /// Obscures exact location by rounding to city-level precision
    static func obscureLocation(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        // Round to ~10km precision for privacy
        let precision: Double = 0.1
        
        return CLLocationCoordinate2D(
            latitude: round(coordinate.latitude / precision) * precision,
            longitude: round(coordinate.longitude / precision) * precision
        )
    }
    
    /// Returns only city name, hiding exact location
    static func cityLevelLocationString(from coordinate: CLLocationCoordinate2D) async -> String? {
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            
            if let placemark = placemarks.first {
                let city = placemark.locality ?? ""
                let state = placemark.administrativeArea ?? ""
                
                if !city.isEmpty {
                    return state.isEmpty ? city : "\(city), \(state)"
                }
            }
        } catch {
            print("⚠️ Geocoding error: \(error.localizedDescription)")
        }
        
        return nil
    }
}

// MARK: - Mock Location (for Testing/Simulator)

extension DatingLocationManager {
    func setMockLocation(latitude: Double, longitude: Double, city: String) {
        currentLocation = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        currentCity = city
        authorizationStatus = .authorizedWhenInUse
    }
    
    func useSampleLocation() {
        // San Francisco for testing
        setMockLocation(
            latitude: 37.7749,
            longitude: -122.4194,
            city: "San Francisco, CA"
        )
    }
}

// MARK: - Location Permission View

import SwiftUI

struct LocationPermissionView: View {
    @StateObject private var locationManager = DatingLocationManager.shared
    let onGranted: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)
                
                Image(systemName: "location.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)
            }
            
            VStack(spacing: 12) {
                Text("Enable Location")
                    .font(.custom("OpenSans-Bold", size: 28))
                    .foregroundStyle(.primary)
                
                Text("We use your location to help you find matches near you. Your exact location is never shared with other users.")
                    .font(.custom("OpenSans-Regular", size: 16))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .lineSpacing(4)
            }
            
            VStack(alignment: .leading, spacing: 16) {
                PermissionBenefit(
                    icon: "location.circle.fill",
                    title: "Find Nearby Matches",
                    description: "See matches in your area"
                )
                
                PermissionBenefit(
                    icon: "lock.shield.fill",
                    title: "Privacy Protected",
                    description: "Only your city is shown to others"
                )
                
                PermissionBenefit(
                    icon: "slider.horizontal.3",
                    title: "You're in Control",
                    description: "Adjust distance preferences anytime"
                )
            }
            .padding(.horizontal, 32)
            
            Spacer()
            
            VStack(spacing: 12) {
                Button {
                    if locationManager.authorizationStatus == .denied || 
                       locationManager.authorizationStatus == .restricted {
                        locationManager.openSettings()
                    } else {
                        locationManager.requestLocationPermission()
                    }
                } label: {
                    Text(locationManager.authorizationStatus == .denied ? 
                         "Open Settings" : "Enable Location")
                        .font(.custom("OpenSans-Bold", size: 16))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal)
                
                Button {
                    // Skip for now - use approximate location
                    onGranted()
                } label: {
                    Text("Skip for Now")
                        .font(.custom("OpenSans-SemiBold", size: 14))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 12)
                }
            }
        }
        .padding(.vertical)
        .onChange(of: locationManager.authorizationStatus) { oldValue, newValue in
            if newValue == .authorizedWhenInUse || newValue == .authorizedAlways {
                onGranted()
            }
        }
    }
}

struct PermissionBenefit: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(.blue)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.custom("OpenSans-Bold", size: 14))
                    .foregroundStyle(.primary)
                
                Text(description)
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
