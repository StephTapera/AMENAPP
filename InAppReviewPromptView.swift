//
//  InAppReviewPromptView.swift
//  AMENAPP
//
//  Premium in-app rating prompt modal
//  Threads-style design with iOS native feel
//

import SwiftUI

/// A beautiful, native-feeling in-app review prompt overlay
/// Appears as a centered modal card above the current content
struct InAppReviewPromptView: View {
    
    // MARK: - Binding
    
    /// Controls visibility of the prompt
    @Binding var isPresented: Bool
    
    // MARK: - State
    
    /// Current star rating (0 = none selected)
    @State private var selectedRating: Int = 0
    
    /// Animation state for smooth appearance
    @State private var isAnimatingIn = false
    
    // MARK: - Constants
    
    private let cardWidth: CGFloat = 320
    private let cardCornerRadius: CGFloat = 24
    private let appIconSize: CGFloat = 64
    
    var body: some View {
        ZStack {
            // Dimmed blurred background
            backgroundOverlay
            
            // Rating card
            ratingCard
                .scaleEffect(isAnimatingIn ? 1.0 : 0.9)
                .opacity(isAnimatingIn ? 1.0 : 0.0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                isAnimatingIn = true
            }
        }
    }
    
    // MARK: - Background
    
    private var backgroundOverlay: some View {
        Color.black.opacity(0.3)
            .ignoresSafeArea()
            .overlay(
                // Subtle blur effect
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(0.1)
                    .ignoresSafeArea()
            )
            .onTapGesture {
                dismissPrompt()
            }
            .accessibilityLabel("Background")
            .accessibilityHint("Tap to dismiss rating prompt")
    }
    
    // MARK: - Rating Card
    
    private var ratingCard: some View {
        VStack(spacing: 0) {
            // App icon and title section
            headerSection
                .padding(.top, 32)
                .padding(.horizontal, 24)
            
            // Star rating row
            StarRatingRow(
                rating: $selectedRating,
                starSize: 36,
                starColor: .blue,
                spacing: 16,
                onRatingChanged: { rating in
                    handleRatingChanged(rating)
                }
            )
            .padding(.top, 24)
            .padding(.horizontal, 24)
            
            // Not Now button
            notNowButton
                .padding(.top, 32)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
        .frame(width: cardWidth)
        .background(
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.15), radius: 30, y: 10)
        )
        .accessibilityElement(children: .contain)
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 16) {
            // App icon
            appIcon
            
            // Title
            Text("Growing in faith with AMEN?")
                .font(.custom("OpenSans-Bold", size: 20))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            
            // Subtitle
            Text("Tap a star to rate it on the App Store.")
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
    
    // MARK: - App Icon
    
    private var appIcon: some View {
        ZStack {
            // Background circle
            Circle()
                .fill(Color(.systemGray6))
                .frame(width: appIconSize, height: appIconSize)
            
            // App icon or logo
            // TODO: Replace with actual app icon asset
            Image(systemName: "flame.fill")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.orange, .red],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .accessibilityHidden(true)
    }
    
    // MARK: - Not Now Button
    
    private var notNowButton: some View {
        Button {
            dismissWithFeedback()
        } label: {
            Text("Not Now")
                .font(.custom("OpenSans-Bold", size: 17))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(Color(.systemGray5))
                )
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel("Not now")
        .accessibilityHint("Dismiss the rating prompt")
    }
    
    // MARK: - Actions
    
    /// Handle star rating selection
    private func handleRatingChanged(_ rating: Int) {
        // Wait a moment for the star animation to complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if rating >= 4 {
                // High rating: Request native StoreKit review
                ReviewPromptManager.shared.requestNativeReview()
            } else {
                // Low rating: Open feedback form or direct to support
                // TODO: Implement feedback flow for low ratings
                dlog("⭐️ User gave \(rating) stars - could show feedback form")
                ReviewPromptManager.shared.userDidRate()
            }
            
            // Dismiss the prompt
            dismissPrompt()
        }
    }
    
    /// Dismiss with haptic feedback
    private func dismissWithFeedback() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        ReviewPromptManager.shared.userDidDismiss()
        dismissPrompt()
    }
    
    /// Dismiss the prompt with animation
    private func dismissPrompt() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isAnimatingIn = false
        }
        
        // Complete dismissal after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            isPresented = false
            selectedRating = 0
        }
    }
}

// MARK: - Preview
#Preview {
    ZStack {
        // Mock feed content
        ScrollView {
            VStack(spacing: 20) {
                ForEach(0..<5) { _ in
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray6))
                        .frame(height: 200)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        
        // Rating prompt overlay
        InAppReviewPromptView(isPresented: .constant(true))
    }
}
