//
//  GivingNonprofitsSection.swift
//  AMENAPP
//
//  Created by Steph on 2/2/26.
//

import SwiftUI

// MARK: - Giving & Nonprofits Section
struct GivingNonprofitsSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.pink)
                    .symbolEffect(.pulse, options: .repeating.speed(0.8))
                Text("Giving & Nonprofits")
                    .font(.custom("OpenSans-Bold", size: 20))
            }
            .padding(.horizontal)
            
            // Featured: Set Up Giving Fund
            GivingFeaturedCard(
                icon: "dollarsign.circle.fill",
                iconColor: .green,
                title: "Set Up Your Giving Fund",
                subtitle: "Automate your charitable giving",
                description: "Create a personal giving fund to support multiple ministries and causes you care about.",
                actionTitle: "Get Started",
                gradientColors: [Color.green, Color.mint]
            )
            
            // Featured Christian Nonprofits Section
            VStack(alignment: .leading, spacing: 12) {
                Text("Featured Nonprofits")
                    .font(.custom("OpenSans-Bold", size: 17))
                    .foregroundStyle(.primary)
                    .padding(.horizontal)
                
                // Compassion International
                NonprofitCard(
                    name: "Compassion International",
                    category: "Child Sponsorship",
                    icon: "heart.circle.fill",
                    iconColor: .red,
                    description: "Sponsor a child and help break the cycle of poverty",
                    website: "https://www.compassion.com"
                )
                
                // Samaritan's Purse
                NonprofitCard(
                    name: "Samaritan's Purse",
                    category: "Disaster Relief",
                    icon: "cross.fill",
                    iconColor: .orange,
                    description: "International relief and evangelism ministry",
                    website: "https://www.samaritanspurse.org"
                )
                
                // World Vision
                NonprofitCard(
                    name: "World Vision",
                    category: "Global Humanitarian",
                    icon: "globe.americas.fill",
                    iconColor: .blue,
                    description: "Christian humanitarian organization serving children worldwide",
                    website: "https://www.worldvision.org"
                )
                
                // The Salvation Army
                NonprofitCard(
                    name: "The Salvation Army",
                    category: "Community Services",
                    icon: "building.2.fill",
                    iconColor: .red,
                    description: "Meeting human needs without discrimination",
                    website: "https://www.salvationarmyusa.org"
                )
                
                // Habitat for Humanity
                NonprofitCard(
                    name: "Habitat for Humanity",
                    category: "Housing & Shelter",
                    icon: "house.fill",
                    iconColor: .green,
                    description: "Building homes, communities, and hope",
                    website: "https://www.habitat.org"
                )
            }
            
            // Browse More Nonprofits
            BrowseNonprofitsCard()
            
            // Monthly Giving Info Card
            MonthlyGivingInfoCard()
        }
    }
}

// MARK: - Giving Featured Card
struct GivingFeaturedCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let description: String
    let actionTitle: String
    let gradientColors: [Color]
    
    @State private var shimmerPhase: CGFloat = 0
    @State private var showComingSoon = false
    
    var body: some View {
        Button {
            showComingSoon = true
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 52, height: 52)
                            .overlay(
                                Circle()
                                    .stroke(
                                        LinearGradient(
                                            colors: [iconColor.opacity(0.6), iconColor.opacity(0.2)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 2
                                    )
                            )
                        
                        Image(systemName: icon)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(iconColor)
                    }
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.custom("OpenSans-Bold", size: 17))
                            .foregroundStyle(.white)
                        
                        Text(subtitle)
                            .font(.custom("OpenSans-SemiBold", size: 13))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    
                    Spacer()
                }
                
                Text(description)
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.white.opacity(0.95))
                    .lineSpacing(3)
                
                HStack {
                    Spacer()
                    HStack(spacing: 6) {
                        Text(actionTitle)
                            .font(.custom("OpenSans-Bold", size: 14))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    Spacer()
                }
                .padding(.vertical, 12)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Capsule()
                                .stroke(.white.opacity(0.4), lineWidth: 1.5)
                        )
                )
            }
            .padding(18)
            .background(
                ZStack {
                    // Base gradient
                    LinearGradient(
                        colors: gradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    
                    // Glass overlay
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .opacity(0.3)
                    
                    // Shimmer effect
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0),
                            Color.white.opacity(0.2),
                            Color.white.opacity(0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .offset(x: shimmerPhase)
                    .blur(radius: 25)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.3), .white.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            )
            .shadow(color: gradientColors[0].opacity(0.3), radius: 16, x: 0, y: 8)
            .shadow(color: .black.opacity(0.1), radius: 6, x: 0, y: 3)
            .padding(.horizontal)
            .onAppear {
                withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                    shimmerPhase = 400
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showComingSoon) {
            ResourceComingSoonPlaceholder(
                title: "Giving Fund",
                icon: "dollarsign.circle.fill",
                iconColor: .green,
                description: "Set up automated giving to support multiple ministries and causes. Track your donations, receive tax receipts, and make a lasting impact with consistent generosity."
            )
        }
    }
}

