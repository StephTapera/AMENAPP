//
//  PrayerWallView.swift
//  AMENAPP
//
//  Created by Steph on 1/16/26.
//
// NOTE: This file contains the old map-based prayer wall.
// The actual PrayerWallView is now in PrayerView.swift
// This file is kept for reference and can be deleted.

import SwiftUI
import MapKit

/// DEPRECATED: Old Prayer Wall with map - No longer used
/// Use PrayerWallView in PrayerView.swift instead
struct PrayerWallMapView_DEPRECATED: View {
    @Binding var isShowing: Bool
    @State private var selectedCategory: PrayerCategory? = nil
    @State private var selectedPin: PrayerPin? = nil
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 20, longitude: 0),
        span: MKCoordinateSpan(latitudeDelta: 120, longitudeDelta: 120)
    )
    
    enum PrayerCategory: String, CaseIterable {
        case all = "All"
        case requests = "Requests"
        case praises = "Praises"
        case answered = "Answered"
        
        var color: Color {
            switch self {
            case .all: return .white
            case .requests: return Color(red: 0.4, green: 0.7, blue: 1.0)
            case .praises: return Color(red: 1.0, green: 0.7, blue: 0.4)
            case .answered: return Color(red: 0.4, green: 0.85, blue: 0.7)
            }
        }
        
        var icon: String {
            switch self {
            case .all: return "globe.americas.fill"
            case .requests: return "hands.sparkles.fill"
            case .praises: return "hands.clap.fill"
            case .answered: return "checkmark.seal.fill"
            }
        }
    }
    
    // Sample prayer pins
    let prayerPins: [PrayerPin] = [
        PrayerPin(
            location: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060),
            city: "New York, USA",
            content: "Praying for revival in our city",
            author: "Pastor Michael",
            category: PrayerWallMapView_DEPRECATED.PrayerCategory.requests,
            prayerCount: 156
        ),
        PrayerPin(
            location: CLLocationCoordinate2D(latitude: 51.5074, longitude: -0.1278),
            city: "London, UK",
            content: "God healed my mother!",
            author: "Sarah J.",
            category: PrayerWallMapView_DEPRECATED.PrayerCategory.answered,
            prayerCount: 234
        ),
        PrayerPin(
            location: CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503),
            city: "Tokyo, Japan",
            content: "First church service in our neighborhood!",
            author: "Missionary Chen",
            category: PrayerWallMapView_DEPRECATED.PrayerCategory.praises,
            prayerCount: 89
        ),
        PrayerPin(
            location: CLLocationCoordinate2D(latitude: -33.8688, longitude: 151.2093),
            city: "Sydney, Australia",
            content: "Teen son came back to faith",
            author: "Anna M.",
            category: PrayerWallMapView_DEPRECATED.PrayerCategory.answered,
            prayerCount: 178
        ),
        PrayerPin(
            location: CLLocationCoordinate2D(latitude: -1.2921, longitude: 36.8219),
            city: "Nairobi, Kenya",
            content: "Need clean water for village",
            author: "Pastor Joseph",
            category: PrayerWallMapView_DEPRECATED.PrayerCategory.requests,
            prayerCount: 267
        ),
        PrayerPin(
            location: CLLocationCoordinate2D(latitude: 19.4326, longitude: -99.1332),
            city: "Mexico City, Mexico",
            content: "Youth ministry growing rapidly!",
            author: "Carlos & Maria",
            category: PrayerWallMapView_DEPRECATED.PrayerCategory.praises,
            prayerCount: 143
        ),
        PrayerPin(
            location: CLLocationCoordinate2D(latitude: -23.5505, longitude: -46.6333),
            city: "São Paulo, Brazil",
            content: "Financial breakthrough for church building",
            author: "Pastor Luis",
            category: PrayerWallMapView_DEPRECATED.PrayerCategory.answered,
            prayerCount: 312
        ),
        PrayerPin(
            location: CLLocationCoordinate2D(latitude: 55.7558, longitude: 37.6173),
            city: "Moscow, Russia",
            content: "Pray for religious freedom",
            author: "Anonymous",
            category: PrayerWallMapView_DEPRECATED.PrayerCategory.requests,
            prayerCount: 445
        ),
        PrayerPin(
            location: CLLocationCoordinate2D(latitude: 28.6139, longitude: 77.2090),
            city: "New Delhi, India",
            content: "50 new believers baptized!",
            author: "Missionary Team",
            category: PrayerWallMapView_DEPRECATED.PrayerCategory.praises,
            prayerCount: 523
        ),
        PrayerPin(
            location: CLLocationCoordinate2D(latitude: 1.3521, longitude: 103.8198),
            city: "Singapore",
            content: "University campus ministry launched",
            author: "Student Leader Ryan",
            category: PrayerWallMapView_DEPRECATED.PrayerCategory.praises,
            prayerCount: 167
        )
    ]
    
    var filteredPins: [PrayerPin] {
        guard let category = selectedCategory, category != .all else {
            return prayerPins
        }
        return prayerPins.filter { $0.category == category }
    }
    
    var body: some View {
        ZStack {
            // Map background
            Color.black
                .ignoresSafeArea()
            
            // Dark world map (you'd use actual MapKit here)
            // For now, using a simple representation
            ZStack {
                // Simulated map
                Rectangle()
                    .fill(Color(white: 0.08))
                    .ignoresSafeArea()
                
                // Prayer pins overlay
                GeometryReader { geometry in
                    ForEach(filteredPins) { pin in
                        PrayerPinView(pin: pin, isSelected: selectedPin?.id == pin.id)
                            .position(
                                x: longitudeToX(pin.location.longitude, width: geometry.size.width),
                                y: latitudeToY(pin.location.latitude, height: geometry.size.height)
                            )
                            .onTapGesture {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                    selectedPin = pin
                                }
                            }
                    }
                }
            }
            
            // Top header
            VStack {
                headerView
                
                Spacer()
            }
            
            // Bottom controls
            VStack {
                Spacer()
                
                if let pin = selectedPin {
                    selectedPrayerCard(pin: pin)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    categoryFilters
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            
            // Random prayer button (floating)
            if selectedPin == nil {
                VStack {
                    Spacer()
                    
                    HStack {
                        Spacer()
                        
                        Button {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                selectedPin = prayerPins.randomElement()
                            }
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: "shuffle")
                                    .font(.system(size: 20, weight: .semibold))
                                
                                Text("Random")
                                    .font(.custom("OpenSans-Bold", size: 11))
                            }
                            .foregroundStyle(.white)
                            .frame(width: 70, height: 70)
                            .background(
                                Circle()
                                    .fill(Color(red: 0.6, green: 0.5, blue: 1.0))
                                    .shadow(color: .black.opacity(0.3), radius: 15, y: 5)
                            )
                        }
                        .padding(.trailing, 24)
                        .padding(.bottom, 180)
                    }
                }
            }
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Prayer Wall")
                    .font(.custom("OpenSans-Bold", size: 26))
                    .foregroundStyle(.white)
                
                Text("\(filteredPins.count) prayers around the world")
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(.white.opacity(0.6))
            }
            
            Spacer()
            
            Button {
                withAnimation(.smooth(duration: 0.3)) {
                    isShowing = false
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .background(
            Color.black.opacity(0.6)
                .background(.ultraThinMaterial.opacity(0.3))
        )
    }
    
    // MARK: - Category Filters
    
    private var categoryFilters: some View {
        VStack(spacing: 16) {
            // Stats overview
            HStack(spacing: 16) {
                StatCard_Deprecated(
                    icon: "hands.sparkles.fill",
                    count: prayerPins.filter { $0.category == PrayerWallMapView_DEPRECATED.PrayerCategory.requests }.count,
                    label: "Requests",
                    color: Color(red: 0.4, green: 0.7, blue: 1.0)
                )
                
                StatCard_Deprecated(
                    icon: "hands.clap.fill",
                    count: prayerPins.filter { $0.category == PrayerWallMapView_DEPRECATED.PrayerCategory.praises }.count,
                    label: "Praises",
                    color: Color(red: 1.0, green: 0.7, blue: 0.4)
                )
                
                StatCard_Deprecated(
                    icon: "checkmark.seal.fill",
                    count: prayerPins.filter { $0.category == PrayerWallMapView_DEPRECATED.PrayerCategory.answered }.count,
                    label: "Answered",
                    color: Color(red: 0.4, green: 0.85, blue: 0.7)
                )
            }
            .padding(.horizontal, 24)
            
            // Category selector
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(PrayerCategory.allCases, id: \.self) { category in
                        CategoryButton(
                            category: category,
                            isSelected: selectedCategory == category,
                            onSelect: {
                                withAnimation(.smooth(duration: 0.3)) {
                                    selectedCategory = category
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal, 24)
            }
        }
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(white: 0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.5), radius: 30, y: -10)
                .ignoresSafeArea(edges: .bottom)
        )
    }
    
    // MARK: - Selected Prayer Card
    
    private func selectedPrayerCard(pin: PrayerPin) -> some View {
        VStack(spacing: 0) {
            // Handle
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.white.opacity(0.3))
                .frame(width: 36, height: 5)
                .padding(.top, 12)
            
            VStack(alignment: .leading, spacing: 16) {
                // Header with location
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(pin.category.color.opacity(0.15))
                            .frame(width: 50, height: 50)
                        
                        Image(systemName: pin.category.icon)
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(pin.category.color)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(pin.city)
                            .font(.custom("OpenSans-Bold", size: 16))
                            .foregroundStyle(.white)
                        
                        Text(pin.author)
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    
                    Spacer()
                    
                    Button {
                        withAnimation(.smooth(duration: 0.3)) {
                            selectedPin = nil
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                
                // Prayer content
                Text(pin.content)
                    .font(.custom("OpenSans-Regular", size: 16))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineSpacing(6)
                    .padding(.horizontal, 24)
                
                // Stats and actions
                HStack(spacing: 24) {
                    HStack(spacing: 8) {
                        Image(systemName: "hands.sparkles.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.white.opacity(0.6))
                        
                        Text("\(pin.prayerCount) praying")
                            .font(.custom("OpenSans-SemiBold", size: 13))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 24)
                
                // Action buttons
                HStack(spacing: 12) {
                    Button {
                        // Pray for this request
                        let haptic = UINotificationFeedbackGenerator()
                        haptic.notificationOccurred(.success)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "hands.sparkles.fill")
                                .font(.system(size: 16, weight: .semibold))
                            
                            Text("I'm Praying")
                                .font(.custom("OpenSans-Bold", size: 15))
                        }
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(.white)
                        )
                    }
                    
                    Button {
                        // Share
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 50, height: 50)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color.white.opacity(0.15))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14)
                                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                    )
                            )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 30)
            }
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(white: 0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.5), radius: 30, y: -10)
                .ignoresSafeArea(edges: .bottom)
        )
    }
    
    // MARK: - Helper Functions
    
    private func longitudeToX(_ longitude: Double, width: CGFloat) -> CGFloat {
        return CGFloat((longitude + 180) / 360) * width
    }
    
    private func latitudeToY(_ latitude: Double, height: CGFloat) -> CGFloat {
        // Mercator projection approximation
        let latRad = latitude * .pi / 180
        let mercN = log(tan(.pi / 4 + latRad / 2))
        let y = (1 - mercN / .pi) / 2
        return CGFloat(y) * height
    }
}

