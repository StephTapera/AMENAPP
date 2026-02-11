//
//  GivingNonprofitsDetailView.swift
//  AMENAPP
//
//  Created by Steph on 2/2/26.
//

import SwiftUI

struct GivingNonprofitsDetailView: View {
    @State private var selectedCategory: NonprofitCategory = .all
    @State private var showingDonationInfo = false
    
    enum NonprofitCategory: String, CaseIterable {
        case all = "All"
        case missions = "Missions"
        case humanitarian = "Humanitarian"
        case youth = "Youth & Education"
        case local = "Local Church"
        case global = "Global Impact"
    }
    
    var filteredNonprofits: [ChristianNonprofit] {
        guard selectedCategory != .all else {
            return ChristianNonprofit.allNonprofits
        }
        return ChristianNonprofit.allNonprofits.filter { $0.category == selectedCategory }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Hero Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(.blue.opacity(0.15))
                                .frame(width: 64, height: 64)
                            
                            Image(systemName: "heart.circle.fill")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundStyle(.blue)
                                .symbolEffect(.pulse, options: .repeating.speed(0.8))
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Giving & Nonprofits")
                                .font(.custom("OpenSans-Bold", size: 28))
                                .foregroundStyle(.primary)
                            
                            Text("Make an eternal impact")
                                .font(.custom("OpenSans-Regular", size: 16))
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Text("\"Each of you should give what you have decided in your heart to give, not reluctantly or under compulsion, for God loves a cheerful giver.\" - 2 Corinthians 9:7")
                        .font(.custom("OpenSans-Regular", size: 15))
                        .foregroundStyle(.secondary)
                        .italic()
                        .lineSpacing(4)
                }
                .padding(.horizontal)
                .padding(.top)
                
                // Giving Impact Stats
                givingImpactCard
                
                // Category Filter
                categoryPicker
                
                // Featured Nonprofits
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(filteredNonprofits) { nonprofit in
                        NonprofitCard(nonprofit: nonprofit)
                    }
                }
                .padding(.horizontal)
                
                // Ways to Give
                waysToGiveSection
                
                // Tax Info
                taxInfoSection
                
                Spacer(minLength: 40)
            }
            .padding(.vertical)
        }
        .navigationTitle("Giving")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingDonationInfo) {
            DonationInfoSheet()
        }
    }
    
    private var givingImpactCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Why Give?")
                .font(.custom("OpenSans-Bold", size: 18))
                .foregroundStyle(.primary)
            
            VStack(spacing: 12) {
                ImpactRow(
                    icon: "heart.fill",
                    title: "Lives Changed",
                    description: "Your giving transforms lives through the Gospel",
                    color: .red
                )
                
                ImpactRow(
                    icon: "globe.americas.fill",
                    title: "Global Reach",
                    description: "Support missions reaching every corner of the world",
                    color: .blue
                )
                
                ImpactRow(
                    icon: "hands.sparkles.fill",
                    title: "Kingdom Work",
                    description: "Advance God's kingdom through strategic giving",
                    color: .purple
                )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        )
        .padding(.horizontal)
    }
    
    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(NonprofitCategory.allCases, id: \.self) { category in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedCategory = category
                        }
                        
                        let haptic = UIImpactFeedbackGenerator(style: .light)
                        haptic.impactOccurred()
                    } label: {
                        Text(category.rawValue)
                            .font(.custom("OpenSans-SemiBold", size: 14))
                            .foregroundStyle(selectedCategory == category ? .white : .primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(selectedCategory == category ? Color.blue : Color(.systemGray6))
                            )
                    }
                }
            }
            .padding(.horizontal)
        }
    }
    
    private var waysToGiveSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Ways to Give")
                .font(.custom("OpenSans-Bold", size: 20))
                .foregroundStyle(.primary)
                .padding(.horizontal)
            
            VStack(spacing: 10) {
                WaysToGiveCard(
                    icon: "creditcard.fill",
                    title: "One-Time Gift",
                    description: "Make a single donation to support a cause",
                    color: .blue
                )
                
                WaysToGiveCard(
                    icon: "arrow.clockwise",
                    title: "Recurring Giving",
                    description: "Set up monthly or yearly donations",
                    color: .green
                )
                
                WaysToGiveCard(
                    icon: "building.columns.fill",
                    title: "Donor-Advised Fund",
                    description: "Strategic giving through a charitable fund",
                    color: .purple
                )
                
                WaysToGiveCard(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "Appreciated Assets",
                    description: "Donate stocks, real estate, or other assets",
                    color: .orange
                )
            }
            .padding(.horizontal)
            
            Button {
                showingDonationInfo = true
            } label: {
                HStack {
                    Image(systemName: "info.circle.fill")
                    Text("Learn About Tax Benefits")
                        .font(.custom("OpenSans-SemiBold", size: 14))
                }
                .foregroundStyle(.blue)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.blue.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(.blue.opacity(0.3), lineWidth: 1)
                        )
                )
            }
            .padding(.horizontal)
        }
    }
    
    private var taxInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.green)
                
                Text("Tax-Deductible Giving")
                    .font(.custom("OpenSans-Bold", size: 18))
                    .foregroundStyle(.primary)
            }
            
            Text("All featured nonprofits are 501(c)(3) organizations. Your donations may be tax-deductible. Consult with a tax professional for specific guidance.")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
                .lineSpacing(3)
            
            Text("Always verify organizations through the IRS Tax Exempt Organization Search or Charity Navigator before donating.")
                .font(.custom("OpenSans-Regular", size: 13))
                .foregroundStyle(.secondary)
                .lineSpacing(3)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.green.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(.green.opacity(0.3), lineWidth: 1)
                )
        )
        .padding(.horizontal)
    }
}

