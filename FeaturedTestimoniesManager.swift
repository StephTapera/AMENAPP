//
//  FeaturedTestimoniesManager.swift
//  AMENAPP
//
//  Created by Steph on 1/15/26.
//

import SwiftUI
import Foundation
import Combine

// MARK: - Featured Testimony Category Name
// This enum represents category names for the rotation system
// It maps to the existing TestimonyCategory structs in ContentView
enum FeaturedCategoryName: String, CaseIterable, Hashable {
    case healing = "Healing"
    case career = "Career"
    case relationship = "Relationships"
    case financial = "Financial"
    case spiritual = "Spiritual Growth"
    case family = "Family"
}

// MARK: - Featured Testimonies Manager
/// Manages the "Featured This Week" rotation system for testimonies

@MainActor
class FeaturedTestimoniesManager: ObservableObject {
    @Published var currentFeaturedCategories: [FeaturedCategoryName] = []
    @Published var rotationInfo: RotationInfo?
    
    // All possible category combinations for rotation (using the existing 6 categories)
    private let featuredRotations: [[FeaturedCategoryName]] = [
        [.healing, .career],
        [.relationship, .financial],
        [.spiritual, .family],
        [.healing, .spiritual],
        [.career, .relationship],
        [.family, .financial]
    ]
    
    init() {
        updateFeaturedCategories()
    }
    
    /// Updates featured categories based on current week
    func updateFeaturedCategories() {
        let weekNumber = currentWeekNumber()
        let rotationIndex = weekNumber % featuredRotations.count
        
        currentFeaturedCategories = featuredRotations[rotationIndex]
        rotationInfo = RotationInfo(
            weekNumber: weekNumber,
            nextRotationDate: nextRotationDate(),
            daysUntilRotation: daysUntilRotation()
        )
    }
    
    /// Gets current week number of the year
    private func currentWeekNumber() -> Int {
        let calendar = Calendar.current
        return calendar.component(.weekOfYear, from: Date())
    }
    
    /// Calculates next rotation date (next Sunday at midnight)
    private func nextRotationDate() -> Date {
        let calendar = Calendar.current
        let today = Date()
        
        // Find next Sunday
        var components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)
        components.weekday = 1 // Sunday
        components.weekOfYear = (components.weekOfYear ?? 0) + 1
        
        return calendar.date(from: components) ?? today
    }
    
    /// Days until next rotation
    private func daysUntilRotation() -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let nextRotation = calendar.startOfDay(for: nextRotationDate())
        
        let components = calendar.dateComponents([.day], from: today, to: nextRotation)
        return components.day ?? 0
    }
    
    /// Check if category name is currently featured
    func isFeatured(_ categoryName: FeaturedCategoryName) -> Bool {
        currentFeaturedCategories.contains(categoryName)
    }
}

// MARK: - Rotation Info Model
struct RotationInfo {
    let weekNumber: Int
    let nextRotationDate: Date
    let daysUntilRotation: Int
    
    var formattedNextRotation: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: nextRotationDate)
    }
}

// MARK: - Featured Badge View
struct FeaturedBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "star.fill")
                .font(.system(size: 10))
                .foregroundColor(.yellow)
            
            Text("FEATURED")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(0.5)
                .foregroundColor(.white)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Color.orange, Color.red],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .shadow(color: .orange.opacity(0.5), radius: 8, y: 2)
        )
    }
}

// MARK: - Rotation Countdown View
struct RotationCountdownView: View {
    let rotationInfo: RotationInfo
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.6))
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Featured This Week")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
                
                Text("Rotates in \(rotationInfo.daysUntilRotation) days • \(rotationInfo.formattedNextRotation)")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }
}

// MARK: - Alternative Featured Systems

/// Option 2: AI-Powered Featured Selection
class AIFeaturedManager: ObservableObject {
    @Published var featuredCategories: [FeaturedCategoryName] = []
    
    /// Selects categories based on user engagement and trending
    func updateFeaturedCategories(
        userInterests: [FeaturedCategoryName],
        trendingCategories: [FeaturedCategoryName: Int]
    ) {
        // Combine user interests with trending
        var scores: [FeaturedCategoryName: Double] = [:]
        
        // Score based on user interests (weight: 0.6)
        for category in userInterests {
            scores[category, default: 0] += 0.6
        }
        
        // Score based on trending (weight: 0.4)
        let maxTrending = trendingCategories.values.max() ?? 1
        for (category, count) in trendingCategories {
            scores[category, default: 0] += 0.4 * (Double(count) / Double(maxTrending))
        }
        
        // Select top 2 categories
        featuredCategories = scores.sorted { $0.value > $1.value }
            .prefix(2)
            .map { $0.key }
    }
}

