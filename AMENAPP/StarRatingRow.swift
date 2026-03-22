//
//  StarRatingRow.swift
//  AMENAPP
//
//  Premium star rating component for in-app review prompts
//

import SwiftUI

/// A reusable row of 5 tappable star icons
/// Displays outlined stars that fill when tapped
struct StarRatingRow: View {
    /// Number of stars selected (0-5)
    @Binding var rating: Int
    
    /// Star size (default: 40pt for easy tapping)
    var starSize: CGFloat = 40
    
    /// Star color (iOS blue by default)
    var starColor: Color = .blue
    
    /// Spacing between stars
    var spacing: CGFloat = 12
    
    /// Callback when a star is tapped
    var onRatingChanged: ((Int) -> Void)?
    
    var body: some View {
        HStack(spacing: spacing) {
            ForEach(1...5, id: \.self) { index in
                starButton(for: index)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rate with \(rating) out of 5 stars")
        .accessibilityHint("Tap to select a rating")
    }
    
    /// Individual star button
    private func starButton(for index: Int) -> some View {
        Button {
            // Haptic feedback for premium feel
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
            
            // Set rating
            rating = index
            
            // Notify callback
            onRatingChanged?(index)
        } label: {
            Image(systemName: index <= rating ? "star.fill" : "star")
                .font(.system(size: starSize, weight: .medium))
                .foregroundStyle(starColor)
                .frame(width: starSize + 8, height: starSize + 8) // Larger tap target
                .contentShape(Rectangle()) // Entire area tappable
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(index == rating ? 1.15 : 1.0) // Subtle scale on selected
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: rating)
        .accessibilityLabel("\(index) stars")
        .accessibilityAddTraits(index == rating ? [.isSelected] : [])
    }
}

// MARK: - Preview
#Preview {
    VStack(spacing: 40) {
        StarRatingRow(rating: .constant(0))
        StarRatingRow(rating: .constant(3))
        StarRatingRow(rating: .constant(5))
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
