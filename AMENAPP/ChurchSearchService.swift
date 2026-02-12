//
//  ChurchSearchService.swift
//  AMENAPP
//
//  Real-time church search using Apple Maps
//

import Foundation
import MapKit
import Combine

// MARK: - Church Search Errors
enum ChurchSearchError: LocalizedError {
    case noInternetConnection
    case noResultsFound
    case tooManyRequests
    case locationUnavailable
    
    var errorDescription: String? {
        switch self {
        case .noInternetConnection:
            return "No internet connection available"
        case .noResultsFound:
            return "No churches found in this area"
        case .tooManyRequests:
            return "Too many search requests. Please try again later"
        case .locationUnavailable:
            return "Location services are unavailable"
        }
    }
}

@MainActor
class ChurchSearchService: ObservableObject {
    static let shared = ChurchSearchService()
    
    @Published var isSearching = false
    @Published var searchResults: [Church] = []
    
    private init() {}
    
    /// Search for churches near a location using Apple Maps
    func searchChurches(
        near location: CLLocationCoordinate2D,
        radius: Double = 8000 // 5 miles in meters
    ) async throws -> [Church] {
        isSearching = true
        defer { isSearching = false }
        
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "church"
        request.region = MKCoordinateRegion(
            center: location,
            latitudinalMeters: radius,
            longitudinalMeters: radius
        )
        
        let search = MKLocalSearch(request: request)
        
        do {
            let response = try await search.start()
            
            // Check if we have results
            guard !response.mapItems.isEmpty else {
                throw ChurchSearchError.noResultsFound
            }
            
            let churches = response.mapItems.compactMap { mapItem -> Church? in
                guard let name = mapItem.name else { return nil }
                
                // Calculate distance
                let churchLocation = CLLocation(
                    latitude: mapItem.placemark.coordinate.latitude,
                    longitude: mapItem.placemark.coordinate.longitude
                )
                let userLocation = CLLocation(
                    latitude: location.latitude,
                    longitude: location.longitude
                )
                let distanceInMiles = userLocation.distance(from: churchLocation) / 1609.34
                
                return Church(
                    id: UUID(), // Generate unique ID for each search result
                    name: name,
                    denomination: extractDenomination(from: name),
                    address: formatAddress(from: mapItem.placemark),
                    distance: String(format: "%.1f miles away", distanceInMiles),
                    distanceValue: distanceInMiles,
                    serviceTime: "Contact church for service times",
                    phone: mapItem.phoneNumber ?? "No phone available",
                    coordinate: mapItem.placemark.coordinate,
                    website: mapItem.url?.host,
                    nextServiceCountdown: calculateNextService()
                )
            }
            
            // Check if we got any valid churches after filtering
            guard !churches.isEmpty else {
                throw ChurchSearchError.noResultsFound
            }
            
            searchResults = churches.sorted { $0.distanceValue < $1.distanceValue }
            return searchResults
            
        } catch let error as ChurchSearchError {
            // Re-throw our custom errors
            throw error
        } catch let mkError as MKError {
            // Handle MapKit-specific errors
            switch mkError.code {
            case .placemarkNotFound:
                throw ChurchSearchError.noResultsFound
            case .loadingThrottled:
                throw ChurchSearchError.tooManyRequests
            default:
                // Check for network-related errors
                if (mkError.errorUserInfo[NSUnderlyingErrorKey] as? URLError)?.code == .notConnectedToInternet {
                    throw ChurchSearchError.noInternetConnection
                }
                throw mkError
            }
        } catch {
            // Check for network errors
            if let urlError = error as? URLError {
                if urlError.code == .notConnectedToInternet {
                    throw ChurchSearchError.noInternetConnection
                }
            }
            throw error
        }
    }
    
    // MARK: - Helper Methods
    
    private func extractDenomination(from name: String) -> String {
        let lowercaseName = name.lowercased()
        
        if lowercaseName.contains("baptist") {
            return "Baptist"
        } else if lowercaseName.contains("catholic") {
            return "Catholic"
        } else if lowercaseName.contains("pentecostal") {
            return "Pentecostal"
        } else if lowercaseName.contains("methodist") {
            return "Methodist"
        } else if lowercaseName.contains("presbyterian") {
            return "Presbyterian"
        } else if lowercaseName.contains("lutheran") {
            return "Lutheran"
        } else if lowercaseName.contains("episcopal") {
            return "Episcopal"
        } else if lowercaseName.contains("assembly") || lowercaseName.contains("of god") {
            return "Assembly of God"
        } else {
            return "Non-Denominational"
        }
    }
    
    private func formatAddress(from placemark: MKPlacemark) -> String {
        var addressComponents: [String] = []
        
        if let street = placemark.thoroughfare {
            if let number = placemark.subThoroughfare {
                addressComponents.append("\(number) \(street)")
            } else {
                addressComponents.append(street)
            }
        }
        
        if let city = placemark.locality {
            addressComponents.append(city)
        }
        
        if let state = placemark.administrativeArea {
            addressComponents.append(state)
        }
        
        if let zip = placemark.postalCode {
            addressComponents.append(zip)
        }
        
        return addressComponents.joined(separator: ", ")
    }
    
    private func calculateNextService() -> String? {
        let calendar = Calendar.current
        let now = Date()
        
        // Get next Sunday
        var components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        components.weekday = 1 // Sunday
        
        guard let nextSunday = calendar.date(from: components) else { return nil }
        
        let daysUntil = calendar.dateComponents([.day], from: now, to: nextSunday).day ?? 0
        
        if daysUntil == 0 {
            return "Service today"
        } else if daysUntil == 1 {
            return "Next service tomorrow"
        } else {
            return "Next service in \(daysUntil) days"
        }
    }
}