// MARK: - Nonprofit Card
struct NonprofitCard: View {
    let name: String
    let category: String
    let icon: String
    let iconColor: Color
    let description: String
    let website: String
    
    @State private var showAlert = false
    
    var body: some View {
        Button {
            showAlert = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(0.15))
                        .frame(width: 52, height: 52)
                    
                    Image(systemName: icon)
                        .font(.system(size: 22))
                        .foregroundStyle(iconColor)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(name)
                        .font(.custom("OpenSans-Bold", size: 15))
                        .foregroundStyle(.primary)
                    
                    Text(category)
                        .font(.custom("OpenSans-SemiBold", size: 11))
                        .foregroundStyle(iconColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(iconColor.opacity(0.1))
                        )
                    
                    Text(description)
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .padding(.top, 2)
                }
                
                Spacer()
                
                Image(systemName: "arrow.up.right.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(iconColor)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
            )
            .padding(.horizontal)
        }
        .buttonStyle(PlainButtonStyle())
        .alert("Visit \(name)?", isPresented: $showAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Open Website") {
                if let url = URL(string: website) {
                    UIApplication.shared.open(url)
                }
            }
        } message: {
            Text("This will open \(name)'s website in Safari where you can learn more and donate.")
        }
    }
}

// MARK: - Browse Nonprofits Card
struct BrowseNonprofitsCard: View {
    @State private var showComingSoon = false
    
    var body: some View {
        Button {
            showComingSoon = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.purple.opacity(0.15))
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 22))
                        .foregroundStyle(.purple)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("Browse More Nonprofits")
                            .font(.custom("OpenSans-Bold", size: 16))
                            .foregroundStyle(.primary)
                        
                        Text("COMING SOON")
                            .font(.custom("OpenSans-Bold", size: 9))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color.orange)
                            )
                    }
                    
                    Text("Discover verified Christian nonprofits by category")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.purple.opacity(0.3), lineWidth: 1.5)
                    )
                    .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
            )
            .padding(.horizontal)
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showComingSoon) {
            ResourceComingSoonPlaceholder(
                title: "Browse Nonprofits",
                icon: "magnifyingglass",
                iconColor: .purple,
                description: "Explore hundreds of verified Christian nonprofits organized by category. Find ministries aligned with your passions and make a difference where it matters most to you."
            )
        }
    }
}

// MARK: - Monthly Giving Info Card
struct MonthlyGivingInfoCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 20))
                    .foregroundStyle(.blue)
                
                Text("Why Monthly Giving?")
                    .font(.custom("OpenSans-Bold", size: 15))
                    .foregroundStyle(.primary)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                GivingBenefitRow(
                    icon: "chart.line.uptrend.xyaxis",
                    text: "Maximize your impact with consistent support"
                )
                GivingBenefitRow(
                    icon: "gear.circle.fill",
                    text: "Automate your generosity and simplify giving"
                )
                GivingBenefitRow(
                    icon: "doc.text.fill",
                    text: "Simplified tax records and annual receipts"
                )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.blue.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                )
        )
        .padding(.horizontal)
    }
}

// MARK: - Giving Benefit Row
struct GivingBenefitRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(.blue)
                .frame(width: 20)
            
            Text(text)
                .font(.custom("OpenSans-Regular", size: 13))
                .foregroundStyle(.primary)
                .lineSpacing(2)
        }
    }
}

#Preview {
    ScrollView {
        GivingNonprofitsSection()
    }
}