// MARK: - Nonprofit Card

struct NonprofitCard: View {
    let nonprofit: ChristianNonprofit
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(nonprofit.color.opacity(0.15))
                        .frame(width: 60, height: 60)
                    
                    Image(systemName: nonprofit.icon)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(nonprofit.color)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(nonprofit.name)
                        .font(.custom("OpenSans-Bold", size: 18))
                        .foregroundStyle(.primary)
                    
                    HStack(spacing: 6) {
                        if nonprofit.isVerified {
                            HStack(spacing: 3) {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 11))
                                Text("Verified")
                                    .font(.custom("OpenSans-SemiBold", size: 11))
                            }
                            .foregroundStyle(.green)
                        }
                        
                        Text(nonprofit.category.rawValue)
                            .font(.custom("OpenSans-SemiBold", size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
            }
            
            // Description
            Text(nonprofit.description)
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
                .lineSpacing(3)
            
            // Impact Stats
            if !nonprofit.impactStats.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Impact")
                        .font(.custom("OpenSans-Bold", size: 13))
                        .foregroundStyle(.primary)
                    
                    ForEach(nonprofit.impactStats.prefix(3), id: \.self) { stat in
                        HStack(spacing: 6) {
                            Image(systemName: "chart.bar.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(nonprofit.color)
                            
                            Text(stat)
                                .font(.custom("OpenSans-Regular", size: 13))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            
            // Actions
            HStack(spacing: 10) {
                Button {
                    if let url = URL(string: nonprofit.websiteURL) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.right.circle.fill")
                        Text("Visit Website")
                            .font(.custom("OpenSans-Bold", size: 14))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(nonprofit.color)
                    )
                }
                
                if let donateURL = nonprofit.donateURL {
                    Button {
                        if let url = URL(string: donateURL) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "heart.fill")
                            Text("Donate")
                                .font(.custom("OpenSans-Bold", size: 14))
                        }
                        .foregroundStyle(nonprofit.color)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(nonprofit.color.opacity(0.15))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(nonprofit.color.opacity(0.3), lineWidth: 1)
                                )
                        )
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.3),
                                    Color.white.opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
    }
}

