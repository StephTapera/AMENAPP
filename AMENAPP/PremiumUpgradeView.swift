//
//  PremiumUpgradeView.swift
//  AMENAPP
//
//  Enhanced premium upgrade sheet with StoreKit 2
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
                // Premium gradient background
                LinearGradient(
                    colors: [
                        Color(red: 0.1, green: 0.05, blue: 0.15),
                        Color(red: 0.15, green: 0.1, blue: 0.2),
                        Color.black
                    ],
                    startPoint: animateGradient ? .topLeading : .bottomLeading,
                    endPoint: animateGradient ? .bottomTrailing : .topTrailing
                )
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 3).repeatForever(autoreverses: true), value: animateGradient)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        // Hero Section
                        VStack(spacing: 16) {
                            // Crown icon with glow
                            ZStack {
                                Circle()
                                    .fill(
                                        RadialGradient(
                                            colors: [
                                                Color(red: 1.0, green: 0.6, blue: 0.0).opacity(0.4),
                                                Color.clear
                                            ],
                                            center: .center,
                                            startRadius: 0,
                                            endRadius: 50
                                        )
                                    )
                                    .frame(width: 100, height: 100)
                                    .blur(radius: 20)

                                Image(systemName: "crown.fill")
                                    .font(.system(size: 50, weight: .bold))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [Color(red: 1.0, green: 0.84, blue: 0.0), Color(red: 1.0, green: 0.6, blue: 0.0)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .symbolEffect(.pulse.byLayer, options: .repeating)
                            }

                            Text("Upgrade to Pro")
                                .font(.custom("OpenSans-Bold", size: 32))
                                .foregroundStyle(.white)

                            Text("Unlimited AI Bible Study\n& Premium Features")
                                .font(.custom("OpenSans-Regular", size: 16))
                                .foregroundStyle(.white.opacity(0.7))
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 20)

                        // Features
                        VStack(spacing: 16) {
                            PremiumFeatureRow(
                                icon: "infinity",
                                title: "Unlimited Messages",
                                description: "Ask as many questions as you want",
                                iconColor: .blue
                            )

                            PremiumFeatureRow(
                                icon: "sparkles",
                                title: "Advanced AI Features",
                                description: "Devotionals, study plans & analysis",
                                iconColor: .purple
                            )

                            PremiumFeatureRow(
                                icon: "book.closed.fill",
                                title: "Priority Support",
                                description: "Faster responses & dedicated help",
                                iconColor: .orange
                            )

                            PremiumFeatureRow(
                                icon: "arrow.triangle.2.circlepath",
                                title: "Conversation History",
                                description: "Save & sync across devices",
                                iconColor: .green
                            )

                            PremiumFeatureRow(
                                icon: "waveform",
                                title: "Voice Input",
                                description: "Ask questions with your voice",
                                iconColor: .pink
                            )

                            PremiumFeatureRow(
                                icon: "bell.badge.fill",
                                title: "Smart Notifications",
                                description: "Personalized study reminders",
                                iconColor: .cyan
                            )
                        }
                        .padding(.horizontal)

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

                        // CTA Button
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
                            HStack {
                                Image(systemName: "sparkles")
                                Text("Start Free Trial")
                                    .font(.custom("OpenSans-Bold", size: 18))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(
                                LinearGradient(
                                    colors: [Color(red: 1.0, green: 0.6, blue: 0.0), Color(red: 1.0, green: 0.4, blue: 0.2)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(16)
                            .shadow(color: Color(red: 1.0, green: 0.6, blue: 0.0).opacity(0.4), radius: 20, y: 10)
                        }
                        .disabled(selectedProduct == nil || premiumManager.isLoading)
                        .opacity((selectedProduct == nil || premiumManager.isLoading) ? 0.5 : 1.0)
                        .padding(.horizontal)

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
                                .font(.custom("OpenSans-SemiBold", size: 14))
                                .foregroundStyle(.white.opacity(0.6))
                        }

                        // Legal text
                        Text("7-day free trial, then \(selectedProduct?.displayPrice ?? "$4.99")/month. Cancel anytime.")
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(.white.opacity(0.5))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)

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
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.6))
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

// MARK: - Premium Feature Row

struct PremiumFeatureRow: View {
    let icon: String
    let title: String
    let description: String
    let iconColor: Color

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 48, height: 48)

                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundStyle(iconColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.custom("OpenSans-Bold", size: 16))
                    .foregroundStyle(.white)

                Text(description)
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.white.opacity(0.6))
            }

            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.white.opacity(0.05))
        )
    }
}

// MARK: - Pricing Card

struct PricingCard: View {
    let product: Product
    let isSelected: Bool
    let badge: String?
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(product.displayName)
                            .font(.custom("OpenSans-Bold", size: 18))
                            .foregroundStyle(.white)

                        if let badge = badge {
                            Text(badge)
                                .font(.custom("OpenSans-Bold", size: 11))
                                .foregroundStyle(Color(red: 1.0, green: 0.6, blue: 0.0))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(Color(red: 1.0, green: 0.6, blue: 0.0).opacity(0.2))
                                )
                        }
                    }

                    Spacer()

                    Text(product.displayPrice)
                        .font(.custom("OpenSans-Bold", size: 24))
                        .foregroundStyle(.white)
                }

                Text(product.description)
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(2)
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(isSelected ? Color(red: 1.0, green: 0.6, blue: 0.0).opacity(0.2) : Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(
                                isSelected ?
                                    LinearGradient(
                                        colors: [Color(red: 1.0, green: 0.6, blue: 0.0), Color(red: 1.0, green: 0.4, blue: 0.2)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ) :
                                    LinearGradient(colors: [.clear], startPoint: .top, endPoint: .bottom),
                                lineWidth: 2
                            )
                    )
            )
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
