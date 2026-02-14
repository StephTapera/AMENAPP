//
//  PremiumUpgradeView.swift
//  AMENAPP
//
//  Enhanced premium upgrade sheet with StoreKit 2
//  Black & White Liquid Glass Design for Berean Pro
//

import SwiftUI
import StoreKit

struct PremiumUpgradeView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var premiumManager = PremiumManager.shared
    @State private var selectedProduct: Product?
    @State private var animateGradient = false
    @State private var showingPurchaseSuccess = false
    @State private var showingRestoreSuccess = false

    var body: some View {
        NavigationStack {
            ZStack {
                // Liquid Glass: Black gradient background with subtle depth
                ZStack {
                    // Deep black base
                    LinearGradient(
                        colors: [
                            Color.black,
                            Color(white: 0.05),
                            Color.black
                        ],
                        startPoint: animateGradient ? .topLeading : .bottomLeading,
                        endPoint: animateGradient ? .bottomTrailing : .topTrailing
                    )
                    
                    // Liquid glass orbs - subtle white glows
                    GeometryReader { geometry in
                        ZStack {
                            // Top right glow
                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [
                                            Color.white.opacity(0.08),
                                            Color.white.opacity(0.03),
                                            Color.clear
                                        ],
                                        center: .center,
                                        startRadius: 50,
                                        endRadius: 300
                                    )
                                )
                                .frame(width: 600, height: 600)
                                .offset(x: geometry.size.width * 0.7, y: -150)
                                .blur(radius: 80)
                            
                            // Bottom left glow
                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [
                                            Color.white.opacity(0.06),
                                            Color.white.opacity(0.02),
                                            Color.clear
                                        ],
                                        center: .center,
                                        startRadius: 50,
                                        endRadius: 280
                                    )
                                )
                                .frame(width: 500, height: 500)
                                .offset(x: -120, y: geometry.size.height * 0.8)
                                .blur(radius: 70)
                        }
                    }
                }
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 4).repeatForever(autoreverses: true), value: animateGradient)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 28) {
                        // Hero Section - Minimalist Liquid Glass
                        VStack(spacing: 20) {
                            // Sparkles icon with white glow (Berean branding)
                            ZStack {
                                // Soft white glow
                                Circle()
                                    .fill(
                                        RadialGradient(
                                            colors: [
                                                Color.white.opacity(0.15),
                                                Color.white.opacity(0.05),
                                                Color.clear
                                            ],
                                            center: .center,
                                            startRadius: 0,
                                            endRadius: 60
                                        )
                                    )
                                    .frame(width: 120, height: 120)
                                    .blur(radius: 30)

                                // Glass morphism circle
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .frame(width: 90, height: 90)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                    )

                                Image(systemName: "sparkles")
                                    .font(.system(size: 42, weight: .light))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [Color.white, Color.white.opacity(0.8)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .symbolEffect(.pulse.byLayer, options: .repeating)
                            }

                            Text("Berean Pro")
                                .font(.custom("Georgia", size: 38))
                                .fontWeight(.light)
                                .foregroundStyle(.white)
                                .tracking(1)

                            Text("Unlimited AI Bible Study")
                                .font(.system(size: 16, weight: .regular))
                                .foregroundStyle(.white.opacity(0.6))
                                .tracking(0.5)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 30)

                        // Features - Liquid Glass Cards
                        VStack(spacing: 12) {
                            LiquidGlassFeatureRow(
                                icon: "infinity",
                                title: "Unlimited Messages",
                                description: "Ask as many questions as you want"
                            )

                            LiquidGlassFeatureRow(
                                icon: "sparkles",
                                title: "Advanced AI Features",
                                description: "Devotionals, study plans & analysis"
                            )

                            LiquidGlassFeatureRow(
                                icon: "book.closed.fill",
                                title: "Priority Support",
                                description: "Faster responses & dedicated help"
                            )

                            LiquidGlassFeatureRow(
                                icon: "arrow.triangle.2.circlepath",
                                title: "Conversation History",
                                description: "Save & sync across devices"
                            )

                            LiquidGlassFeatureRow(
                                icon: "bookmark.fill",
                                title: "Save Messages",
                                description: "Bookmark insights for later"
                            )

                            LiquidGlassFeatureRow(
                                icon: "square.and.arrow.up",
                                title: "Share to Feed",
                                description: "Share AI insights with community"
                            )
                        }
                        .padding(.horizontal, 20)

                        // Pricing Options
                        if premiumManager.isLoading {
                            ProgressView()
                                .scaleEffect(1.5)
                                .tint(.white)
                                .frame(height: 200)
                        } else if !premiumManager.products.isEmpty {
                            VStack(spacing: 12) {
                                if let monthly = premiumManager.getMonthlyProduct() {
                                    PricingCard(
                                        product: monthly,
                                        isSelected: selectedProduct?.id == monthly.id,
                                        badge: nil,
                                        onSelect: { selectedProduct = monthly }
                                    )
                                }

                                if let yearly = premiumManager.getYearlyProduct() {
                                    PricingCard(
                                        product: yearly,
                                        isSelected: selectedProduct?.id == yearly.id,
                                        badge: "SAVE 40%",
                                        onSelect: { selectedProduct = yearly }
                                    )
                                }

                                if let lifetime = premiumManager.getLifetimeProduct() {
                                    PricingCard(
                                        product: lifetime,
                                        isSelected: selectedProduct?.id == lifetime.id,
                                        badge: "BEST VALUE",
                                        onSelect: { selectedProduct = lifetime }
                                    )
                                }
                            }
                            .padding(.horizontal)
                        }

                        // CTA Button - Liquid Glass Style
                        Button {
                            guard let product = selectedProduct else { return }
                            Task {
                                let success = await premiumManager.purchase(product)
                                if success {
                                    showingPurchaseSuccess = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                        dismiss()
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 16, weight: .medium))
                                Text(premiumManager.isLoading ? "Loading..." : "Upgrade to Pro")
                                    .font(.system(size: 17, weight: .semibold))
                                    .tracking(0.3)
                            }
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(
                                ZStack {
                                    // White background with subtle gradient
                                    LinearGradient(
                                        colors: [Color.white, Color(white: 0.95)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                    
                                    // Subtle shimmer effect
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.0),
                                            Color.white.opacity(0.3),
                                            Color.white.opacity(0.0)
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                }
                            )
                            .cornerRadius(16)
                            .shadow(color: .white.opacity(0.3), radius: 20, y: 8)
                        }
                        .disabled(selectedProduct == nil || premiumManager.isLoading)
                        .opacity((selectedProduct == nil || premiumManager.isLoading) ? 0.5 : 1.0)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                        // Restore button
                        Button {
                            Task {
                                let success = await premiumManager.restorePurchases()
                                if success {
                                    showingRestoreSuccess = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                        dismiss()
                                    }
                                }
                            }
                        } label: {
                            Text("Restore Purchases")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        .padding(.top, 8)

                        // Legal text
                        Text("7-day free trial, then \(selectedProduct?.displayPrice ?? "$4.99")/month. Cancel anytime.")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.white.opacity(0.4))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                            .padding(.top, 4)

                        // Error message
                        if let error = premiumManager.purchaseError {
                            Text(error)
                                .font(.custom("OpenSans-SemiBold", size: 14))
                                .foregroundStyle(.red)
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(.red.opacity(0.1))
                                )
                                .padding(.horizontal)
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                            .frame(width: 32, height: 32)
                            .background(
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                                    )
                            )
                    }
                }
            }
            .overlay {
                if showingPurchaseSuccess {
                    SuccessOverlay(message: "Welcome to Pro! 🎉")
                }
                if showingRestoreSuccess {
                    SuccessOverlay(message: "Purchases Restored! ✅")
                }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            animateGradient = true
            await premiumManager.loadProducts()
            // Auto-select yearly plan
            selectedProduct = premiumManager.getYearlyProduct() ?? premiumManager.getMonthlyProduct()
        }
    }
}