// MARK: - Supporting Views

struct ImpactRow: View {
    let icon: String
    let title: String
    let description: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(color)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.custom("OpenSans-Bold", size: 14))
                    .foregroundStyle(.primary)
                
                Text(description)
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
            }
        }
    }
}

struct WaysToGiveCard: View {
    let icon: String
    let title: String
    let description: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 44, height: 44)
                
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(color)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.custom("OpenSans-Bold", size: 15))
                    .foregroundStyle(.primary)
                
                Text(description)
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
            }
            
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }
}

// MARK: - Donation Info Sheet

struct DonationInfoSheet: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Tax Benefits of Charitable Giving")
                            .font(.custom("OpenSans-Bold", size: 24))
                            .foregroundStyle(.primary)
                        
                        Text("Understanding how charitable donations can reduce your tax burden")
                            .font(.custom("OpenSans-Regular", size: 15))
                            .foregroundStyle(.secondary)
                    }
                    
                    TaxBenefitSection(
                        title: "Standard Deduction vs. Itemizing",
                        content: "To claim charitable deductions, you must itemize deductions on Schedule A. Compare this to the standard deduction ($13,850 single / $27,700 married for 2023) to see which benefits you more."
                    )
                    
                    TaxBenefitSection(
                        title: "Cash Donations",
                        content: "You can generally deduct up to 60% of your adjusted gross income (AGI) for cash donations to qualified organizations."
                    )
                    
                    TaxBenefitSection(
                        title: "Appreciated Assets",
                        content: "Donating stocks, bonds, or real estate held for over one year can allow you to deduct the fair market value and avoid capital gains taxes."
                    )
                    
                    TaxBenefitSection(
                        title: "Record Keeping",
                        content: "Keep receipts and acknowledgment letters from organizations. Donations of $250+ require written acknowledgment."
                    )
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("⚠️ Important Disclaimer")
                            .font(.custom("OpenSans-Bold", size: 14))
                            .foregroundStyle(.orange)
                        
                        Text("This information is for educational purposes only. Always consult with a qualified tax professional or CPA for personalized advice based on your specific financial situation.")
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.secondary)
                            .lineSpacing(3)
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.orange.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(.orange.opacity(0.3), lineWidth: 1)
                            )
                    )
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

struct TaxBenefitSection: View {
    let title: String
    let content: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.custom("OpenSans-Bold", size: 16))
                .foregroundStyle(.primary)
            
            Text(content)
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
                .lineSpacing(4)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

// MARK: - Data Models