// MARK: - Prayer Pin Model

struct PrayerPin: Identifiable {
    let id = UUID()
    let location: CLLocationCoordinate2D
    let city: String
    let content: String
    let author: String
    let category: PrayerWallMapView_DEPRECATED.PrayerCategory
    let prayerCount: Int
}

// MARK: - Prayer Pin View

struct PrayerPinView: View {
    let pin: PrayerPin
    let isSelected: Bool
    
    var body: some View {
        ZStack {
            // Pulsing glow
            Circle()
                .fill(pin.category.color.opacity(0.3))
                .frame(width: isSelected ? 40 : 24, height: isSelected ? 40 : 24)
                .blur(radius: 10)
                .scaleEffect(isSelected ? 1.2 : 1.0)
            
            // Pin
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: isSelected ? 32 : 20, weight: .medium))
                .foregroundStyle(pin.category.color)
                .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)
    }
}

// MARK: - Stat Card

private struct StatCard_Deprecated: View {
    let icon: String
    let count: Int
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(color)
                
                Text("\(count)")
                    .font(.custom("OpenSans-Bold", size: 18))
                    .foregroundStyle(.white)
            }
            
            Text(label)
                .font(.custom("OpenSans-SemiBold", size: 11))
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }
}

// MARK: - Category Button

struct CategoryButton: View {
    let category: PrayerWallMapView_DEPRECATED.PrayerCategory
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Image(systemName: category.icon)
                    .font(.system(size: 14, weight: .medium))
                
                Text(category.rawValue)
                    .font(.custom("OpenSans-SemiBold", size: 14))
            }
            .foregroundStyle(isSelected ? .black : category.color)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(isSelected ? category.color : Color.white.opacity(0.08))
                    .overlay(
                        Capsule()
                            .stroke(isSelected ? Color.clear : category.color.opacity(0.4), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    PrayerWallMapView_DEPRECATED(isShowing: .constant(true))
}
