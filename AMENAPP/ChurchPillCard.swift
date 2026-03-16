//
//  ChurchPillCard.swift
//  AMENAPP
//
//  Clickable church pills/cards for posts, notes, messages
//  Consistent design across the app
//

import SwiftUI
import CoreLocation

// MARK: - Church Pill (Inline)

/// Small inline pill for church mentions
struct ChurchPill: View {
    let church: ChurchEntity
    let userLocation: CLLocation?
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                // Church icon/photo
                if let photoURL = church.photoURL {
                    CachedAsyncImage(url: URL(string: photoURL)) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        churchIconPlaceholder
                    }
                    .frame(width: 24, height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    churchIconPlaceholder
                        .frame(width: 24, height: 24)
                }
                
                // Church name
                Text(church.name)
                    .font(.custom("OpenSans-SemiBold", size: 14))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                
                // Distance + city
                if let location = userLocation {
                    Text("• \(church.distanceString(from: location)) • \(church.city)")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("• \(church.city)")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
    
    private var churchIconPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.blue.opacity(0.1))
            
            Image(systemName: "building.columns.fill")
                .font(.system(size: 12))
                .foregroundStyle(.blue)
        }
    }
}

// MARK: - Church Card (Expanded)

/// Larger card for prominent church display
struct ChurchEntityCard: View {
    let church: ChurchEntity
    let userLocation: CLLocation?
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                // Header with photo
                HStack(spacing: 12) {
                    // Church photo/logo
                    if let photoURL = church.photoURL {
                        CachedAsyncImage(url: URL(string: photoURL)) { image in
                            image
                                .resizable()
                                .scaledToFill()
                        } placeholder: {
                            churchPhotoPlaceholder
                        }
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        churchPhotoPlaceholder
                            .frame(width: 64, height: 64)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(church.name)
                            .font(.custom("OpenSans-Bold", size: 16))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        
                        if let denomination = church.denomination {
                            Text(denomination)
                                .font(.custom("OpenSans-Regular", size: 13))
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Spacer()
                }
                
                // Location info
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.blue)
                        
                        if let location = userLocation {
                            Text("\(church.distanceString(from: location)) away")
                                .font(.custom("OpenSans-SemiBold", size: 13))
                                .foregroundStyle(.blue)
                        }
                    }
                    
                    Text("\(church.city), \(church.state ?? "")")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                }
                
                // Quick actions
                HStack(spacing: 16) {
                    if church.phoneNumber != nil {
                        quickActionButton(icon: "phone.fill", label: "Call")
                    }
                    
                    quickActionButton(icon: "location.fill", label: "Directions")
                    
                    quickActionButton(icon: "square.and.arrow.up", label: "Share")
                    
                    Spacer()
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
                    .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
            )
        }
        .buttonStyle(.plain)
    }
    
    private var churchPhotoPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: [.blue.opacity(0.2), .purple.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Image(systemName: "building.columns.fill")
                .font(.system(size: 28))
                .foregroundStyle(.blue)
        }
    }
    
    private func quickActionButton(icon: String, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11))
            
            Text(label)
                .font(.custom("OpenSans-SemiBold", size: 12))
        }
        .foregroundStyle(.blue)
    }
}

// MARK: - Church Search Result Row

/// Row for church search results
struct ChurchSearchResultRow: View {
    let result: ChurchSearchResult
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Icon
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.1))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: "building.columns.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.blue)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(result.name)
                        .font(.custom("OpenSans-SemiBold", size: 15))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    
                    HStack(spacing: 4) {
                        if let distance = result.distance {
                            Text(String(format: "%.1f mi", distance))
                                .font(.custom("OpenSans-Regular", size: 13))
                                .foregroundStyle(.secondary)
                            
                            Text("•")
                                .font(.custom("OpenSans-Regular", size: 13))
                                .foregroundStyle(.secondary)
                        }
                        
                        Text(result.city)
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                if result.isExisting {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.green)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview("Church Pill") {
    ChurchPill(
        church: ChurchEntity(
            id: "1",
            placeId: nil,
            name: "Redeemer Presbyterian",
            address: "123 Main St",
            city: "New York",
            state: "NY",
            zipCode: "10001",
            country: "USA",
            coordinate: ChurchEntity.GeoPoint(latitude: 40.7128, longitude: -74.0060),
            phoneNumber: nil,
            email: nil,
            website: nil,
            denomination: "Presbyterian",
            photoURL: nil,
            logoURL: nil,
            serviceTimes: [],
            memberCount: 150,
            visitCount: 45,
            tipCount: 12,
            createdAt: Date(),
            updatedAt: Date(),
            source: .googlePlaces
        ),
        userLocation: CLLocation(latitude: 40.7128, longitude: -74.0060),
        onTap: {}
    )
    .padding()
}

#Preview("Church Card") {
    ChurchEntityCard(
        church: ChurchEntity(
            id: "1",
            placeId: nil,
            name: "Redeemer Presbyterian Church",
            address: "123 Main St",
            city: "New York",
            state: "NY",
            zipCode: "10001",
            country: "USA",
            coordinate: ChurchEntity.GeoPoint(latitude: 40.7128, longitude: -74.0060),
            phoneNumber: "212-555-1234",
            email: nil,
            website: "https://redeemer.com",
            denomination: "Presbyterian",
            photoURL: nil,
            logoURL: nil,
            serviceTimes: [],
            memberCount: 150,
            visitCount: 45,
            tipCount: 12,
            createdAt: Date(),
            updatedAt: Date(),
            source: .googlePlaces
        ),
        userLocation: CLLocation(latitude: 40.7128, longitude: -74.0060),
        onTap: {}
    )
    .padding()
}