struct ChristianNonprofit: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let category: GivingNonprofitsDetailView.NonprofitCategory
    let icon: String
    let color: Color
    let websiteURL: String
    let donateURL: String?
    let isVerified: Bool
    let impactStats: [String]
    
    static let allNonprofits = [
        // Missions
        ChristianNonprofit(
            name: "Samaritan's Purse",
            description: "International relief organization providing spiritual and physical aid to hurting people around the world.",
            category: .missions,
            icon: "cross.case.fill",
            color: .red,
            websiteURL: "https://www.samaritanspurse.org",
            donateURL: "https://www.samaritanspurse.org/donate",
            isVerified: true,
            impactStats: [
                "Active in over 100 countries",
                "Operation Christmas Child reaches millions",
                "Disaster relief and medical care"
            ]
        ),
        ChristianNonprofit(
            name: "Compassion International",
            description: "Child sponsorship organization releasing children from poverty in Jesus' name.",
            category: .missions,
            icon: "heart.circle.fill",
            color: .blue,
            websiteURL: "https://www.compassion.com",
            donateURL: "https://www.compassion.com/sponsor-a-child.htm",
            isVerified: true,
            impactStats: [
                "2+ million children sponsored",
                "Operating in 27 countries",
                "Holistic child development"
            ]
        ),
        ChristianNonprofit(
            name: "World Vision",
            description: "Global humanitarian organization dedicated to working with children, families, and communities.",
            category: .missions,
            icon: "globe.americas.fill",
            color: .green,
            websiteURL: "https://www.worldvision.org",
            donateURL: "https://www.worldvision.org/donate",
            isVerified: true,
            impactStats: [
                "Serving nearly 100 countries",
                "Water projects reach millions",
                "Emergency relief response"
            ]
        ),
        
        // Humanitarian
        ChristianNonprofit(
            name: "Food for the Hungry",
            description: "Ending all forms of poverty by providing emergency relief, clean water, and education.",
            category: .humanitarian,
            icon: "heart.fill",
            color: .orange,
            websiteURL: "https://www.fh.org",
            donateURL: "https://www.fh.org/donate",
            isVerified: true,
            impactStats: [
                "Graduated 80+ communities from poverty",
                "Clean water for 1M+ people",
                "Education programs in 20+ countries"
            ]
        ),
        ChristianNonprofit(
            name: "International Justice Mission",
            description: "Protecting the poor from violence by rescuing victims, bringing criminals to justice.",
            category: .humanitarian,
            icon: "shield.fill",
            color: .purple,
            websiteURL: "https://www.ijm.org",
            donateURL: "https://www.ijm.org/donate",
            isVerified: true,
            impactStats: [
                "Protected 70+ million from slavery",
                "Active in 31 offices worldwide",
                "Legal system transformation"
            ]
        ),
        ChristianNonprofit(
            name: "Convoy of Hope",
            description: "Feeding the world through children's feeding initiatives, community outreaches, and disaster response.",
            category: .humanitarian,
            icon: "truck.box.fill",
            color: .red,
            websiteURL: "https://www.convoyofhope.org",
            donateURL: "https://www.convoyofhope.org/donate",
            isVerified: true,
            impactStats: [
                "500K+ children fed daily",
                "Served 130+ million people",
                "Rapid disaster response team"
            ]
        ),
        
        // Youth & Education
        ChristianNonprofit(
            name: "Young Life",
            description: "Reaching adolescents with the Gospel and helping them grow in their faith.",
            category: .youth,
            icon: "person.3.fill",
            color: .blue,
            websiteURL: "https://www.younglife.org",
            donateURL: "https://www.younglife.org/Donate",
            isVerified: true,
            impactStats: [
                "Active in 100+ countries",
                "Reaching 2+ million kids",
                "Faith-based mentoring"
            ]
        ),
        ChristianNonprofit(
            name: "Fellowship of Christian Athletes",
            description: "Impacting the world for Jesus Christ through sports ministry.",
            category: .youth,
            icon: "sportscourt.fill",
            color: .green,
            websiteURL: "https://www.fca.org",
            donateURL: "https://www.fca.org/donate",
            isVerified: true,
            impactStats: [
                "2+ million student athletes reached",
                "10,000+ coaches involved",
                "Faith and sports combined"
            ]
        ),
        
        // Global Impact
        ChristianNonprofit(
            name: "The Salvation Army",
            description: "Meeting human needs without discrimination, preaching the gospel of Jesus Christ.",
            category: .global,
            icon: "building.2.fill",
            color: .red,
            websiteURL: "https://www.salvationarmyusa.org",
            donateURL: "https://www.salvationarmyusa.org/usn/ways-to-give",
            isVerified: true,
            impactStats: [
                "Operating in 130+ countries",
                "30+ million served annually",
                "Disaster relief and social services"
            ]
        ),
        ChristianNonprofit(
            name: "Habitat for Humanity",
            description: "Building strength, stability, and self-reliance through affordable homeownership.",
            category: .global,
            icon: "house.fill",
            color: .blue,
            websiteURL: "https://www.habitat.org",
            donateURL: "https://www.habitat.org/donate",
            isVerified: true,
            impactStats: [
                "46+ million people served",
                "Operating in 70+ countries",
                "Faith-driven housing solutions"
            ]
        )
    ]
}

#Preview {
    NavigationStack {
        GivingNonprofitsDetailView()
    }
}