// MARK: - Liquid Glass Feature Row

struct LiquidGlassFeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 14) {
            // Icon with glass effect
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 44, height: 44)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )

                Image(systemName: icon)
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(.white.opacity(0.9))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)
                    .tracking(0.2)

                Text(description)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.white.opacity(0.5))
            }

            Spacer()
            
            // Checkmark
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.15),
                                    Color.white.opacity(0.05)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
    }
}

// MARK: - Liquid Glass Pricing Card

struct PricingCard: View {
    let product: Product
    let isSelected: Bool
    let badge: String?
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(product.displayName)
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(.white)
                            .tracking(0.3)

                        if let badge = badge {
                            Text(badge)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .tracking(0.5)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule()
                                        .fill(.white.opacity(0.2))
                                        .overlay(
                                            Capsule()
                                                .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
                                        )
                                )
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(product.displayPrice)
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(.white)
                        
                        if product.id.contains("monthly") {
                            Text("/month")
                                .font(.system(size: 12, weight: .regular))
                                .foregroundStyle(.white.opacity(0.5))
                        } else if product.id.contains("yearly") {
                            Text("/year")
                                .font(.system(size: 12, weight: .regular))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                }

                Text(product.description)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(2)
            }
            .padding(20)
            .background(
                ZStack {
                    // Glass morphism base
                    RoundedRectangle(cornerRadius: 18)
                        .fill(.ultraThinMaterial)
                    
                    // Selected state: White glow
                    if isSelected {
                        RoundedRectangle(cornerRadius: 18)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.12),
                                        Color.white.opacity(0.06)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    
                    // Border
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(
                            LinearGradient(
                                colors: isSelected ? 
                                    [Color.white.opacity(0.4), Color.white.opacity(0.2)] :
                                    [Color.white.opacity(0.15), Color.white.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: isSelected ? 1.5 : 1
                        )
                }
            )
            .shadow(color: isSelected ? .white.opacity(0.2) : .black.opacity(0.3), radius: isSelected ? 15 : 10, y: 5)
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - Success Overlay

struct SuccessOverlay: View {
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)

            Text(message)
                .font(.custom("OpenSans-Bold", size: 20))
                .foregroundStyle(.white)
        }
        .padding(40)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)
        )
        .transition(.scale.combined(with: .opacity))
    }
}
