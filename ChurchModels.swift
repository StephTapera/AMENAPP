//
//  ChurchModels.swift
//  AMENAPP
//
//  Unified Church entity system
//  Clickable church references with deep linking
//

import Foundation
import CoreLocation
import SwiftUI

// MARK: - Church Entity

/// Unified church entity (one church = one ID across the app)
/// Note: Named ChurchEntity to avoid conflict with FindChurchView.Church
struct ChurchEntity: Identifiable, Codable, Hashable {
    let id: String  // Stable churchId (from Google Places or Firestore)
    let placeId: String?  // Google Places ID
    let name: String
    let address: String
    let city: String
    let state: String?
    let zipCode: String?
    let country: String
    let coordinate: GeoPoint
    let phoneNumber: String?
    let email: String?
    let website: String?
    let denomination: String?
    let photoURL: String?
    let logoURL: String?
    
    // Service times (optional)
    var serviceTimes: [ChurchEntity.ServiceTime]
    
    // Cached stats
    var memberCount: Int  // Users who marked "My Church"
    var visitCount: Int  // Users who visited or planned to visit
    var tipCount: Int  // Number of tips/reviews
    
    // Metadata
    let createdAt: Date
    var updatedAt: Date
    let source: ChurchSource  // How this church was added
    
    enum ChurchSource: String, Codable {
        case googlePlaces = "google_places"
        case userSubmitted = "user_submitted"
        case manual = "manual"
    }
    
    struct ServiceTime: Codable, Hashable {
        let dayOfWeek: Int  // 1 = Sunday, 7 = Saturday
        let time: String  // "9:00 AM", "10:30 AM", etc.
        let serviceType: String?  // "Sunday Service", "Youth Service", etc.
    }
    
    struct GeoPoint: Codable, Hashable {
        let latitude: Double
        let longitude: Double
        
        var clLocation: CLLocation {
            CLLocation(latitude: latitude, longitude: longitude)
        }
    }
    
    // Calculate distance from user location
    func distance(from userLocation: CLLocation) -> Double {
        return coordinate.clLocation.distance(from: userLocation) / 1609.34  // Convert to miles
    }
    
    // Display string for distance
    func distanceString(from userLocation: CLLocation) -> String {
        let miles = distance(from: userLocation)
        if miles < 1 {
            return String(format: "%.1f mi", miles)
        } else {
            return String(format: "%.0f mi", miles)
        }
    }
}

// MARK: - Church Tag

/// Church reference in posts, notes, comments, messages
struct ChurchTag: Codable, Identifiable, Hashable {
    let id: String  // Tag ID
    let churchId: String  // Reference to Church
    let churchName: String  // Cached for quick display
    let city: String  // Cached for display
    let distance: Double?  // Distance when tagged (optional)
    let taggedAt: Date
    let taggedBy: String  // User ID who tagged
    
    // Context where this tag appears
    let context: TagContext
    let contextId: String  // Post ID, Note ID, Message ID, etc.
    
    enum TagContext: String, Codable {
        case post
        case churchNote
        case comment
        case message
    }
}

// MARK: - Church Profile View Data

/// Full church profile data (extended with user-specific info)
struct ChurchProfileData {
    let church: ChurchEntity
    let userRelation: UserChurchRelation?
    let recentTips: [ChurchTip]
    let upcomingServices: [ChurchEntity.ServiceTime]
    let isMyChurch: Bool
    let havePlannedVisit: Bool
}

/// User's relationship with a church
struct UserChurchRelation: Codable {
    let userId: String
    let churchId: String
    let relation: RelationType
    let since: Date
    var lastVisited: Date?
    var visitCount: Int
    
    enum RelationType: String, Codable {
        case member = "member"  // "This is my church"
        case visitor = "visitor"  // Visited once
        case interested = "interested"  // Saved/planning to visit
    }
}

// MARK: - Church Tips

/// User-submitted tips for first-time visitors
struct ChurchTip: Identifiable, Codable {
    let id: String
    let churchId: String
    let authorId: String
    let authorName: String
    let authorPhotoURL: String?
    let content: String
    let category: TipCategory
    let helpfulCount: Int
    let createdAt: Date
    var isHelpful: Bool  // User marked as helpful
    
    enum TipCategory: String, Codable, CaseIterable {
        case parking = "parking"
        case entrance = "entrance"
        case kids = "kids"
        case accessibility = "accessibility"
        case culture = "culture"
        case service = "service"
        case general = "general"
        
        var displayName: String {
            switch self {
            case .parking: return "Parking"
            case .entrance: return "Entrance"
            case .kids: return "Kids/Youth"
            case .accessibility: return "Accessibility"
            case .culture: return "Culture"
            case .service: return "Service"
            case .general: return "General"
            }
        }
        
        var icon: String {
            switch self {
            case .parking: return "car.fill"
            case .entrance: return "door.left.hand.open"
            case .kids: return "figure.2.and.child.holdinghands"
            case .accessibility: return "figure.roll"
            case .culture: return "heart.fill"
            case .service: return "clock.fill"
            case .general: return "info.circle.fill"
            }
        }
    }
}

// MARK: - Church Search Result

/// Church search/autocomplete result
struct ChurchSearchResult: Identifiable {
    let id: String
    let church: ChurchEntity?  // If already in our system
    let name: String
    let address: String
    let city: String
    let distance: Double?
    let placeId: String?  // Google Places ID
    let isExisting: Bool  // True if in Firestore already
    
    // For new churches from Google Places
    var photoReference: String?
}

// MARK: - Deep Link

/// Deep link to church profile
struct ChurchDeepLink {
    let churchId: String
    
    var url: URL? {
        URL(string: "amen://church/\(churchId)")
    }
    
    static func parse(_ url: URL) -> String? {
        guard url.scheme == "amen",
              url.host == "church",
              url.pathComponents.count > 1 else {
            return nil
        }
        return url.pathComponents[1]
    }
}

// MARK: - Church Mention

/// For @ mentions in composer
struct ChurchMention: Identifiable, Hashable {
    let id: String
    let churchId: String
    let name: String
    let city: String
    let range: NSRange  // Text range in composer
    
    static func == (lhs: ChurchMention, rhs: ChurchMention) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