/// Option 3: Seasonal Featured Selection
class SeasonalFeaturedManager: ObservableObject {
    @Published var featuredCategories: [FeaturedCategoryName] = []
    @Published var seasonalTheme: String = ""
    
    func updateFeaturedCategories() {
        let month = Calendar.current.component(.month, from: Date())
        
        switch month {
        case 1: // January - New Year
            featuredCategories = [.spiritual, .career]
            seasonalTheme = "New Beginnings"
            
        case 2: // February - Love
            featuredCategories = [.relationship, .healing]
            seasonalTheme = "Love & Restoration"
            
        case 3, 4: // March-April - Spring/Easter
            featuredCategories = [.spiritual, .family]
            seasonalTheme = "Resurrection Power"
            
        case 5: // May - Mothers
            featuredCategories = [.healing, .family]
            seasonalTheme = "Family Blessings"
            
        case 6: // June - Fathers
            featuredCategories = [.career, .family]
            seasonalTheme = "Fatherhood & Leadership"
            
        case 7, 8: // July-August - Summer
            featuredCategories = [.spiritual, .financial]
            seasonalTheme = "Summer Harvest"
            
        case 9, 10: // September-October - Back to School/Fall
            featuredCategories = [.career, .spiritual]
            seasonalTheme = "Fresh Start"
            
        case 11: // November - Thanksgiving
            featuredCategories = [.financial, .family]
            seasonalTheme = "Gratitude Season"
            
        case 12: // December - Christmas
            featuredCategories = [.healing, .relationship]
            seasonalTheme = "Year-End Miracles"
            
        default:
            featuredCategories = [.healing, .spiritual]
            seasonalTheme = "God's Faithfulness"
        }
    }
}

// MARK: - Usage Example in TestimoniesView

/*
 
 // In ContentView.swift's TestimoniesView:
 
 struct TestimoniesView: View {
     @StateObject private var featuredManager = FeaturedTestimoniesManager()
     @State private var showQuickTestimony = false
     
     // Convert featured category names to actual TestimonyCategory objects
     private var featuredCategories: [TestimonyCategory] {
         featuredManager.currentFeaturedCategories.compactMap { categoryName in
             switch categoryName {
             case .healing: return .healing
             case .career: return .career
             case .relationship: return .relationship
             case .financial: return .financial
             case .spiritual: return .spiritual
             case .family: return .family
             }
         }
     }
     
     var body: some View {
         VStack(alignment: .leading, spacing: 20) {
             // Header with Quick Testimony Button
             HStack {
                 Text("Testimonies")
                     .font(.custom("OpenSans-Bold", size: 24))
                 
                 Spacer()
                 
                 // QUICK TESTIMONY BUTTON
                 Button {
                     showQuickTestimony = true
                 } label: {
                     Image(systemName: "plus.circle.fill")
                         .font(.system(size: 28))
                         .foregroundStyle(
                             LinearGradient(
                                 colors: [.pink, .purple],
                                 startPoint: .topLeading,
                                 endPoint: .bottomTrailing
                             )
                         )
                 }
             }
             .padding(.horizontal)
             
             // Rotation Countdown
             if let rotationInfo = featuredManager.rotationInfo {
                 RotationCountdownView(rotationInfo: rotationInfo)
                     .padding(.horizontal)
             }
             
             // Featured Categories - uses the computed property above
             HStack(spacing: 12) {
                 ForEach(featuredCategories) { category in
                     CommunityCard(
                         icon: category.icon,
                         iconColor: category.color,
                         title: category.title,
                         subtitle: category.subtitle,
                         backgroundColor: category.backgroundColor
                     )
                 }
             }
             .padding(.horizontal)
         }
         .sheet(isPresented: $showQuickTestimony) {
             QuickTestimonyView()
         }
         .onAppear {
             featuredManager.updateFeaturedCategories()
         }
     }
 }
 
 */

#Preview("Featured Badge") {
    ZStack {
        Color.black.ignoresSafeArea()
        FeaturedBadge()
    }
}

#Preview("Rotation Countdown") {
    ZStack {
        Color.black.ignoresSafeArea()
        RotationCountdownView(
            rotationInfo: RotationInfo(
                weekNumber: 3,
                nextRotationDate: Date().addingTimeInterval(86400 * 5),
                daysUntilRotation: 5
            )
        )
        .padding()
    }
}
